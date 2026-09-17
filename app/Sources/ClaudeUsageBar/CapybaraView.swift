//
//  CapybaraView.swift — CapyBeats: คาปิบาร่าดุ๊กดิ๊กนั่งบนขอบบนของการ์ด
//
//  spritesheet 8 คอลัมน์ × 9 แถว = 72 เฟรม (เฟรมละ 192×208 px) — ไฟล์ capybeats.png
//  จังหวะเดียวกับ widget เดิม: 8 เฟรม/0.8 วิ (10 fps), ครบลูป 7.2 วิ
//
//  ทำไมใช้ CAKeyframeAnimation บน `contentsRect` แทนการวาดเองทุกเฟรม:
//   • ภาพถูกอัปโหลดเป็นเท็กซ์เจอร์ครั้งเดียว แล้ว render server เลื่อนกรอบให้เอง
//     → โปรเซสเราไม่ต้องตื่นทุก 100 มิลลิวินาที (CPU ~0%) ต่างจาก Timer/TimelineView
//   • calculationMode = .discrete = เปลี่ยนเฟรมแบบกระโดด ไม่ interpolate (เหมือน steps() ของ CSS)
//  และหยุด animation เมื่อการ์ดถูกซ่อน (ไม่มีอะไรวาด = ไม่ต้องให้ CA ตื่น)
//

import SwiftUI
import AppKit
import QuartzCore
import ImageIO

// MARK: - โหลดไฟล์ spritesheet

enum CapySprite {

    /// โหลดครั้งเดียวทั้งแอป (เป็น CGImage เต็มแผ่น — ไม่ต้องหั่น เพราะใช้ contentsRect เลื่อนกรอบ)
    static let sheet: CGImage? = {
        guard let url = locate(),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }()

    /// 1) ใน .app → Contents/Resources/capybeats.png
    /// 2) ตอน dev (`swift run`) → ไล่โฟลเดอร์แม่ขึ้นไปจนเจอ capybeats.png ที่รากของ repo
    static func locate() -> URL? {
        if let inBundle = Bundle.main.url(forResource: "capybeats", withExtension: "png") {
            return inBundle
        }
        let start = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
        var dir = start.deletingLastPathComponent().standardizedFileURL
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("capybeats.png")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent == dir { break }
            dir = parent
        }
        return nil
    }
}

// MARK: - NSView ที่ถือ layer ของ sprite

final class CapyLayerView: NSView {

    private let sprite = CALayer()
    private var animating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        sprite.contents = CapySprite.sheet
        sprite.magnificationFilter = .nearest   // image-rendering: pixelated
        sprite.minificationFilter = .nearest
        sprite.contentsGravity = .resize
        sprite.contentsRect = Self.frameRect(0)
        sprite.isOpaque = false
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) { fatalError("ไม่ได้ใช้ storyboard") }

    /// การ์ดไม่ควรโดนคาปิบาร่าบังคลิก (pointer-events: none ของ jsx)
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        sprite.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if animating { startAnimation() }
    }

    func setAnimating(_ on: Bool) {
        guard on != animating else { return }
        animating = on
        on ? startAnimation() : sprite.removeAnimation(forKey: "capybeats")
    }

    private func startAnimation() {
        guard sprite.animation(forKey: "capybeats") == nil, CapySprite.sheet != nil else { return }
        let animation = CAKeyframeAnimation(keyPath: "contentsRect")
        // 72 เฟรม + เฟรมแรกซ้ำท้าย → ได้ 72 ช่วงเท่ากันช่วงละ 0.1 วิ พอดี
        // (ถ้าไม่ซ้ำท้าย CA จะหาร duration ด้วย 71 ช่วง แล้วจังหวะเพี้ยนไปนิดนึง)
        animation.values = (0...Metrics.capyFrames).map { NSValue(rect: Self.frameRect($0 % Metrics.capyFrames)) }
        animation.calculationMode = .discrete
        animation.duration = Metrics.capyLoopDuration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        sprite.add(animation, forKey: "capybeats")
    }

    /// กรอบของเฟรมที่ i ในหน่วย 0…1 ของภาพเต็มแผ่น (เรียงซ้าย→ขวา แล้วลงแถวถัดไป — เหมือน CAPY_CSS ของ jsx)
    ///
    /// ⚠️ `contentsRect` วัด y จาก **ล่าง** ของภาพ (layer ที่ถูก host ในแอปนี้ contentsAreFlipped = false)
    /// ยืนยันด้วยการเรนเดอร์จริงแล้ว: สูตรเดิม `y = row*h` ทำให้ index 0 โชว์แถวล่างสุดของ spritesheet
    /// → แถวเล่นกลับหลัง ต้องกลับด้านแถวเอง
    private static func frameRect(_ index: Int) -> NSRect {
        let column = index % Metrics.capyColumns
        let row = index / Metrics.capyColumns
        let w = 1.0 / CGFloat(Metrics.capyColumns)
        let h = 1.0 / CGFloat(Metrics.capyRows)
        return NSRect(x: CGFloat(column) * w, y: 1 - CGFloat(row + 1) * h, width: w, height: h)
    }
}

// MARK: - หน้าตาฝั่ง SwiftUI

struct CapybaraView: NSViewRepresentable {
    /// false = การ์ดถูกซ่อน/ย่อ → หยุด animation ไปเลย
    var animating: Bool

    func makeNSView(context: Context) -> CapyLayerView {
        let view = CapyLayerView(frame: NSRect(x: 0, y: 0, width: Metrics.capyWidth, height: Metrics.capyHeight))
        view.setAnimating(animating)
        return view
    }

    func updateNSView(_ view: CapyLayerView, context: Context) {
        view.setAnimating(animating)
    }
}
