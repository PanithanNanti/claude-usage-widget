//
//  Models.swift — ชนิดข้อมูลหลักของ UsageCore
//
//  พอร์ตมาจาก claude-usage.jsx (toRows / sessionPct / errInfo) — ชื่อแถวภาษาไทย
//  และกติกาทุกอย่างต้องตรงกับ widget เดิม เพื่อให้เลขบนแอปกับบน Übersicht ตรงกัน
//

import Foundation

// MARK: - LimitKind

/// ชนิดของ limit ที่ endpoint /api/oauth/usage ส่งมาใน `limits[]`
public enum LimitKind: String, Equatable, Hashable, Sendable, CaseIterable {
    case session
    case weeklyAll = "weekly_all"
    case weeklyScoped = "weekly_scoped"
}

// MARK: - UsageLimit

/// หนึ่งแถวบนการ์ด (= หนึ่ง limit)
public struct UsageLimit: Identifiable, Equatable, Hashable, Sendable {
    /// `"session"` | `"weekly_all"` | `"weekly_scoped:<display_name>"` — ใช้เป็น key ของ anchor ด้วย
    public let id: String
    public let kind: LimitKind
    /// ข้อความไทยเหมือน `toRows()` ใน jsx เป๊ะ
    public let title: String
    /// 0...100 — ค่า**ดิบ** (ไม่ปัดเศษ); UI ปัดเองตอนแสดง, pacing ใช้ค่าดิบเหมือน jsx
    public let percent: Double
    public let resetsAt: Date?

    public init(id: String, kind: LimitKind, title: String, percent: Double, resetsAt: Date?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.percent = percent
        self.resetsAt = resetsAt
    }

    /// % ที่ปัดแล้วสำหรับแสดงผล (เหมือน `Math.round(lim.percent || 0)` ใน jsx)
    public var displayPercent: Int { Int(percent.rounded()) }
}

// MARK: - ErrorInfo

/// แปลงรหัส error ของ `claude-usage.sh` (`_error`) → ข้อความไทย + ต้องให้ผู้ใช้ล็อกอินไหม
/// (พอร์ตจาก `errInfo()` ใน claude-usage.jsx — ข้อความต้องตรงกันทุกตัวอักษร)
public struct ErrorInfo: Equatable, Hashable, Sendable {
    /// ข้อความเต็ม (ใช้ในการ์ดตอนสถานะ error)
    public let message: String
    /// ข้อความสั้น (ใช้ท้ายการ์ดตอน stale)
    public let short: String
    /// ควรโชว์ปุ่ม 🔑 ให้ไปล็อกอิน Claude Code ไหม (rate limit/network ไม่ต้อง)
    public let needsLogin: Bool

    public init(message: String, short: String, needsLogin: Bool) {
        self.message = message
        self.short = short
        self.needsLogin = needsLogin
    }

    public static func info(for code: String?) -> ErrorInfo {
        switch code {
        case "no_token":
            return ErrorInfo(message: "ยังไม่ได้ล็อกอิน Claude Code หรือหา token ไม่เจอ",
                             short: "ยังไม่ได้ล็อกอิน", needsLogin: true)
        case "auth":
            return ErrorInfo(message: "token หมดอายุ — เปิด Claude เพื่อรีเฟรช",
                             short: "token หมดอายุ", needsLogin: true)
        case "rate_limit":
            return ErrorInfo(message: "โดน rate limit (429) — พักยิง ~15 นาทีแล้วลองใหม่เอง",
                             short: "พัก 429 · รอรอบใหม่", needsLogin: false)
        case "network":
            return ErrorInfo(message: "ต่ออินเทอร์เน็ตไม่ได้",
                             short: "เน็ตมีปัญหา", needsLogin: false)
        default:
            return ErrorInfo(message: "ดึงข้อมูลไม่ได้", short: "ดึงข้อมูลไม่ได้", needsLogin: false)
        }
    }
}

// MARK: - FetchStatus

/// สถานะของข้อมูลก้อนนี้ — map จาก `_status`/`_error` ที่ `claude-usage.sh` ฝังมา
///
/// - `live`  : `_status == "live"` (หรือไม่มี `_status` เลย — เหมือน jsx ที่ตกไปทางเขียว)
/// - `stale` : `_status == "stale"` → ยิง API ไม่สำเร็จแต่มี cache เดิม (reason = ข้อความสั้น)
/// - `error` : `_status == "error"` → ไม่มีอะไรจะโชว์เลย (ไม่มี cache)
public enum FetchStatus: Equatable, Hashable, Sendable {
    case live
    case stale(reason: String)
    case error(message: String, needsLogin: Bool)

    public var isLive: Bool { self == .live }

    public var isError: Bool {
        if case .error = self { return true }
        return false
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}

// MARK: - UsageSnapshot

/// ข้อมูลหนึ่งก้อนที่พร้อมเรนเดอร์
public struct UsageSnapshot: Equatable, Sendable {
    /// จาก `limits[]`; ถ้าไม่มีให้ fallback `five_hour`/`seven_day` (กัน null/ไม่มี field ทุกจุด)
    public let limits: [UsageLimit]
    /// `_plan` เช่น "Max (20×)"
    public let plan: String?
    /// `_fetched_at`
    public let fetchedAt: Date?
    public let status: FetchStatus
    /// รหัสดิบจาก `_error` (`no_token` / `auth` / `rate_limit` / `network` / `http_NNN` / …)
    /// — เก็บไว้ให้ UI แยกเคสได้ละเอียดกว่าข้อความที่แปลแล้ว
    public let errorCode: String?

    public init(limits: [UsageLimit],
                plan: String?,
                fetchedAt: Date?,
                status: FetchStatus,
                errorCode: String? = nil) {
        self.limits = limits
        self.plan = plan
        self.fetchedAt = fetchedAt
        self.status = status
        self.errorCode = errorCode
    }

    /// % ของ limit "เซสชันปัจจุบัน" (ค่าดิบ) — ใช้โชว์บน menu bar / pill
    public var sessionPercent: Double? {
        limits.first(where: { $0.kind == .session })?.percent
    }

    public func limit(id: String) -> UsageLimit? { limits.first(where: { $0.id == id }) }

    public func limit(kind: LimitKind) -> UsageLimit? { limits.first(where: { $0.kind == kind }) }

    /// ข้อมูล error ที่แปลแล้ว (nil เมื่อสถานะ live)
    public var errorInfo: ErrorInfo? {
        status.isLive ? nil : ErrorInfo.info(for: errorCode)
    }

    /// ควรโชว์ปุ่มล็อกอินไหม — `stale` ก็โชว์ได้ (jsx ทำแบบนั้น) เพราะ FetchStatus.stale
    /// ไม่ได้พก flag นี้ไว้ในตัว
    public var needsLogin: Bool {
        if case .error(_, let needsLogin) = status { return needsLogin }
        if case .stale = status { return ErrorInfo.info(for: errorCode).needsLogin }
        return false
    }

    /// snapshot ว่างเปล่า (ก่อน fetch ครั้งแรก)
    public static let empty = UsageSnapshot(limits: [], plan: nil, fetchedAt: nil,
                                            status: .error(message: "ดึงข้อมูลไม่ได้", needsLogin: false),
                                            errorCode: nil)
}

// MARK: - UsageError

/// ⚠️ กฎสองข้อของ error ก้อนนี้ (มาจากรีวิว 17 ก.ย.):
///  1) `errorDescription` = ข้อความที่ขึ้น**บนการ์ด** → ต้องสั้น อ่านรู้เรื่อง ไม่มีรายการ path ยาวเป็นพรืด
///     (เคยยาวจนการ์ดสูง 1279pt) และ**ห้ามมี stdout/stderr ดิบของสคริปต์** — สคริปต์เผลอเปิด `set -x`
///     เมื่อไหร่ Bearer token ก็ขึ้นจอทันที
///  2) รายละเอียดสำหรับดีบักอยู่ที่ `diagnosticDescription` เท่านั้น — และผ่าน `redact()` มาแล้ว
public enum UsageError: LocalizedError, Equatable {
    /// `tried` = path ทั้งหมดที่ลองแล้ว (path เดียว = env `CLAUDE_USAGE_SCRIPT` บังคับไว้)
    case scriptNotFound(tried: [String])
    case launchFailed(reason: String)
    case timedOut(seconds: Double)
    /// สคริปต์พ่นอะไรที่ไม่ใช่ JSON (หรือว่างเปล่า) — `detail` ห้ามขึ้นจอ
    case invalidOutput(detail: String)

    public static func scriptNotFound(path: String) -> UsageError { .scriptNotFound(tried: [path]) }

    /// ข้อความสำหรับผู้ใช้ (บนการ์ด/เมนู)
    public var errorDescription: String? {
        switch self {
        case .scriptNotFound(let tried):
            // path เดียว = ถูกบังคับด้วย env → บอกไปเลยว่าไฟล์ไหนหาย, หลาย path = ติดตั้งเพี้ยน
            guard let only = tried.first, tried.count == 1 else {
                return "หาสคริปต์ claude-usage.sh ไม่เจอ — ติดตั้งแอปใหม่ด้วย install-app.sh"
            }
            return "หาสคริปต์ claude-usage.sh ไม่เจอที่ \(only)"
        case .launchFailed(let reason):
            return "รันสคริปต์ไม่ได้: \(reason)"
        case .timedOut(let seconds):
            return "สคริปต์ไม่ตอบใน \(Int(seconds)) วินาที (ถูกสั่งหยุดแล้ว)"
        case .invalidOutput:
            return "ผลลัพธ์จากสคริปต์ไม่ใช่ JSON — ดู log ของสคริปต์"
        }
    }

    /// รายละเอียดเต็มสำหรับดีบัก (เช็ก/log) — **ไม่ใช่**สิ่งที่เอาไปวาดบนการ์ด
    public var diagnosticDescription: String {
        switch self {
        case .scriptNotFound(let tried):
            return "หาสคริปต์ไม่เจอ · ลองแล้ว: " + tried.joined(separator: ", ")
        case .invalidOutput(let detail):
            return "ผลลัพธ์จากสคริปต์ไม่ใช่ JSON: " + UsageError.redact(detail)
        default:
            return errorDescription ?? "\(self)"
        }
    }

    /// ตัดความลับทิ้งก่อนข้อความจะไปโผล่ที่ไหนก็ตาม + จำกัดความยาว
    public static func redact(_ text: String, limit: Int = 300) -> String {
        var out = text
        for pattern in [#"(?i)bearer\s+\S+"#, #"sk-ant-[A-Za-z0-9_-]+"#] {
            out = out.replacingOccurrences(of: pattern, with: "«ซ่อนไว้»", options: .regularExpression)
        }
        return out.count > limit ? String(out.prefix(limit)) + "…" : out
    }
}
