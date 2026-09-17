//
//  Preferences.swift — ค่าที่ต้องจำข้ามการเปิด/ปิดแอป (UserDefaults)
//
//  เทียบเท่า localStorage ของ widget เดิม:
//    POS_KEY → ตำแหน่งการ์ด (แยกต่อจอ)   SCREEN_KEY → จอที่เลือก
//    COLLAPSE_KEY → ย่อเป็น pill อยู่ไหม
//
//  ⚠️ บทเรียน 17 ก.ย. (CLAUDE.md #6): "จอที่เลือก" ต้องไม่ทำให้การ์ดหายทั้งเครื่อง
//  → ที่นี่แค่ "เก็บค่า" เท่านั้น การตัดสินใจ fallback อยู่ที่ CardWindowController
//  และ**ห้ามลบค่าที่ผู้ใช้เลือกไว้เอง**เมื่อจอหาย (เสียบกลับมาต้องย้ายกลับเอง)
//

import Foundation
import AppKit

final class Preferences: ObservableObject {

    static let shared = Preferences()

    private enum Key {
        static let collapsed = "card.collapsed"
        static let visible = "card.visible"
        static let positions = "card.positions"      // [displayUUID: [x, y]] (top-left ของการ์ด, พิกัดในจอนั้น)
        static let screenUUID = "card.screenUUID"
        static let screenName = "card.screenName"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.collapsed = defaults.bool(forKey: Key.collapsed)
        self.cardVisible = defaults.object(forKey: Key.visible) as? Bool ?? true
        self.screenUUID = defaults.string(forKey: Key.screenUUID)
        self.screenName = defaults.string(forKey: Key.screenName)
        self.positions = (defaults.dictionary(forKey: Key.positions) as? [String: [Double]]) ?? [:]
    }

    @Published var collapsed: Bool {
        didSet { defaults.set(collapsed, forKey: Key.collapsed) }
    }

    @Published var cardVisible: Bool {
        didSet { defaults.set(cardVisible, forKey: Key.visible) }
    }

    /// UUID ของจอที่ผู้ใช้เลือก (nil = "จอหลัก (อัตโนมัติ)")
    @Published private(set) var screenUUID: String?
    /// ชื่อจอที่เลือกไว้ — เก็บไว้โชว์ในเมนูตอนจอนั้นไม่ได้ต่ออยู่
    @Published private(set) var screenName: String?

    func chooseScreen(uuid: String?, name: String?) {
        screenUUID = uuid
        screenName = name
        defaults.set(uuid, forKey: Key.screenUUID)
        defaults.set(name, forKey: Key.screenName)
    }

    // MARK: - ตำแหน่งการ์ด (แยกต่อจอ)

    private var positions: [String: [Double]] {
        didSet { defaults.set(positions, forKey: Key.positions) }
    }

    /// จุดบนซ้ายของการ์ด ในพิกัด "ของจอนั้น" แบบ y ชี้ลง (เหมือน top/left ของ CSS)
    func position(forDisplay uuid: String) -> CGPoint? {
        guard let p = positions[uuid], p.count == 2 else { return nil }
        return CGPoint(x: p[0], y: p[1])
    }

    func setPosition(_ point: CGPoint, forDisplay uuid: String) {
        positions[uuid] = [Double(point.x), Double(point.y)]
    }
}
