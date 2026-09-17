//
//  UsageParser.swift — แปลง JSON จาก `claude-usage.sh --json` → UsageSnapshot
//
//  พอร์ตตรงจาก `toRows()` + render path ใน claude-usage.jsx
//
//  หลักสำคัญ: response จริงมีฟิลด์ `null` เต็มไปหมด (seven_day_opus, tangelo, scope, …)
//  และ schema ฝั่ง Anthropic ขยับได้ตลอด → ห้ามใช้ Codable แบบเข้มงวด, ใช้ JSONSerialization
//  แล้วอ่านทีละคีย์แบบยอมให้หายได้ทุกจุด
//

import Foundation

public struct UsageParser {

    public init() {}

    public static func parse(_ json: Data) throws -> UsageSnapshot {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed])
        } catch {
            throw UsageError.invalidOutput(detail: preview(json))
        }
        guard let dict = object as? [String: Any] else {
            throw UsageError.invalidOutput(detail: preview(json))
        }
        return snapshot(from: dict)
    }

    /// แปลง dictionary ที่ parse แล้ว (แยกออกมาเพื่อให้เทสต์ป้อน dict ตรงๆ ได้)
    public static func snapshot(from dict: [String: Any]) -> UsageSnapshot {
        let statusRaw = string(dict["_status"])
        let errorCode = string(dict["_error"])

        // jsx: `!data || status === "error"` → การ์ด error, `status === "stale"` → เหลือง,
        //      นอกนั้น (รวมกรณีไม่มี _status) → เขียว
        let status: FetchStatus
        switch statusRaw {
        case "error":
            let info = ErrorInfo.info(for: errorCode)
            status = .error(message: info.message, needsLogin: info.needsLogin)
        case "stale":
            status = .stale(reason: ErrorInfo.info(for: errorCode).short)
        default:
            status = .live
        }

        return UsageSnapshot(limits: limits(from: dict),
                             plan: string(dict["_plan"]),
                             fetchedAt: ISODate.parse(string(dict["_fetched_at"])),
                             status: status,
                             errorCode: errorCode)
    }

    // MARK: - limits

    private static func limits(from dict: [String: Any]) -> [UsageLimit] {
        let raw = (dict["limits"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        if !raw.isEmpty {
            return raw.compactMap(limit(from:))
        }
        // fallback: บัญชี/เวอร์ชันที่ไม่มี limits[] — ใช้ five_hour / seven_day
        let fh = dict["five_hour"] as? [String: Any] ?? [:]
        let sd = dict["seven_day"] as? [String: Any] ?? [:]
        let session = number(fh["utilization"])
        let weekly = number(sd["utilization"])
        // ⚠️ ไม่มีตัวเลขสักตัว → คืน [] (jsx ดันแถว 0% เสมอ = โกหกผู้ใช้ทับข้อมูลดี)
        // กติกา "ผลไม่มีแถว = คงข้อมูลเดิม" ของ UsageViewModel ถึงจะทำงาน
        guard session != nil || weekly != nil else { return [] }
        return [
            UsageLimit(id: "session", kind: .session, title: Title.session,
                       percent: session ?? 0,
                       resetsAt: ISODate.parse(string(fh["resets_at"]))),
            UsageLimit(id: "weekly_all", kind: .weeklyAll, title: Title.weeklyAll,
                       percent: weekly ?? 0,
                       resetsAt: ISODate.parse(string(sd["resets_at"]))),
        ]
    }

    private static func limit(from raw: [String: Any]) -> UsageLimit? {
        guard let kindRaw = string(raw["kind"]), let kind = LimitKind(rawValue: kindRaw) else {
            return nil // kind แปลกใหม่ → ข้าม (jsx ก็ไม่สร้างแถว)
        }
        let percent = number(raw["percent"]) ?? 0
        let resetsAt = ISODate.parse(string(raw["resets_at"]))
        switch kind {
        case .session:
            return UsageLimit(id: "session", kind: .session, title: Title.session,
                              percent: percent, resetsAt: resetsAt)
        case .weeklyAll:
            return UsageLimit(id: "weekly_all", kind: .weeklyAll, title: Title.weeklyAll,
                              percent: percent, resetsAt: resetsAt)
        case .weeklyScoped:
            // ⚠️ ห้ามกรอง percent > 0 ทิ้ง — วันแรกของสัปดาห์ที่ยัง 0% ต้องโชว์
            // ไม่งั้น anchor ของวันนั้นไม่ถูกตั้ง (บั๊กจริง ดู CLAUDE.md)
            let model = (raw["scope"] as? [String: Any])?["model"] as? [String: Any]
            let name = string(model?["display_name"]) ?? Title.unknownModel
            return UsageLimit(id: "weekly_scoped:" + name, kind: .weeklyScoped,
                              title: Title.weeklyScoped(name), percent: percent, resetsAt: resetsAt)
        }
    }

    /// ข้อความไทยของแต่ละแถว — ต้องตรงกับ `toRows()` ใน claude-usage.jsx เป๊ะ
    public enum Title {
        public static let session = "เซสชันปัจจุบัน"
        public static let weeklyAll = "สัปดาห์นี้ (ทุกโมเดล)"
        public static let unknownModel = "โมเดล"
        public static func weeklyScoped(_ model: String) -> String { "สัปดาห์ · " + model }
    }

    // MARK: - ตัวช่วยอ่านค่าแบบยอมให้ null/ผิดชนิดได้

    /// คืน nil ถ้าเป็น NSNull / ไม่ใช่สตริง / สตริงว่าง
    static func string(_ any: Any?) -> String? {
        guard let s = any as? String, !s.isEmpty else { return nil }
        return s
    }

    /// รับได้ทั้ง Int/Double/NSNumber และสตริงตัวเลข; nil เมื่อ null/ผิดชนิด
    static func number(_ any: Any?) -> Double? {
        if let n = any as? NSNumber, !(any is NSNull) { return n.doubleValue }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func preview(_ data: Data) -> String {
        let text = String(decoding: data.prefix(400), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(ไม่มีข้อมูล)" : text
    }
}
