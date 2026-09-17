//
//  ScreenCatalog.swift — รายชื่อจอ + รหัสจอที่ "คงที่" ข้ามการรีบูต/ถอดเสียบ
//
//  ใช้ CGDisplayCreateUUIDFromDisplayID เพราะ displayID เปลี่ยนได้เมื่อถอด/เสียบ
//  ส่วนความละเอียด (แบบที่ widget เดิมใช้เป็น sig เช่น "3440x1440") ชนกันได้ง่ายเมื่อมีจอรุ่นเดียวกัน 2 ตัว
//

import AppKit
import CoreGraphics

struct DisplayInfo: Identifiable, Hashable {
    /// UUID ของจอ (สตริงจาก CFUUID) — nil ไม่ได้ ถ้าหาไม่ได้จะ fallback เป็น "screen-<displayID>"
    let id: String
    let name: String
    let isMain: Bool
}

enum ScreenCatalog {

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(n.uint32Value)
    }

    /// รหัสจอที่ใช้เป็น key ทั้งของ "จอที่เลือก" และ "ตำแหน่งการ์ดต่อจอ"
    static func identifier(of screen: NSScreen) -> String {
        guard let did = displayID(of: screen) else { return "screen-unknown" }
        if let uuidRef = CGDisplayCreateUUIDFromDisplayID(did)?.takeRetainedValue(),
           let str = CFUUIDCreateString(nil, uuidRef) as String? {
            return str
        }
        return "screen-\(did)"
    }

    static func all() -> [DisplayInfo] {
        let main = NSScreen.main
        return NSScreen.screens.map { screen in
            DisplayInfo(id: identifier(of: screen),
                        name: displayName(of: screen),
                        isMain: screen == main)
        }
    }

    static func screen(withIdentifier id: String) -> NSScreen? {
        NSScreen.screens.first { identifier(of: $0) == id }
    }

    /// ชื่อจอ + ความละเอียด เช่น "M34WQ · 3440×1440"
    static func displayName(of screen: NSScreen) -> String {
        let size = screen.frame.size
        let base = screen.localizedName.trimmingCharacters(in: .whitespaces)
        let dims = "\(Int(size.width))×\(Int(size.height))"
        return base.isEmpty ? dims : "\(base) · \(dims)"
    }
}
