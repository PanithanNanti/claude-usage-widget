//
//  StatusItemController.swift — ไอเทมบนแถบเมนู + เมนูของแอป
//
//  ทำไมใช้ NSStatusItem แทน MenuBarExtra ของ SwiftUI:
//    MenuBarExtra เรนเดอร์ label เป็นภาพ template → คุมสีเองไม่ได้ แต่สเปกต้องการให้
//    ตัวเลขบนแถบเมนู "เปลี่ยนสี" เมื่อ ≥80 / ≥95 / ข้อมูลค้าง (ดู app/PLAN.md — UI ข้อแรก)
//    NSStatusItem + attributedTitle ทำได้ตรงไปตรงมา และคุม state ของเมนูย่อยได้ครบ
//

import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: UsageViewModel
    private let prefs: Preferences
    private let card: CardWindowController
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()
    /// ข้อความ error ล่าสุดจากการตั้ง login item (โชว์ในเมนู ไม่ใช่ alert)
    private var loginItemError: String?

    init(model: UsageViewModel, prefs: Preferences, card: CardWindowController) {
        self.model = model
        self.prefs = prefs
        self.card = card
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false   // เราคุม isEnabled เอง (ปุ่มรีเฟรชต้องเทาได้ตอนกำลังดึง)
        item.menu = menu
        item.button?.font = NSFont.menuBarFont(ofSize: 0)
        updateTitle()

        // objectWillChange ยิง "ก่อน" ค่าเปลี่ยน → หน่วงหนึ่งรอบ runloop ค่อยอ่านค่าใหม่
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateTitle() } }
            .store(in: &cancellables)
    }

    // MARK: - ป้ายบนแถบเมนู

    private func updateTitle() {
        guard let button = item.button else { return }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0)
        ]
        if let color = model.menuBarColor { attributes[.foregroundColor] = color }
        button.attributedTitle = NSAttributedString(string: model.menuBarText, attributes: attributes)
        button.toolTip = "Claude Usage — \(model.menuSummary)\n\(model.menuStatusLine)"
    }

    // MARK: - เมนู (สร้างใหม่ทุกครั้งที่เปิด ค่าจะได้สดเสมอ)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(info(model.menuSummary, bold: true))
        menu.addItem(info(model.menuStatusLine))
        menu.addItem(.separator())

        add(menu, model.isFetching ? "กำลังรีเฟรช…" : "รีเฟรชเดี๋ยวนี้",
            #selector(refreshNow), key: "r", enabled: !model.isFetching)
        add(menu, prefs.cardVisible ? "ซ่อนการ์ดบน desktop" : "แสดงการ์ดบน desktop",
            #selector(toggleCard), key: "d")
        add(menu, prefs.collapsed ? "กางการ์ด" : "ย่อการ์ดเป็นวงกลม",
            #selector(toggleCollapse), key: "e")

        // ── จอ ──
        let screensItem = NSMenuItem(title: "แสดงบนจอ", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let auto = NSMenuItem(title: "จอหลัก (อัตโนมัติ)", action: #selector(pickAutoScreen), keyEquivalent: "")
        auto.target = self
        auto.state = prefs.screenUUID == nil ? .on : .off
        submenu.addItem(auto)
        submenu.addItem(.separator())
        for display in ScreenCatalog.all() {
            let entry = NSMenuItem(title: display.name + (display.isMain ? " · จอหลัก" : ""),
                                   action: #selector(pickScreen(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = display.id
            entry.state = display.id == prefs.screenUUID ? .on : .off
            submenu.addItem(entry)
        }
        if card.chosenScreenMissing {
            submenu.addItem(.separator())
            submenu.addItem(info("⚠︎ จอ “\(prefs.screenName ?? "ที่เลือกไว้")” ไม่ได้ต่ออยู่ — ใช้จอหลักชั่วคราว"))
        }
        screensItem.submenu = submenu
        menu.addItem(screensItem)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "เปิดแอปตอนล็อกอินเข้าเครื่อง", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        login.isEnabled = LoginItem.isAvailable
        menu.addItem(login)
        if let error = loginItemError {
            menu.addItem(info("⚠︎ ตั้งไม่สำเร็จ: \(error)"))
        } else if LoginItem.needsApproval {
            menu.addItem(info("ℹ︎ \(LoginItem.statusText)"))
        }

        add(menu, "เปิด terminal ที่ \((SystemActions.terminalFolder.path as NSString).abbreviatingWithTildeInPath)", #selector(openTerminal), key: "t")
        add(menu, "🔑 ล็อกอิน Claude (เปิด \(SystemActions.terminalName))", #selector(openLogin))
        add(menu, "เปิด log ของสคริปต์", #selector(openLog))

        menu.addItem(.separator())
        add(menu, "ออกจาก Claude Usage", #selector(quit), key: "q")
    }

    // MARK: - ตัวช่วยสร้างไอเทม

    private func info(_ text: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let font = bold ? NSFont.menuFont(ofSize: 0) : NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector,
                     key: String = "", enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    // MARK: - actions

    @objc private func refreshNow() { model.refresh(force: true) }
    @objc private func toggleCard() { card.toggleVisible() }
    @objc private func toggleCollapse() { card.toggleCollapsed() }
    @objc private func openLogin() { SystemActions.openLoginTerminal() }
    @objc private func openTerminal() { SystemActions.openTerminalAtFolder() }
    @objc private func openLog() { SystemActions.openLog() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func pickAutoScreen() { card.chooseScreen(nil) }

    @objc private func pickScreen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let display = ScreenCatalog.all().first(where: { $0.id == id }) else { return }
        card.chooseScreen(display)
    }

    @objc private func toggleLoginItem() {
        loginItemError = LoginItem.setEnabled(!LoginItem.isEnabled)
    }
}
