//
//  UsageViewModel.swift — ตัวเดียวที่ถือ "ข้อมูลที่ถูกต้องล่าสุด" ของแอป
//
//  กฎเหล็ก (บทเรียนจาก widget เดิม):
//   1) error หรือผลที่ไม่มี limits **ห้ามวาดทับข้อมูลดี** — เก็บ snapshot เดิมไว้ เปลี่ยนแค่บรรทัดสถานะ
//   2) ห้ามยิงสคริปต์ซ้อนกัน (สคริปต์มี TTL cache 5 นาที + backoff 429 อยู่แล้ว — ยิงรัวไม่ช่วยอะไร)
//   3) ข้อมูลค้างเกิน 1 ชม. ต้อง "เด่น" (17 ส.ค.: widget โชว์เลขของ 4 วันก่อนโดยไม่มีใครรู้)
//      → คิดอายุข้อมูลใหม่ทุกนาทีจาก `tick` ไม่ใช่เฉพาะตอน fetch
//   4) budgets คำนวณครั้งเดียวต่อ snapshot ใหม่ (ไม่ใช่ทุกครั้งที่ View วาด — Pacing เขียน anchor ลงดิสก์ด้วย)
//

import Foundation
import AppKit
import Combine
import SwiftUI
import UsageCore

@MainActor
final class UsageViewModel: ObservableObject {

    /// สถานะที่การ์ด/เมนูบาร์ใช้ — แยกจาก `snapshot.status` เพราะเราเก็บข้อมูลดีไว้แม้รอบล่าสุดจะพัง
    enum Status: Equatable {
        case waiting                                                   // ยังไม่เคยดึงสำเร็จ
        case live                                                      // ข้อมูลสด
        case stale(short: String, needsLogin: Bool)                    // มีข้อมูลเดิม แต่รอบล่าสุดไม่สำเร็จ/ไม่สด
        case failed(message: String, short: String, needsLogin: Bool)  // ไม่มีอะไรจะโชว์เลย
    }

    // MARK: - state ที่ View ดู

    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var budgets: [String: DailyBudget] = [:]
    @Published private(set) var status: Status = .waiting
    @Published private(set) var isFetching = false
    /// เดินทุกนาที — ใช้ทำให้ "รีเซ็ตใน Xชม. Yนาที" และอายุข้อมูลค้างเดินจริง
    @Published private(set) var tick = Date()

    // MARK: - เครื่องมือ

    /// nil = ยังหาสคริปต์ไม่เจอ — หาใหม่ทุกครั้งที่ refresh (ดู `resolveFetcher()`)
    private var fetcher: UsageFetching?
    /// true = ต้องหาสคริปต์เอง (false = ถูกฉีด fetcher มาจากเทสต์/พรีวิว)
    private let locatesScript: Bool
    private let pacing: Pacing
    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// ระยะ refresh ปกติ — ตรงกับ refreshFrequency ของ widget เดิม (10 นาที)
    private let refreshInterval: TimeInterval = 600

    init(fetcher: UsageFetching? = nil, anchorStore: AnchorStore = UserDefaultsAnchorStore()) {
        self.pacing = Pacing(store: anchorStore)
        self.fetcher = fetcher
        self.locatesScript = fetcher == nil
    }

    /// หาสคริปต์ "ตอนจะยิงจริง" ไม่ใช่ตอน init — หาไม่เจอครั้งแรกต้องไม่แปลว่าแอปตายถาวร
    /// (เช่น ติดตั้งสคริปต์ทีหลัง/แก้ env แล้วกด ↻ ต้องใช้ได้เลย) เจอแล้วจำไว้เลย ไม่หาซ้ำ
    private func resolveFetcher() -> UsageFetching? {
        if let fetcher { return fetcher }
        guard locatesScript else { return nil }
        do {
            let found = ScriptUsageFetcher(scriptURL: try ScriptLocator.find())
            fetcher = found
            return found
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .failed(message: message, short: "หาสคริปต์ไม่เจอ", needsLogin: false)
            return nil
        }
    }

    deinit {
        refreshTimer?.invalidate()
        tickTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - lifecycle

    func start() {
        // ใส่เข้า runloop เองในโหมด .common — ไม่งั้นเวลากางเมนูค้างไว้/กำลังลากการ์ด
        // runloop จะสลับเป็น event tracking แล้ว timer หยุดเดินไปเฉยๆ
        let refresher = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let ticker = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick = Date() }
        }
        RunLoop.main.add(refresher, forMode: .common)
        RunLoop.main.add(ticker, forMode: .common)
        refreshTimer = refresher
        tickTimer = ticker
        // ตื่นจาก sleep → หน่วงหน่อยให้ Wi-Fi กลับมาก่อนค่อยยิง (ยิงทันทีมักได้ network error เปล่าๆ)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick = Date()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self?.refresh()
            }
        }
        refresh()
    }

    /// - Parameter force: ข้าม TTL cache ของสคริปต์ (ปุ่ม ↻ / เมนู "รีเฟรชเดี๋ยวนี้" เท่านั้น)
    func refresh(force: Bool = false) {
        guard !isFetching, let fetcher = resolveFetcher() else { return }
        isFetching = true
        Task { [weak self] in
            defer { Task { @MainActor in self?.isFetching = false } }
            do {
                let fresh = try await fetcher.fetch(force: force)
                await MainActor.run { self?.apply(fresh) }
            } catch {
                await MainActor.run { self?.applyFailure(error) }
            }
        }
    }

    // MARK: - ผสมผลลัพธ์เข้ากับสถานะเดิม (กฎข้อ 1)

    private var hasData: Bool { !snapshot.limits.isEmpty }

    private func apply(_ fresh: UsageSnapshot) {
        tick = Date()
        guard !fresh.limits.isEmpty, !fresh.status.isError else {
            // ไม่มีแถวให้วาด (หรือสคริปต์บอก error) → คงข้อมูลเดิมไว้ เปลี่ยนแค่สถานะ
            let info = ErrorInfo.info(for: fresh.errorCode)
            status = hasData
                ? .stale(short: info.short, needsLogin: info.needsLogin)
                : .failed(message: info.message, short: info.short, needsLogin: info.needsLogin)
            return
        }
        snapshot = fresh
        budgets = pacing.budgets(for: fresh)   // คิดครั้งเดียวต่อ snapshot (กฎข้อ 4)
        switch fresh.status {
        case .live:
            status = .live
        case .stale:
            let info = ErrorInfo.info(for: fresh.errorCode)
            status = .stale(short: info.short, needsLogin: info.needsLogin)
        case .error(let message, let needsLogin):
            status = .failed(message: message, short: message, needsLogin: needsLogin)
        }
    }

    private func applyFailure(_ error: Error) {
        tick = Date()
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if hasData {
            status = .stale(short: "ดึงข้อมูลไม่ได้", needsLogin: false)
        } else {
            status = .failed(message: message, short: "ดึงข้อมูลไม่ได้", needsLogin: false)
        }
    }

    // MARK: - ค่าที่ View ใช้ตรงๆ

    var limits: [UsageLimit] { snapshot.limits }

    /// ป้าย plan — ค่า default เดียวกับ widget เดิม
    var plan: String { snapshot.plan ?? "Max (20×)" }

    var needsLogin: Bool {
        switch status {
        case .stale(_, let l), .failed(_, _, let l): return l
        default: return false
        }
    }

    /// ข้อความกลางการ์ดตอนไม่มีข้อมูลเลย (nil = มีข้อมูลให้วาดแถว)
    var errorBody: String? {
        if case .failed(let message, _, _) = status, !hasData { return message }
        return nil
    }

    /// บรรทัดท้ายการ์ด — ตรงกับ footText ของ jsx
    var footText: String {
        let clock = snapshot.fetchedAt.map { ResetFormat.clock($0) } ?? ResetFormat.clock(tick)
        switch status {
        case .waiting: return "กำลังดึงข้อมูล…"
        case .live: return "อัปเดต \(clock) · ทุก 10 นาที"
        case .stale(let short, _): return "ค่าล่าสุด \(clock) · \(short)"
        case .failed(_, let short, _): return hasData ? "ค่าล่าสุด \(clock) · \(short)" : short
        }
    }

    var footColor: Color {
        switch status {
        case .waiting: return Theme.rowReset
        case .live: return Theme.ok
        case .stale: return Theme.warn
        case .failed: return hasData ? Theme.warn : Theme.crit
        }
    }

    // MARK: - ข้อมูลค้าง (กฎข้อ 3)

    /// อายุข้อมูลตอนนี้ (วินาที) — nil ถ้ายังไม่มีข้อมูล
    var dataAge: TimeInterval? {
        guard hasData, let fetched = snapshot.fetchedAt else { return nil }
        return max(0, tick.timeIntervalSince(fetched))
    }

    /// ข้อความแถบเตือน "ข้อมูลค้าง …" — nil เมื่อข้อมูลยังใหม่พอ
    var staleWarning: String? {
        guard let age = dataAge, age >= Metrics.staleWarningSeconds else { return nil }
        let hint: String
        if needsLogin {
            hint = "เปิด Claude เพื่อล็อกอินใหม่"
        } else if case .stale(let short, _) = status {
            hint = short
        } else if case .failed(_, let short, _) = status {
            hint = short
        } else {
            hint = "กด ↻ เพื่อลองดึงใหม่"
        }
        return "ข้อมูลค้าง \(Self.ageText(age)) — \(hint)"
    }

    static func ageText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days) วัน \(hours) ชม." }
        return "\(hours) ชม. \(minutes) นาที"
    }

    // MARK: - เมนูบาร์

    var sessionPercent: Int? {
        snapshot.limit(kind: .session).map(\.displayPercent)
    }

    /// สรุปสั้นๆ บรรทัดแรกของเมนู
    var menuSummary: String {
        guard hasData else { return "ยังไม่มีข้อมูล" }
        var parts: [String] = []
        for limit in snapshot.limits {
            switch limit.kind {
            case .session: parts.append("เซสชัน \(limit.displayPercent)%")
            case .weeklyAll: parts.append("สัปดาห์ \(limit.displayPercent)%")
            case .weeklyScoped: continue
            }
        }
        return parts.isEmpty ? "ยังไม่มีข้อมูล" : parts.joined(separator: " · ")
    }

    /// บรรทัดที่สองของเมนู — สถานะ + อายุข้อมูล
    var menuStatusLine: String {
        if isFetching { return "กำลังดึงข้อมูล…" }
        if let warning = staleWarning { return warning }
        switch status {
        case .waiting: return "กำลังดึงข้อมูล…"
        case .live: return footText
        case .stale(let short, _): return "\(footText) (\(short))"
        case .failed(let message, _, _): return hasData ? footText : message
        }
    }

    /// สีตัวอักษรบนเมนูบาร์ — nil = ใช้สีปกติของเมนูบาร์
    var menuBarColor: NSColor? {
        if staleWarning != nil { return NSColor(hex: 0xf0a728) }
        switch status {
        case .failed where !hasData: return NSColor(hex: 0xf0554a)
        case .stale, .failed: return NSColor(hex: 0xf0a728)
        default: break
        }
        guard let pct = sessionPercent else { return nil }
        if pct >= 95 { return NSColor(hex: 0xf0554a) }
        if pct >= 80 { return NSColor(hex: 0xf0a728) }
        return nil
    }

    var menuBarText: String {
        let mark = (staleWarning != nil || status == .waiting || errorBody != nil) ? "⚠︎" : "✳"
        guard let pct = sessionPercent else { return "\(mark) —" }
        return "\(mark) \(pct)%"
    }
}
