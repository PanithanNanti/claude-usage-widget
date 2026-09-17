# ClaudeUsageBar — native macOS app (แทน Übersicht)

เป้าหมาย: แอป SwiftUI menu bar + การ์ดลอยระดับ desktop แสดง Claude plan usage — **ไม่พึ่ง Übersicht**.
ข้อมูลยังมาจาก `claude-usage.sh --json` ตัวเดิม (token/refresh/429/cache ผ่านสนามจริงแล้ว — ห้ามเขียนใหม่ใน Swift).
แหล่งอ้างอิงพฤติกรรม: `../claude-usage.jsx` (พอร์ต logic ให้ตรง) และ `../CLAUDE.md` (บทเรียน/กฎ Fable 50%).

## ข้อจำกัดเครื่อง
- มีแค่ Command Line Tools (Swift 6.4, **ไม่มี Xcode/xcodebuild**) → SwiftPM ล้วน, ประกอบ `.app` ด้วยสคริปต์
- XCTest อาจไม่มีใน CLT → ถ้า `swift test` ใช้ไม่ได้ ให้ทำ executable target `UsageCoreChecks` (assert แล้ว exit code ≠ 0 เมื่อพัง)
- deployment target macOS 14+, Swift language mode 5 (เลี่ยง strict-concurrency error ที่ไม่จำเป็น)
- ไม่มี dependency ภายนอก

## โครงสร้าง
```
app/
  Package.swift
  Sources/UsageCore/          ← library: ไม่มี UI, ไม่ import AppKit/SwiftUI
  Sources/ClaudeUsageBar/     ← executable: SwiftUI + AppKit
  Sources/UsageCoreChecks/    ← (หรือ Tests/UsageCoreTests ถ้า XCTest ใช้ได้)
  Resources/Info.plist        ← LSUIElement=true, bundle id io.github.panithannanti.ClaudeUsageBar
  scripts/build-app.sh        ← swift build -c release → dist/ClaudeUsageBar.app (+ ad-hoc codesign)
  scripts/install-app.sh      ← copy ไป ~/Applications, เปิดแอป
```
`.app/Contents/Resources/` ต้องมี `claude-usage.sh` และ `capybeats.png` (copy จาก root repo ตอน build)
→ แอป self-contained; หา script ตามลำดับ: **env `CLAUDE_USAGE_SCRIPT` ถ้าตั้งไว้ = ใช้ path นั้นตัวเดียว
(ไม่มีไฟล์ = error ที่ path นั้น ห้าม fallback)** → ไม่ได้ตั้ง: `Bundle.main` Resources → ไล่โฟลเดอร์แม่ → error ชัดเจน

## สัญญา API ของ UsageCore (✅ ทำแล้วในเฟส 1 — นี่คือของจริงที่มีในโค้ด)
```swift
public enum LimitKind: String, Equatable, Hashable, Sendable, CaseIterable {
  case session, weeklyAll = "weekly_all", weeklyScoped = "weekly_scoped"
}

public struct UsageLimit: Identifiable, Equatable, Hashable, Sendable {
  public let id: String          // "session" | "weekly_all" | "weekly_scoped:<model>"  (= key ของ anchor)
  public let kind: LimitKind
  public let title: String       // ข้อความไทยเหมือน toRows() ใน jsx
  public let percent: Double     // 0...100 — ค่า "ดิบ" ไม่ปัด (pacing ใช้ค่านี้เหมือน jsx)
  public let resetsAt: Date?
  public init(id: String, kind: LimitKind, title: String, percent: Double, resetsAt: Date?)
  public var displayPercent: Int { get }   // ปัดแล้ว = Math.round(lim.percent) ของ jsx
}

public enum FetchStatus: Equatable, Hashable, Sendable {
  case live, stale(reason: String), error(message: String, needsLogin: Bool)
  public var isLive: Bool { get }; public var isStale: Bool { get }; public var isError: Bool { get }
}

// errInfo() ของ jsx ย้ายมาเป็น type สาธารณะ (UI ใช้ตอนอยากได้ข้อความเต็มของสถานะ stale)
public struct ErrorInfo: Equatable, Hashable, Sendable {
  public let message: String     // ข้อความเต็ม   public let short: String  // ข้อความสั้น
  public let needsLogin: Bool
  public static func info(for code: String?) -> ErrorInfo
}

public struct UsageSnapshot: Equatable, Sendable {
  public let limits: [UsageLimit]     // จาก limits[]; fallback five_hour/seven_day; กัน null/ไม่มี field ทุกจุด
  public let plan: String?            // _plan
  public let fetchedAt: Date?         // _fetched_at
  public let status: FetchStatus      // จาก _status/_error ของ script (ดู errInfo() ใน jsx)
  public let errorCode: String?       // ➕ _error ดิบ ("auth"/"rate_limit"/"http_502"/…)
  public init(limits:plan:fetchedAt:status:errorCode: = nil)
  public var sessionPercent: Double? { get }          // ค่าดิบของแถว session
  public var needsLogin: Bool { get }                 // ➕ ใช้ได้ทั้งตอน error และ stale
  public var errorInfo: ErrorInfo? { get }            // ➕ nil เมื่อ live
  public func limit(id: String) -> UsageLimit?        // ➕
  public func limit(kind: LimitKind) -> UsageLimit?   // ➕
  public static let empty: UsageSnapshot              // ➕ ก่อน fetch ครั้งแรก
}

public enum UsageError: LocalizedError, Equatable {   // ➕
  case scriptNotFound(path: String), launchFailed(reason: String)
  case timedOut(seconds: Double), invalidOutput(detail: String)
}

public struct UsageParser {
  public static func parse(_ json: Data) throws -> UsageSnapshot          // throw UsageError.invalidOutput
  public static func snapshot(from dict: [String: Any]) -> UsageSnapshot  // ➕ (ไม่ throw)
  public enum Title { static let session, weeklyAll, unknownModel; static func weeklyScoped(_:) }  // ➕ ข้อความไทย
}

public enum ISODate {                                  // ➕
  public static func parse(_ s: String?) -> Date?      // ทนเศษวินาที 6 หลัก / offset / null
  public static func resetKey(_ d: Date) -> String     // ปัดเป็น "นาที" — ดูหมายเหตุ jitter ข้างล่าง
}

public protocol UsageFetching { func fetch(force: Bool) async throws -> UsageSnapshot }
public final class ScriptUsageFetcher: UsageFetching, Sendable {
  public init(scriptURL: URL, timeout: TimeInterval = 30)  // /bin/bash <script> --json [--force]
}                                     // รันบน background queue, เติม PATH ให้ GUI, timeout = ฆ่าโปรเซสจริง
public enum ScriptLocator {                            // ➕ env CLAUDE_USAGE_SCRIPT → bundle Resources → ไล่โฟลเดอร์แม่
  public static let scriptName = "claude-usage.sh"
  public static func find(bundle: Bundle = .main) throws -> URL
  public static func candidates(bundle: Bundle = .main) -> [URL]
}

public struct DailyBudget: Equatable, Hashable, Sendable {
  public let target: Double       // เป้า % ของวันนี้ (clamp 0...100)
  public let remaining: Double    // เป้า "ก่อน clamp" − percent (ติดลบ = เกินเป้า) — ให้ตัวเลข "เกินเป้า +X%" ตรง jsx
  public let daysLeft: Double     // เศษทศนิยม (ค่า ณ ตอนนี้)
  public let cappedByWeekly: Bool // "จำกัดโดยโควตาสัปดาห์รวม"
  public init(target:remaining:daysLeft:cappedByWeekly:)
  public var displayTarget: Int { get }   // ➕ max(0, round(target))
  public var isOverTarget: Bool { get }   // ➕ remaining < 0
}
public protocol AnchorStore: AnyObject { func load() -> [String: Anchor]; func save(_ a: [String: Anchor]) }
public struct Anchor: Codable, Equatable, Hashable, Sendable {
  public var day: String; public var pct: Double
  public var days: Double     // ➕ "วันที่เหลือ ณ ตอน anchor" — jsx ใช้ a.days คิดเป้า (ถ้าไม่มี เป้าจะไม่คงที่ทั้งวัน)
  public var reset: String    // = ISODate.resetKey(resetsAt)
  public init(day:pct:days:reset:)
}
public let anchorDefaultsKey = "claudeUsageDailyAnchor2"
public final class UserDefaultsAnchorStore: AnchorStore {
  public init(defaults: UserDefaults = .standard, key: String = anchorDefaultsKey)
}
public final class InMemoryAnchorStore: AnchorStore { public init(_ anchors: [String: Anchor] = [:]) }  // ➕ เทสต์/พรีวิว
public struct Pacing {
  public static let scopedShare: Double = 0.5
  public init(store: AnchorStore, now: @escaping () -> Date = Date.init, calendar: Calendar = .current)
  public func budgets(for snapshot: UsageSnapshot) -> [String: DailyBudget]   // key = UsageLimit.id; ไม่มี entry สำหรับ session
}
public enum ResetFormat {
  public static func relative(_ d: Date, now: Date) -> String                       // "รีเซ็ตใน 3ชม. 42นาที"
  public static func absolute(_ d: Date, calendar: Calendar = .current) -> String    // "รีเซ็ต จ 21/09 13:00"
  public static func clock(_ d: Date, calendar: Calendar = .current) -> String       // ➕ "13:00"
}
```
กติกา pacing ตรง jsx 100%: `target = anchor.pct + (100−anchor.pct)/anchor.days`, re-anchor เมื่อวัน local เปลี่ยนหรือ
`resets_at` เปลี่ยน **เฉพาะเมื่อ fetchedAt เป็นวันนี้**, `capScopedBudget` (scopedShare = 0.5), เป้าติดลบ → 0.

> ⚠️ **แก้บั๊กของ jsx ตรงนี้ด้วย:** `resets_at` ที่ API ส่งมา "สั่น" ระดับเศษวินาทีทุกครั้งที่ยิง
> (เจอจริง: weekly_all `…T06:00:01.126168Z` แต่ weekly_scoped `…T06:00:00.126364Z` ในคำตอบเดียวกัน)
> jsx เทียบสตริง ISO ดิบ (`a.reset !== resetIso`) จึงนึกว่า "ขึ้นรอบสัปดาห์ใหม่" แล้ว **re-anchor ทิ้งทุกรอบ poll**
> → เป้ารายวันวิ่งตามการใช้งานระหว่างวันแทนที่จะคงที่. ฝั่ง Swift เทียบด้วย `ISODate.resetKey` ที่**ปัดเป็นนาที**

> เทสต์: `cd app && swift run UsageCoreChecks` (exit ≠ 0 เมื่อพัง) — เครื่องนี้ไม่มี XCTest และ
> swift-testing คอมไพล์ผ่านบ้างไม่ผ่านบ้าง (`plugin for module 'TestingMacros' not found` แบบสุ่ม)
> `swift run UsageCoreChecks --live` = ยิงสคริปต์จริงแล้วพิมพ์สิ่งที่ core อ่านได้ (ใช้ตอน verify)

## UI (ClaudeUsageBar) — เทียบเท่าการ์ดแบบ A
- `MenuBarExtra`: ไอคอน + % session; เมนู: Refresh now, Show/Hide card, เลือกจอ, Launch at login (`SMAppService`), Login (เปิด Terminal รัน `claude`), Quit
- การ์ด: `NSPanel` borderless, ระดับ desktop (เหนือ wallpaper/ไอคอน ใต้หน้าต่างปกติ), ทุก Space, ไม่ขโมย focus,
  พื้นเข้ม glassy, ลากได้ที่หัวการ์ด + จำตำแหน่ง, ย่อเป็น pill ได้
- แถว limit: ชื่อ + reset + bar (#4f7cff / ≥80 #f0a728 / ≥95 #f0554a) + เส้นขีดเป้า + บรรทัด daily pacing (ฟ้า/เหลืองเมื่อเกินเป้า)
- CapyBeats: spritesheet 8×9 เฟรมละ 192×208, 72 เฟรม, scale 0.75, นั่งบนหัวการ์ด
- refresh ทุก 10 นาที + ตอนตื่นจาก sleep; **ผลเพี้ยน/ error ห้ามวาดทับข้อมูลดี** (คง snapshot เดิม + เปลี่ยนแค่สถานะ)
- stale เกิน ~1 ชม. ต้อง**เด่น** (บทเรียน 17 ส.ค.) — แถบเตือนชัด ไม่ใช่แค่จุดเหลือง
- เลือกจอ: เก็บ display UUID/ชื่อ; **จอที่เลือกไม่อยู่ → fallback จอหลักเสมอ** (บทเรียน 17 ก.ย.), ฟัง `didChangeScreenParametersNotification`

### ✅ ผลของเฟส 2 (ui) — ไฟล์จริงใน `Sources/ClaudeUsageBar/`
| ไฟล์ | หน้าที่ |
|------|--------|
| `App.swift` | `@main` + AppDelegate (accessory/LSUIElement), กันเปิดซ้ำ (bundle id เดิมรันอยู่ → exit) |
| `UsageViewModel.swift` | `@MainActor ObservableObject` — fetch/สถานะ/pacing/timer 10 นาที + tick 1 นาที + ตื่นจาก sleep |
| `CardWindowController.swift` | NSPanel ระดับ desktop, ตำแหน่ง/จอ/ลากย้าย/ย่อ-กาง |
| `CardView.swift` | การ์ดแบบ A + pill + แถบเตือนข้อมูลค้าง + bar/เส้นขีดเป้า/บรรทัด pacing |
| `CapybaraView.swift` | CapyBeats: CALayer + CAKeyframeAnimation บน `contentsRect` (discrete, 72 เฟรม/7.2 วิ) |
| `StatusItemController.swift` | NSStatusItem + เมนู (สถานะ/รีเฟรช/ซ่อน/ย่อ/เลือกจอ/login item/ล็อกอิน/log/ออก) |
| `Preferences.swift` · `ScreenCatalog.swift` · `SystemActions.swift` · `Theme.swift` | ค่าที่จำไว้ · รายชื่อจอ+UUID · Terminal/log/SMAppService · สี-ขนาดจาก CSS ของ jsx |

**ที่ต่างจากแผนเดิม (ตั้งใจ):**
- ใช้ **NSStatusItem แทน `MenuBarExtra`** — MenuBarExtra เรนเดอร์ label เป็นภาพ template
  ทำให้คุมสีตัวเลขบนแถบเมนูไม่ได้ (สเปกต้องการเหลือง ≥80 / แดง ≥95 / เหลืองเมื่อข้อมูลค้าง)
- **window level = `CGWindowLevelForKey(.desktopIconWindow) + 1`** (= -2147483602) ทดสอบบน macOS 27
  แล้วว่าเห็นการ์ดบน desktop จริงและ **คลิก/ลากได้** (ยืนยันด้วยการยิง CGEvent เข้าไปจริง)
  — ข้อควรรู้: widget ของ macOS เอง (เช่น Reminders บน desktop) อยู่ **สูงกว่า** ระดับนี้ จะทับการ์ดได้
- ตำแหน่งการ์ดถูกเขียนลง prefs **เฉพาะตอนลากเสร็จ** เท่านั้น (เขียนตอน `applyPlacement()` ด้วยจะพัง
  เพราะบางจังหวะมันถูกเรียกตอนขนาดยังเป็นของเก่า แล้วค่าที่หนีบผิดไปทับตำแหน่งจริง)

### ✅ ผลของเฟส 5 (fix) — จากรีวิว + QA (17 ก.ย.)
| แก้อะไร | ทำไม |
|---------|------|
| `targetScreen` "อัตโนมัติ" = `NSScreen.screens.first` (เลิกใช้ `NSScreen.main`) | `.main` = จอของหน้าต่าง key → หลายจอแล้วการ์ดกระโดดข้ามจอ + ตำแหน่งถูกจำใต้คีย์จอผิด |
| ลาก: จำ "จอตอนเริ่มลาก" ไว้ใน `dragOrigin` แล้วหนีบ/เซฟด้วยจอนั้น | กันจอเปลี่ยนกลางคันแล้วการ์ดเทเลพอร์ต |
| `CapybaraView.frameRect` กลับด้านแถว (`y = 1 − (row+1)·h`) | **ยืนยันด้วยการเรนเดอร์จริง**: `contentsRect` วัด y จากล่าง — สูตรเดิม index 0 โชว์แถวล่างสุด = แถวเล่นย้อนกลับเทียบ `CAPY_CSS` ของ jsx |
| parser: ไม่มีตัวเลขใน `five_hour`/`seven_day` → คืน `[]` | เดิมปั้นแถว 0% ไปทับข้อมูลดี (กฎ "ผลไม่มีแถว = คงของเดิม" ของ view model เลยไม่ทำงาน) |
| view model หาสคริปต์แบบ lazy ทุกครั้งที่ refresh | หาไม่เจอตอนเปิดแอปต้องไม่ตายถาวร — ติดตั้งทีหลังแล้วกด ↻ ต้องใช้ได้ |
| `ScriptLocator`: env `CLAUDE_USAGE_SCRIPT` ตั้งแล้ว = ใช้ path เดียว ห้าม fallback | ไม่งั้นเทสต์/ดีบักหลอกตัวเอง (แอบไปอ่านตัวใน bundle) |
| `UsageError`: `errorDescription` สั้น · `diagnosticDescription` เก็บรายละเอียด · `redact()` | รายการ 15 path เคยดันการ์ดสูง 1279pt; `set -x` ในสคริปต์ = Bearer token ขึ้นจอได้ → stdout/stderr ถูก redact ตั้งแต่ตอนสร้าง error + การ์ดหนีบข้อความไว้ 4 บรรทัด |
| fetcher: timeout เช็ก `process.isRunning` ก่อนตีตรา expired · รอ EOF ทั้ง stdout/stderr แล้วไม่ `close()` เอง | timeout ที่ยิงพร้อมโปรเซสจบ = ทิ้งข้อมูลดี; `close()` ชนกับ `readabilityHandler` ที่ยังทำงานอยู่ |
| timer ทั้งสองตัวเข้า `RunLoop.main` โหมด `.common` | เมนูเปิดค้าง/กำลังลาก → timer เดิมหยุดเดิน |
| pill: `.simultaneousGesture` + กันคลิกหลังลาก (`swallowClickAfterDrag`, 0.4 วิ) | `.gesture()` บน Button เดียวกันกินคลิกทิ้ง (คลิก pill แล้วไม่กาง — ยืนยันด้วย CGEvent จริง); พอเปลี่ยนเป็น simultaneous แล้วปล่อยเมาส์หลังลาก **ยิง action จริง** (เห็นใน log) → ต้องมีตัวกลืนคลิก |
| login item เทียบ `SMAppService.mainApp.status == .requiresApproval` | เดิมเทียบสตริงไทยของ `statusText` — แก้ข้อความทีเดียวเมนูเพี้ยนเงียบๆ |

**ยืนยันด้วยของจริง:** `swift run UsageCoreChecks` = 176 ข้อผ่านหมด · การ์ดรันจริงกับข้อมูลจริง (session/weekly/Fable)
· สคริปต์ปลอม 3 เคส: หาสคริปต์ไม่เจอ (การ์ดสูง 313pt ไม่ใช่ 1279), JSON เพี้ยนที่มี `Bearer sk-ant-…` (ไม่โผล่ทั้งบนจอและใน AX tree),
payload `limits: []` หลังก้อนที่ดี (ตัวเลขเดิมยังอยู่ + สถานะเป็น "ค่าล่าสุด …")
· **Übersicht เปิดอยู่ไม่กินคลิก**: หน้าต่าง Übersicht layer −1 เต็มจอ แต่ CGEvent คลิก ✕/pill และลากหัวการ์ดถึงการ์ดหมด
(สิ่งที่บังจริงคือหน้าต่างแอปปกติที่ทับอยู่ — การ์ดอยู่ระดับ desktop ตามสเปก)

## เฟสงาน
1. (ขนาน) **core**: Package.swift + UsageCore + checks  ·  **packaging**: Info.plist + build/install scripts
2. **ui**: target ClaudeUsageBar ตามสัญญาข้างบน (อ่านโค้ด core จริงก่อนเขียน)
3. **integrate+verify**: build `.app`, รันจริง, screenshot เทียบกับ widget Übersicht, แก้จนผ่าน
4. **review**: อ่านโค้ดทั้งหมดหา bug/ช่องโหว่ แล้ว Fable สรุป
