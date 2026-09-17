//
//  CardWindowController.swift — หน้าต่างการ์ดลอยระดับ desktop
//
//  ระดับหน้าต่าง: `CGWindowLevelForKey(.desktopIconWindow) + 1`
//    = อยู่เหนือวอลเปเปอร์และไอคอนบน desktop แต่ต่ำกว่าหน้าต่างแอปปกติทั้งหมด
//      (แบบเดียวกับที่ Übersicht ใช้) → การ์ดไม่เคยบังงาน แต่ยังรับคลิก/ลากได้
//
//  กติกาอื่น:
//   • NSPanel แบบ .nonactivatingPanel + canBecomeKey/Main = false → คลิกการ์ดแล้วแอปหน้าไม่สลับ
//   • collectionBehavior = canJoinAllSpaces + stationary + ignoresCycle → อยู่ทุก Space, ไม่โดน ⌘Tab
//   • hasShadow = false แล้ววาดเงาเองใน SwiftUI — ไม่งั้น AppKit วาดเงาเป็นสี่เหลี่ยมรอบหน้าต่างโปร่งใส
//   • ตำแหน่งเก็บเป็น "จุดบนซ้ายของการ์ด" ในพิกัดของจอนั้นๆ (y ชี้ลงเหมือน CSS) แยกต่อจอ
//   • จอที่เลือกไม่ได้ต่ออยู่ → ใช้จอหลักชั่วคราว **โดยไม่ลบค่าที่เลือกไว้** (บทเรียน 17 ก.ย.)
//

import AppKit
import SwiftUI

/// หน้าต่างที่ไม่มีวันเป็น key/main — คลิกแล้วโฟกัสของผู้ใช้ไม่หาย
final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CardWindowController: NSObject {

    private let model: UsageViewModel
    private let prefs: Preferences
    private let panel: CardPanel
    private let host: NSHostingController<CardRoot>

    /// สถานะตอนกำลังลาก (delta จากตำแหน่งเมาส์จริง + จอที่การ์ดอยู่ "ตอนเริ่มลาก")
    private var dragOrigin: (mouse: CGPoint, frame: CGPoint, screen: NSScreen)?
    private var isApplyingFrame = false

    init(model: UsageViewModel, prefs: Preferences) {
        self.model = model
        self.prefs = prefs
        self.panel = CardPanel(contentRect: NSRect(x: 0, y: 0, width: Metrics.cardWidth, height: 200),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered,
                               defer: false)
        self.host = NSHostingController(rootView: CardRoot(model: model, prefs: prefs, actions: CardActions()))
        super.init()

        host.sizingOptions = [.preferredContentSize]

        panel.level = Self.desktopLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentViewController = host

        host.rootView = CardRoot(model: model, prefs: prefs, actions: makeActions())

        // ขนาดการ์ดเปลี่ยน (ย่อ/กาง, มีแถบเตือนเพิ่ม) → ยึด "มุมบนซ้าย" ไว้ที่เดิมเสมอ
        NotificationCenter.default.addObserver(self, selector: #selector(contentResized),
                                               name: NSView.frameDidChangeNotification, object: host.view)
        host.view.postsFrameChangedNotifications = true

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // หมายเหตุ: ย่อ/กางไม่ต้องดักเอง — ขนาด content เปลี่ยน → frameDidChange → applyPlacement()
        // (ดักเองจะทำงาน "ก่อน" SwiftUI จัดขนาดใหม่ = คิดตำแหน่งจากความสูงเก่า)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// เหนือไอคอน desktop 1 ขั้น — ต่ำกว่าหน้าต่างปกติทุกบาน
    static var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    // MARK: - actions ที่ส่งให้ SwiftUI

    private func makeActions() -> CardActions {
        CardActions(
            refresh: { [weak self] in self?.model.refresh(force: true) },
            collapse: { [weak self] in
                guard self?.swallowClickAfterDrag() == false else { return }
                self?.prefs.collapsed = true
            },
            expand: { [weak self] in
                guard self?.swallowClickAfterDrag() == false else { return }
                self?.prefs.collapsed = false
            },
            login: { SystemActions.openLoginTerminal() },
            openTerminal: { SystemActions.openTerminalAtFolder() },
            pickScreen: { [weak self] in self?.popUpScreenMenu() },
            dragChanged: { [weak self] in self?.dragChanged() },
            dragEnded: { [weak self] in self?.dragEnded() }
        )
    }

    // MARK: - แสดง/ซ่อน

    func show() {
        prefs.cardVisible = true
        applyPlacement()
        panel.orderFrontRegardless()   // ไม่ใช้ makeKeyAndOrderFront — การ์ดต้องไม่แย่งโฟกัส
    }

    func hide() {
        prefs.cardVisible = false
        panel.orderOut(nil)
    }

    func toggleVisible() {
        prefs.cardVisible ? hide() : show()
    }

    func toggleCollapsed() {
        prefs.collapsed.toggle()
        if !prefs.cardVisible { show() }
    }

    // MARK: - จอที่ใช้

    /// จอเป้าหมาย: ที่ผู้ใช้เลือก → ถ้าไม่ได้ต่ออยู่ก็ใช้จอที่มีแถบเมนู (ค่าที่เลือก**ไม่ถูกลบ**)
    ///
    /// ⚠️ ห้ามใช้ `NSScreen.main` — นั่นคือ "จอของหน้าต่าง key" ซึ่งเปลี่ยนไปมาตามที่ผู้ใช้คลิก
    /// (หลายจอ → การ์ดกระโดดข้ามจอทุกครั้งที่จัดตำแหน่งใหม่ + ตำแหน่งถูกจำใต้คีย์ของจอผิดตัว)
    /// `NSScreen.screens.first` = จอที่มีแถบเมนู — นิ่งจริง
    private var targetScreen: NSScreen? {
        if let id = prefs.screenUUID, let screen = ScreenCatalog.screen(withIdentifier: id) {
            return screen
        }
        return NSScreen.screens.first
    }

    /// จอที่เลือกไว้แต่ตอนนี้ไม่ได้ต่ออยู่ (ให้เมนูบอกผู้ใช้ว่ากำลัง fallback)
    var chosenScreenMissing: Bool {
        guard let id = prefs.screenUUID else { return false }
        return ScreenCatalog.screen(withIdentifier: id) == nil
    }

    func chooseScreen(_ info: DisplayInfo?) {
        prefs.chooseScreen(uuid: info?.id, name: info?.name)
        applyPlacement()
        if prefs.cardVisible { panel.orderFrontRegardless() }
    }

    private func popUpScreenMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "ให้การ์ดอยู่จอไหน", action: nil, keyEquivalent: "").isEnabled = false
        let auto = NSMenuItem(title: "จอหลัก (อัตโนมัติ)", action: #selector(pickAuto), keyEquivalent: "")
        auto.target = self
        auto.state = prefs.screenUUID == nil ? .on : .off
        menu.addItem(auto)
        for info in ScreenCatalog.all() {
            let item = NSMenuItem(title: info.name + (info.isMain ? " · จอหลัก" : ""),
                                  action: #selector(pickScreenItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = info.id
            item.state = info.id == prefs.screenUUID ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func pickAuto() { chooseScreen(nil) }

    @objc private func pickScreenItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let info = ScreenCatalog.all().first(where: { $0.id == id }) else { return }
        chooseScreen(info)
    }

    // MARK: - ตำแหน่ง

    /// ส่วนบนของหน้าต่างที่เป็น "ที่ของคาปิบาร่า" (ไม่ใช่ตัวการ์ด) — ตอนย่อไม่มี
    private var topInset: CGFloat { prefs.collapsed ? 0 : Metrics.capyOverhang }

    /// ขนาด content เปลี่ยน → จัดตำแหน่งใหม่ "รอบ runloop ถัดไป"
    /// (ถ้าทำทันทีจะชนกับ setFrame ของเราเอง: notification ถูกยิงกลางคัน แล้วโดน guard ทิ้ง
    ///  → หน้าต่างค้างที่ตำแหน่งซึ่งคิดจากขนาดเก่า — เจอจริงตอนกดกางจาก pill แล้วการ์ดล้นขอบล่างจอ)
    @objc private func contentResized() {
        DispatchQueue.main.async { [weak self] in self?.applyPlacement() }
    }

    @objc private func screensChanged() {
        applyPlacement()
        if prefs.cardVisible { panel.orderFrontRegardless() }
    }

    func applyPlacement() {
        guard !isApplyingFrame, dragOrigin == nil, let screen = targetScreen else { return }
        var frame = panel.frame
        // ใช้ขนาดที่ SwiftUI ต้องการ "ตอนนี้" เป็นหลัก — ไม่รอ AppKit ปรับขนาดหน้าต่างให้
        // ไม่งั้นตำแหน่งจะถูกคิดจากความสูงเก่า (เช่น ตอนสลับ pill ↔ การ์ด)
        let fitting = host.view.fittingSize
        if fitting.width > 1, fitting.height > 1 { frame.size = fitting }
        let cardHeight = frame.height - topInset
        let stored = prefs.position(forDisplay: ScreenCatalog.identifier(of: screen))
            ?? Self.defaultPosition(on: screen)
        frame.origin = CGPoint(x: screen.frame.minX + stored.x,
                               y: screen.frame.maxY - stored.y - cardHeight)
        frame = Self.clamp(frame, into: screen.visibleFrame)

        isApplyingFrame = true
        panel.setFrame(frame, display: true)
        isApplyingFrame = false
        // ⚠️ ห้ามเขียนตำแหน่งกลับลง prefs ตรงนี้ — applyPlacement() ถูกเรียกระหว่างที่ขนาดการ์ด
        // ยังเป็นของเก่าได้ (ตอนสลับย่อ/กาง) ค่าที่ถูกหนีบจากขนาดผิดจะไปทับตำแหน่งจริงที่ผู้ใช้ตั้งไว้
        // (เจอจริงตอนทดสอบ: กด ✕ แล้ว pill กระโดดไปอยู่ล่างจอ) — เขียนกลับเฉพาะตอนลากเสร็จเท่านั้น
    }

    /// มุมขวาบนของจอ เว้นขอบ 20pt (เหมือน `top:20px; right:20px` ของ jsx)
    /// — เผื่อที่ให้คาปิบาร่าโผล่พ้นการ์ดโดยไม่มุดใต้แถบเมนู
    private static func defaultPosition(on screen: NSScreen) -> CGPoint {
        let visible = screen.visibleFrame
        let x = visible.maxX - 20 - Metrics.cardWidth - screen.frame.minX
        let y = (screen.frame.maxY - visible.maxY) + 20 + Metrics.capyOverhang
        return CGPoint(x: max(Metrics.screenMargin, x), y: y)
    }

    /// frame (พิกัด AppKit, y ชี้ขึ้น) → จุดบนซ้ายของ "ตัวการ์ด" ในพิกัดของจอ (y ชี้ลง)
    private static func topLeft(of frame: NSRect, on screen: NSScreen, topInset: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX - screen.frame.minX,
                y: screen.frame.maxY - (frame.maxY - topInset))
    }

    private static func clamp(_ frame: NSRect, into visible: NSRect) -> NSRect {
        var result = frame
        let m = Metrics.screenMargin
        let maxX = max(visible.minX + m, visible.maxX - m - frame.width)
        let maxY = max(visible.minY + m, visible.maxY - m - frame.height)
        result.origin.x = min(max(frame.minX, visible.minX + m), maxX)
        result.origin.y = min(max(frame.minY, visible.minY + m), maxY)
        return result
    }

    // MARK: - ลากย้าย

    private func dragChanged() {
        if dragOrigin == nil {
            // จอที่การ์ด "อยู่จริง" ตอนเริ่มลาก — ใช้ตัวนี้ทั้งตอนหนีบและตอนเซฟ
            // (ถ้าไปอ่าน targetScreen ใหม่กลางคัน จอเปลี่ยนได้ → การ์ดกระโดด/เซฟผิดคีย์)
            guard let screen = panel.screen ?? targetScreen else { return }
            dragOrigin = (NSEvent.mouseLocation, panel.frame.origin, screen)
        }
        guard let start = dragOrigin else { return }
        let mouse = NSEvent.mouseLocation
        var frame = panel.frame
        frame.origin = CGPoint(x: start.frame.x + (mouse.x - start.mouse.x),
                               y: start.frame.y + (mouse.y - start.mouse.y))
        // หนีบไว้ในจอที่ลากอยู่ (ไม่งั้นตำแหน่งที่จำไว้จะขัดกับจอที่การ์ดอยู่)
        panel.setFrameOrigin(Self.clamp(frame, into: start.screen.visibleFrame).origin)
    }

    private func dragEnded() {
        let screen = dragOrigin?.screen ?? panel.screen ?? targetScreen
        let dragged = dragOrigin != nil
        dragOrigin = nil
        if dragged { lastDragEnd = Date() }
        guard let screen else { return }
        prefs.setPosition(Self.topLeft(of: panel.frame, on: screen, topInset: topInset),
                          forDisplay: ScreenCatalog.identifier(of: screen))
    }

    /// ปุ่ม ✕ / pill นั่งอยู่ใต้ DragGesture เดียวกัน — ปล่อยเมาส์หลังลากอาจนับเป็น "คลิก" ด้วย
    /// (DragGesture มี minimumDistance 4pt อยู่แล้ว → dragChanged ยิง = ขยับเกิน 4pt แน่)
    /// เลยกลืนคลิกที่มาติดๆ หลังลากเสร็จทิ้ง ไม่ให้การ์ดย่อ/กางเองตอนผู้ใช้แค่ย้ายตำแหน่ง
    private var lastDragEnd: Date?

    private func swallowClickAfterDrag() -> Bool {
        guard let end = lastDragEnd, Date().timeIntervalSince(end) < 0.4 else { return false }
        lastDragEnd = nil
        return true
    }
}
