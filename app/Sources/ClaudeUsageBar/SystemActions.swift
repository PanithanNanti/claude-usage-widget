//
//  SystemActions.swift — งานที่ต้องคุยกับระบบ (Terminal / log / login item)
//

import AppKit
import ServiceManagement

enum SystemActions {

    /// เปิด Terminal แล้วรัน `claude` — วิธีเดียวกับ openLogin() ของ widget เดิม
    /// (ให้ Claude Code เป็นคนล็อกอิน/หมุน token ให้ เราไม่ยุ่งกับ credential เอง)
    static func openLoginTerminal() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"claude\"",
        ]
        try? task.run()
    }

    /// โฟลเดอร์ที่ปุ่ม ">_" เปิด — ค่าเริ่มต้น `~/dev`
    /// เปลี่ยนได้: `defaults write io.github.panithannanti.ClaudeUsageBar terminal.folder "~/Projects"`
    /// ไม่มีโฟลเดอร์นั้นจริง → เปิดที่ home แทน (เครื่องคนอื่นอาจไม่มี ~/dev)
    static var terminalFolder: URL {
        let raw = UserDefaults.standard.string(forKey: "terminal.folder") ?? "~/dev"
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return url
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// เปิดหน้าต่าง terminal ใหม่ที่ `terminalFolder` — iTerm2 ก่อน ไม่มีค่อยใช้ Terminal.app
    /// ส่งโฟลเดอร์เป็น URL ให้แอปเปิดเอง (เหมือนลากโฟลเดอร์ไปวางบนไอคอน) —
    /// ไม่ประกอบคำสั่ง shell/AppleScript จาก path จึงไม่มีช่อง injection จากชื่อโฟลเดอร์แปลกๆ
    static func openTerminalAtFolder() {
        let folder = terminalFolder
        let candidates = ["com.googlecode.iterm2", "com.apple.Terminal"]
        guard let appURL = candidates.lazy
            .compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })
            .first else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: config)
    }

    static var logURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/usage-widget.log")
    }

    /// เปิด `~/.claude/usage-widget.log` — ไฟล์ที่ต้องดูเป็นอย่างแรกเวลาการ์ดค้าง
    static func openLog() {
        let url = logURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }
}

// MARK: - Launch at login

/// ห่อ SMAppService ไว้ — แอปที่เซ็นแบบ ad-hoc อาจถูกระบบปฏิเสธ
/// ห้ามพังทั้งแอปเพราะเรื่องนี้: ล้มเหลวก็แค่เก็บข้อความไว้โชว์ในเมนู
enum LoginItem {

    /// login item ใช้ได้เฉพาะตอนรันเป็น .app จริง (ตอน `swift run` ไม่มี bundle ให้ลงทะเบียน)
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// - Returns: nil = สำเร็จ, ไม่ใช่ nil = ข้อความ error ที่ควรโชว์ให้ผู้ใช้เห็น
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard isAvailable else { return "ใช้ได้เฉพาะตอนรันเป็นแอป (.app) เท่านั้น" }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// "ลงทะเบียนแล้วแต่ผู้ใช้ยังไม่อนุมัติใน System Settings" — เทียบ enum ตรงๆ
    /// (ห้ามไปเทียบข้อความไทยของ `statusText` — แก้ข้อความทีเดียวเมนูก็เพี้ยนเงียบๆ)
    static var needsApproval: Bool {
        isAvailable && SMAppService.mainApp.status == .requiresApproval
    }

    static var statusText: String {
        guard isAvailable else { return "ไม่พร้อมใช้" }
        switch SMAppService.mainApp.status {
        case .enabled: return "เปิดอยู่"
        case .requiresApproval: return "รออนุมัติใน System Settings"
        case .notFound: return "ระบบยังไม่รู้จักแอปนี้"
        default: return "ปิดอยู่"
        }
    }
}
