//
//  App.swift — จุดเริ่มของแอป (LSUIElement: ไม่มีหน้าต่างหลัก ไม่มีไอคอนบน Dock)
//
//  ประกอบร่าง: UsageViewModel (ข้อมูล) → CardWindowController (การ์ดบน desktop)
//              → StatusItemController (แถบเมนู)
//

import AppKit
import UsageCore

@main
enum ClaudeUsageBarMain {
    static func main() {
        // เปิดซ้ำ → ออกเงียบๆ ปล่อยให้ตัวเดิมทำงานต่อ (ไม่แย่งกันยิงสคริปต์/ไม่มีการ์ดซ้อน)
        if isAlreadyRunning() { exit(0) }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate   // กัน optimizer ปล่อย delegate (NSApplication ถือแบบ weak)
    }

    private static func isAlreadyRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = NSRunningApplication.current.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != me }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let prefs = Preferences.shared
    private lazy var model = UsageViewModel()
    private var card: CardWindowController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let card = CardWindowController(model: model, prefs: prefs)
        self.card = card
        statusItem = StatusItemController(model: model, prefs: prefs, card: card)
        if prefs.cardVisible { card.show() }
        model.start()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
