//
//  Theme.swift — สี/ขนาดของการ์ด (พอร์ตตรงจาก CSS ใน claude-usage.jsx)
//
//  ตัวเลขทุกตัวในนี้อ้างอิง `className` ของ widget เดิม 1:1 (px → pt)
//  แก้ที่นี่ที่เดียวเมื่ออยากขยับดีไซน์ ห้ามฝังค่าสีดิบใน View
//

import SwiftUI
import AppKit

extension Color {
    /// สร้างสีจากเลขฐาน 16 แบบ CSS (`0xd97757`)
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255.0,
                  green: Double((hex >> 8) & 0xff) / 255.0,
                  blue: Double(hex & 0xff) / 255.0,
                  opacity: alpha)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255.0,
                  green: CGFloat((hex >> 8) & 0xff) / 255.0,
                  blue: CGFloat(hex & 0xff) / 255.0,
                  alpha: alpha)
    }
}

enum Theme {
    // พื้นการ์ด / เส้นขอบ
    static let cardTint = Color(hex: 0x18181c, alpha: 0.72)   // background: rgba(24,24,28,0.72)
    static let hairline = Color.white.opacity(0.09)           // border: rgba(255,255,255,0.09)
    static let divider = Color.white.opacity(0.07)            // border-top ของ .cu-foot
    static let trackBG = Color.white.opacity(0.08)            // .cu-track

    // ตัวอักษร
    static let title = Color(hex: 0xececf1)
    static let rowName = Color(hex: 0xf2f2f5)                 // .cu-name
    static let rowPct = Color(hex: 0xb6b6be)                  // .cu-pct
    static let rowReset = Color(hex: 0x86868f)                // .cu-reset / .cu-foot
    static let daily = Color(hex: 0x9db4e8)                   // .cu-daily
    static let errText = Color(hex: 0xd6d6dc)                 // .cu-err
    static let closeIcon = Color(hex: 0x8a8a93)               // .cu-close
    static let buttonText = Color(hex: 0x9a9aa2)              // .cu-btn

    // แบรนด์ / สถานะ
    static let orange = Color(hex: 0xd97757)                  // ไทล์ ✳ + ป้าย plan
    static let badgeText = Color(hex: 0xe8a48a)
    static let blue = Color(hex: 0x4f7cff)
    static let warn = Color(hex: 0xf0a728)
    static let crit = Color(hex: 0xf0554a)
    static let ok = Color(hex: 0x3fbf68)

    /// สีแท่ง bar ตาม % — เหมือน `barColor()` ใน jsx เป๊ะ
    static func bar(_ percent: Int) -> Color {
        percent >= 95 ? crit : percent >= 80 ? warn : blue
    }

    static func nsBar(_ percent: Int) -> NSColor {
        percent >= 95 ? NSColor(hex: 0xf0554a)
            : percent >= 80 ? NSColor(hex: 0xf0a728) : NSColor(hex: 0x4f7cff)
    }
}

enum Metrics {
    static let cardWidth: CGFloat = 320
    static let hPad: CGFloat = 20
    static let cornerRadius: CGFloat = 18
    /// ความกว้างของ bar (= การ์ดหัก padding ซ้าย/ขวา)
    static let contentWidth: CGFloat = cardWidth - hPad * 2

    // ── CapyBeats (spritesheet 8 คอลัมน์ × 9 แถว, เฟรมต้นฉบับ 192×208) ──
    static let capyColumns = 8
    static let capyRows = 9
    static let capyFrames = capyColumns * capyRows           // 72
    static let capyScale: CGFloat = 0.75
    static let capyWidth: CGFloat = (192 * capyScale).rounded()   // 144
    static let capyHeight: CGFloat = (208 * capyScale).rounded()  // 156
    /// โผล่พ้นหัวการ์ด (จมลงในการ์ด 10pt เหมือนนั่งบนขอบ) = CAPY_OVERHANG ของ jsx
    static let capyOverhang: CGFloat = capyHeight - 10            // 146
    static let capyLeft: CGFloat = 14
    /// 1 แถว = 8 เฟรม ใน 0.8 วิ → 10 fps, ครบลูป 72 เฟรม = 7.2 วิ
    static let capyLoopDuration: Double = 7.2

    /// ระยะขอบจอขั้นต่ำตอนหนีบการ์ดกลับเข้าจอ
    static let screenMargin: CGFloat = 8
    /// ข้อมูลค้างเกินเท่านี้ = ขึ้นแถบเตือนเด่นๆ (บทเรียน 17 ส.ค. — จุดเหลืองเล็กๆ ไม่พอ)
    static let staleWarningSeconds: TimeInterval = 3600
}
