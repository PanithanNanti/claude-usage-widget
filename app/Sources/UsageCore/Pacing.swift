//
//  Pacing.swift — เป้าใช้งานรายวัน (daily pacing) สำหรับ weekly limits
//
//  พอร์ตตรงจาก `dailyBudget()` + `capScopedBudget()` ใน claude-usage.jsx
//
//  หลักการ: แบ่งโควตาที่ "เหลือจริง" เท่าๆ กันตามจำนวนวันที่เหลือถึงรีเซ็ต
//    เป้าวันนี้ = anchor.pct + (100 − anchor.pct) / anchor.days
//  โดย anchor = ค่า % ตอนต้นวัน (ตรึงไว้ทั้งวัน เป้าจึงไม่วิ่งหนีตามการใช้ระหว่างวัน)
//  → วันไหนใช้เกิน/ต่ำกว่าเป้า โควตาต่อวันของวันถัดไปจะหด/ขยายเองอัตโนมัติ
//
//  daysLeft เป็นเศษทศนิยมเป๊ะตามชั่วโมง (เช่น 4.18 วัน) — วันรีเซ็ตที่เหลือ <1 วัน
//  จะหารด้วยค่า <1 ทำให้เป้าพุ่งชน cap 100 = ปลดล็อกโควตาที่เหลือทั้งหมด
//

import Foundation

// MARK: - DailyBudget

public struct DailyBudget: Equatable, Hashable, Sendable {
    /// เป้า % ของวันนี้ — clamp 0...100 แล้ว (เป้าติดลบตอนโดนแคป → 0)
    public let target: Double
    /// ใช้ได้อีกกี่ % ก่อนถึงเป้า (ติดลบ = เกินเป้าไปแล้ว)
    /// คิดจากเป้า**ก่อน clamp** เพื่อให้ตัวเลข "เกินเป้า +X%" ตรงกับ widget เดิม
    public let remaining: Double
    /// เหลือกี่วันถึงรีเซ็ต (เศษทศนิยม) — ค่า ณ ตอนนี้ ไม่ใช่ตอน anchor
    public let daysLeft: Double
    /// true = เป้าถูกหั่นลงเพราะโควตา weekly รวมเหลือไม่พอ ("จำกัดโดยโควตาสัปดาห์รวม")
    public let cappedByWeekly: Bool

    public init(target: Double, remaining: Double, daysLeft: Double, cappedByWeekly: Bool) {
        self.target = target
        self.remaining = remaining
        self.daysLeft = daysLeft
        self.cappedByWeekly = cappedByWeekly
    }

    /// เป้าที่ปัดแล้วสำหรับข้อความ (เหมือน `Math.max(0, Math.round(b.target))` ใน jsx)
    public var displayTarget: Int { Int(max(0, target).rounded()) }
    /// ใช้เกินเป้าของวันนี้ไปแล้วหรือยัง
    public var isOverTarget: Bool { remaining < 0 }
}

// MARK: - Anchor

/// ค่าที่ตรึงไว้ตอนต้นวัน (เก็บถาวรข้ามการเปิด/ปิดแอป)
public struct Anchor: Codable, Equatable, Hashable, Sendable {
    /// วันที่แบบ local "YYYY-MM-DD"
    public var day: String
    /// % ณ ตอน anchor
    public var pct: Double
    /// จำนวนวันที่เหลือ ณ ตอน anchor — เป้าทั้งวันคิดจากค่านี้ จึงคงที่ทั้งวัน
    public var days: Double
    /// คีย์ของรอบสัปดาห์ (จาก `ISODate.resetKey`) — เปลี่ยน = ขึ้นรอบใหม่ → anchor ใหม่
    public var reset: String

    public init(day: String, pct: Double, days: Double, reset: String) {
        self.day = day
        self.pct = pct
        self.days = days
        self.reset = reset
    }
}

// MARK: - AnchorStore

public protocol AnchorStore: AnyObject {
    func load() -> [String: Anchor]
    func save(_ anchors: [String: Anchor])
}

/// key เดียวกับ widget เดิม (คนละที่เก็บกันอยู่แล้ว — localStorage vs UserDefaults)
public let anchorDefaultsKey = "claudeUsageDailyAnchor2"

public final class UserDefaultsAnchorStore: AnchorStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = anchorDefaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [String: Anchor] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Anchor].self, from: data)) ?? [:]
    }

    public func save(_ anchors: [String: Anchor]) {
        guard let data = try? JSONEncoder().encode(anchors) else { return }
        defaults.set(data, forKey: key)
    }
}

/// สำหรับเทสต์/พรีวิว
public final class InMemoryAnchorStore: AnchorStore {
    public private(set) var anchors: [String: Anchor]
    public init(_ anchors: [String: Anchor] = [:]) { self.anchors = anchors }
    public func load() -> [String: Anchor] { anchors }
    public func save(_ anchors: [String: Anchor]) { self.anchors = anchors }
}

// MARK: - Pacing

public struct Pacing {
    /// สัดส่วนของ weekly รวมที่ bar per-model (เช่น Fable) กินได้เต็มที่ — กฎ "Fable 50%"
    public static let scopedShare: Double = 0.5

    private let store: AnchorStore
    private let now: () -> Date
    private let calendar: Calendar

    public init(store: AnchorStore,
                now: @escaping () -> Date = Date.init,
                calendar: Calendar = .current) {
        self.store = store
        self.now = now
        self.calendar = calendar
    }

    /// คำนวณเป้ารายวันของทุก weekly limit ใน snapshot
    /// - Returns: key = `UsageLimit.id` (ไม่มี entry ของ `session` — pacing รายวันไม่มีความหมายกับ limit 5 ชม.)
    public func budgets(for snapshot: UsageSnapshot) -> [String: DailyBudget] {
        var anchors = store.load()
        var dirty = false
        let reference = now()
        let today = dayKey(reference)
        let fetchedToday = snapshot.fetchedAt.map { dayKey($0) == today } ?? false

        // weekly_all ต้องคิดก่อน — bar per-model เอาโควตาที่ weekly รวมเหลือให้มาแคปอีกชั้น
        let all = snapshot.limit(kind: .weeklyAll)
        let allPct = all?.percent
        let allBudget: DailyBudget? = all.flatMap {
            budget(id: $0.id, pct: $0.percent, resetsAt: $0.resetsAt,
                   today: today, reference: reference, fetchedToday: fetchedToday,
                   anchors: &anchors, dirty: &dirty)
        }

        var result: [String: DailyBudget] = [:]
        for limit in snapshot.limits {
            switch limit.kind {
            case .session:
                continue
            case .weeklyAll:
                if let b = allBudget { result[limit.id] = b }
            case .weeklyScoped:
                let own = budget(id: limit.id, pct: limit.percent, resetsAt: limit.resetsAt,
                                 today: today, reference: reference, fetchedToday: fetchedToday,
                                 anchors: &anchors, dirty: &dirty)
                if let capped = capScoped(own, pct: limit.percent, allPct: allPct, allBudget: allBudget) {
                    result[limit.id] = capped
                }
            }
        }

        if dirty { store.save(anchors) }
        return result
    }

    // MARK: - dailyBudget()

    private func budget(id: String,
                        pct: Double,
                        resetsAt: Date?,
                        today: String,
                        reference: Date,
                        fetchedToday: Bool,
                        anchors: inout [String: Anchor],
                        dirty: inout Bool) -> DailyBudget? {
        guard let resetsAt else { return nil }
        let secondsLeft = resetsAt.timeIntervalSince(reference)
        guard secondsLeft > 0 else { return nil }
        let daysLeft = secondsLeft / 86_400

        let resetKey = ISODate.resetKey(resetsAt)
        var anchor = anchors[id]
        // anchor ใหม่เมื่อขึ้นวันใหม่/ขึ้นรอบสัปดาห์ใหม่ — เฉพาะจากข้อมูลที่ดึงมา "วันนี้" จริงๆ
        // (กัน cache ค้างจากเมื่อวานมาตั้ง anchor ต่ำเกินตอนเพิ่งตื่นเครื่อง)
        let needsAnchor = anchor == nil || anchor!.day != today || anchor!.reset != resetKey
        if needsAnchor && fetchedToday {
            let fresh = Anchor(day: today, pct: pct, days: daysLeft, reset: resetKey)
            anchors[id] = fresh
            anchor = fresh
            dirty = true
        }
        // ไม่มี anchor ที่ใช้ได้ (ยังไม่เคยเห็นข้อมูลสดของวันนี้ หรือ anchor เป็นของรอบสัปดาห์ก่อน)
        // → ยังบอกเป้าไม่ได้ ต้องรอข้อมูลสด
        guard let a = anchor, a.reset == resetKey else { return nil }

        let rawTarget = min(100, a.pct + (100 - a.pct) / a.days)
        return DailyBudget(target: clamp(rawTarget),
                           remaining: rawTarget - pct,
                           daysLeft: daysLeft,
                           cappedByWeekly: false)
    }

    // MARK: - capScopedBudget()

    /// แคปเป้าของ bar per-model ด้วยโควตาที่ weekly รวมเหลือให้วันนี้
    /// (bar per-model คิด % เทียบแคป 50% ของตัวเอง → 1 จุดบน weekly_all = 2% บน bar นี้)
    func capScoped(_ own: DailyBudget?, pct: Double, allPct: Double?, allBudget: DailyBudget?) -> DailyBudget? {
        guard let own, let allBudget, let allPct else { return own }
        let room = (allBudget.target - allPct) / Pacing.scopedShare
        let capped = min(own.target, pct + room)
        if capped >= own.target - 0.05 { return own } // เส้นตัวเองตึงกว่าอยู่แล้ว
        return DailyBudget(target: clamp(capped),
                           remaining: capped - pct,
                           daysLeft: own.daysLeft,
                           cappedByWeekly: true)
    }

    // MARK: - helpers

    private func clamp(_ v: Double) -> Double { min(100, max(0, v)) }

    /// "YYYY-MM-DD" ตามปฏิทิน/โซนเวลาที่ inject เข้ามา (พอร์ตของ `dayKeyLocal()` ใน jsx)
    func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
