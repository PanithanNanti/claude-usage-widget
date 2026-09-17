//
//  CardView.swift — การ์ดแบบ A (พอร์ตจาก paint()/rowHTML() ของ claude-usage.jsx)
//
//  โครง: [คาปิบาร่าเกาะขอบบน]
//        ┌───────────────────────────────┐
//        │ ✳  Claude Usage    Max (20×) ✕ │
//        │ [แถบเตือนข้อมูลค้าง ถ้ามี]        │
//        │ ชื่อ limit            X% ใช้ไป    │
//        │ ▇▇▇▇▇▇░░░░░░░│░░░░░░░░         │ ← เส้นขีด = เป้าของวันนี้
//        │ วันนี้ควรหยุดที่ ~X% · …          │
//        │ รีเซ็ต …                        │
//        │ ● อัปเดต HH:MM · ทุก 10 นาที >_ ↻ 🖥️│
//        └───────────────────────────────┘
//

import SwiftUI
import AppKit
import UsageCore

/// สิ่งที่การ์ดสั่งได้ (ผูกกับ CardWindowController — View ไม่รู้จัก NSWindow)
struct CardActions {
    var refresh: () -> Void = {}
    var collapse: () -> Void = {}
    var expand: () -> Void = {}
    var login: () -> Void = {}
    var openTerminal: () -> Void = {}
    var pickScreen: () -> Void = {}
    var dragChanged: () -> Void = {}
    var dragEnded: () -> Void = {}
}

// MARK: - ราก (สลับระหว่างการ์ดเต็มกับ pill + วางคาปิบาร่า)

struct CardRoot: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject var prefs: Preferences
    let actions: CardActions

    var body: some View {
        Group {
            if prefs.collapsed {
                PillView(model: model, actions: actions)
            } else {
                ZStack(alignment: .topLeading) {
                    CardView(model: model, actions: actions)
                        .padding(.top, Metrics.capyOverhang)
                    CapybaraView(animating: !prefs.collapsed && prefs.cardVisible)
                        .frame(width: Metrics.capyWidth, height: Metrics.capyHeight)
                        .padding(.leading, Metrics.capyLeft)
                        .allowsHitTesting(false)
                }
            }
        }
        .fixedSize()
    }
}

// MARK: - การ์ดเต็ม

struct CardView: View {
    @ObservedObject var model: UsageViewModel
    let actions: CardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let warning = model.staleWarning {
                StaleBanner(text: warning).padding(.bottom, 12)
            }
            if let message = model.errorBody {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.errText)
                    .lineSpacing(6)   // line-height: 1.55 ของ .cu-err
                    // หนีบไว้ 4 บรรทัด — ข้อความ error ยาวๆ เคยดันการ์ดสูงถึง 1279pt
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(model.limits) { limit in
                        LimitRow(limit: limit, budget: model.budgets[limit.id], now: model.tick)
                    }
                }
                .padding(.bottom, 4)
            }
            footer.padding(.top, 14)
        }
        .padding(EdgeInsets(top: 18, leading: Metrics.hPad, bottom: 15, trailing: Metrics.hPad))
        .frame(width: Metrics.cardWidth, alignment: .leading)
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 12)
    }

    // ── หัวการ์ด (ลากย้ายได้ทั้งแถบ เหมือน .cu-head) ──
    private var header: some View {
        HStack(spacing: 10) {
            LogoTile(size: 26, radius: 8, glyph: 15)
            Text("Claude Usage")
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.2)
                .foregroundColor(Theme.title)
            Spacer(minLength: 8)
            Text(model.plan)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(Theme.badgeText)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.orange.opacity(0.16)))
                .overlay(Capsule().strokeBorder(Theme.orange.opacity(0.3), lineWidth: 1))
                .fixedSize()
            Button(action: actions.collapse) {
                Text("✕")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.closeIcon)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("ย่อเป็นวงกลมเล็ก")
        }
        .padding(.bottom, 16)
        .contentShape(Rectangle())
        .gesture(
            // ลากด้วยหัวการ์ด — อ่านตำแหน่งเมาส์จริงจาก NSEvent ใน controller
            // (ใช้ translation ของ SwiftUI ไม่ได้ เพราะพอหน้าต่างขยับ พิกัดอ้างอิงก็ขยับตาม → สั่น)
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in actions.dragChanged() }
                .onEnded { _ in actions.dragEnded() }
        )
    }

    // ── ท้ายการ์ด ──
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack(spacing: 7) {
                Circle().fill(model.footColor).frame(width: 7, height: 7)
                Text(model.footText)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.rowReset)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    if model.needsLogin {
                        CardButton(title: "🔑",
                                   tint: Theme.badgeText,
                                   border: Theme.orange.opacity(0.32),
                                   help: "เปิด Claude เพื่อล็อกอิน/รีเฟรช token",
                                   action: actions.login)
                    }
                    CardButton(title: ">_", help: "เปิด terminal ที่ ~/dev", action: actions.openTerminal)
                    CardButton(title: model.isFetching ? "⟳ กำลังรีเฟรช" : "↻ รีเฟรช",
                               tint: model.isFetching ? Theme.blue : Theme.buttonText,
                               help: "ดึงข้อมูลใหม่เดี๋ยวนี้",
                               enabled: !model.isFetching,
                               action: actions.refresh)
                    CardButton(title: "🖥️", help: "เลือกจอที่จะให้การ์ดอยู่", action: actions.pickScreen)
                }
                .fixedSize()
            }
            .padding(.top, 12)
        }
    }
}

// MARK: - แถว limit

struct LimitRow: View {
    let limit: UsageLimit
    let budget: DailyBudget?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(limit.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Theme.rowName)
                Spacer(minLength: 6)
                Text("\(limit.displayPercent)% ใช้ไป")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Theme.rowPct)
                    .fixedSize()
            }
            .padding(.bottom, 6)

            UsageBar(percent: limit.displayPercent, target: budget?.target)

            if let budget {
                Text(Self.dailyText(budget))
                    .font(.system(size: 10))
                    .foregroundColor(budget.isOverTarget ? Theme.warn : Theme.daily)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if let reset = resetText {
                Text(reset)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.rowReset)
                    .padding(.top, 5)
            }
        }
    }

    private var resetText: String? {
        guard let date = limit.resetsAt else { return nil }
        return limit.kind == .session ? ResetFormat.relative(date, now: now) : ResetFormat.absolute(date)
    }

    /// ข้อความ pacing — ตรงกับ rowHTML() ของ jsx ทุกตัวอักษร
    static func dailyText(_ b: DailyBudget) -> String {
        let target = b.displayTarget
        let days = String(format: "%.1f", b.daysLeft)
        let why = b.cappedByWeekly ? " · จำกัดโดยโควตาสัปดาห์รวม" : ""
        if b.isOverTarget {
            return "เกินเป้าวันนี้ +\(String(format: "%.1f", -b.remaining))% (เป้า ~\(target)%) · เหลือ \(days) วัน" + why
        }
        return "วันนี้ควรหยุดที่ ~\(target)% · ใช้ได้อีก \(String(format: "%.1f", b.remaining))% · เหลือ \(days) วัน" + why
    }
}

/// แท่ง progress + เส้นขีดเป้าของวันนี้ (.cu-track / .cu-fill / .cu-mark)
struct UsageBar: View {
    let percent: Int
    let target: Double?

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.trackBG)
            Capsule()
                .fill(Theme.bar(percent))
                .frame(width: fillWidth)
            if let target {
                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.6), radius: 1.5)
                    .offset(x: markOffset(target))
            }
        }
        .frame(width: Metrics.contentWidth, height: 7)
    }

    private var fillWidth: CGFloat {
        // jsx: width: max(2, pct)% — เหลือหัวแท่งไว้ให้เห็นแม้ 0%
        let clamped = min(100, max(2, Double(percent)))
        return Metrics.contentWidth * CGFloat(clamped) / 100
    }

    private func markOffset(_ target: Double) -> CGFloat {
        let clamped = min(100, max(0, target))
        return min(Metrics.contentWidth - 2, Metrics.contentWidth * CGFloat(clamped) / 100)
    }
}

// MARK: - แถบเตือนข้อมูลค้าง (บทเรียน 17 ส.ค. — ต้องเด่นกว่าจุดเหลืองเล็กๆ)

struct StaleBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text("⚠︎").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.warn)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.warn.opacity(0.14)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.warn.opacity(0.38), lineWidth: 1)
        )
    }
}

// MARK: - pill ตอนย่อ (.cu-pill)

struct PillView: View {
    @ObservedObject var model: UsageViewModel
    let actions: CardActions

    var body: some View {
        // คลิก = กางการ์ด, ลาก = ย้ายตำแหน่ง
        // ใช้ Button (ไม่ใช่ onTapGesture) เพราะเป็นทางที่ยืนยันแล้วว่ารับคลิกได้จริงบนหน้าต่าง
        // ที่ไม่เคยเป็น key — แบบเดียวกับปุ่ม ✕ บนหัวการ์ด
        Button(action: actions.expand) {
            HStack(spacing: 6) {
                LogoTile(size: 22, radius: 7, glyph: 13)
                if let pct = model.sessionPercent {
                    Text("\(pct)%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.title)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 46, minHeight: 46)
            .background(GlassBackground())
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.42), radius: 14, x: 0, y: 8)
        // ⚠️ ต้องเป็น simultaneousGesture — `.gesture()` ธรรมดาบน Button ตัวเดียวกันจะ**กินคลิกทิ้ง**
        // (ยืนยันด้วย CGEvent จริง 17 ก.ย.: คลิก pill แล้วไม่กางเลย ทั้งที่ AXPress กางได้)
        // แลกกับการที่ปล่อยเมาส์หลังลากจะยิง action ด้วย → controller มี swallowClickAfterDrag() กันไว้
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in actions.dragChanged() }
                .onEnded { _ in actions.dragEnded() }
        )
        .help("กางการ์ด Claude Usage")
    }
}

// MARK: - ชิ้นส่วนเล็กๆ

struct LogoTile: View {
    let size: CGFloat
    let radius: CGFloat
    let glyph: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.orange)
            .frame(width: size, height: size)
            .overlay(Text("✳").font(.system(size: glyph)).foregroundColor(.white))
    }
}

struct CardButton: View {
    let title: String
    var tint: Color = Theme.buttonText
    var border: Color = Color.white.opacity(0.09)
    var help: String = ""
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

/// พื้นหลัง glassy = blur ของสิ่งที่อยู่ข้างหลัง (วอลเปเปอร์) + ทับด้วยสีเข้มโปร่ง
/// เทียบเท่า `backdrop-filter: blur(24px) saturate(140%)` + `rgba(24,24,28,0.72)` ของ jsx
struct GlassBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()
            Theme.cardTint
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active          // การ์ดไม่เคยเป็นหน้าต่าง key → ต้องบังคับ active ไม่งั้นสีจะจืด
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
    }
}
