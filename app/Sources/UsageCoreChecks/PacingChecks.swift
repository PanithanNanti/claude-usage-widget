import Foundation
import UsageCore

/// 2026-09-17 11:00 ตามเวลาไทย
private let now = ISODate.parse("2026-09-17T04:00:00Z")!
private let tz = gregorian("Asia/Bangkok")

private func pacing(_ store: AnchorStore, at date: Date = now) -> Pacing {
    Pacing(store: store, now: { date }, calendar: tz)
}

/// สร้าง snapshot สังเคราะห์ — reset ของ weekly = now + daysLeft
private func snapshot(weeklyAll: Double? = nil,
                      scoped: Double? = nil,
                      session: Double? = 10,
                      daysLeft: Double = 4.18,
                      scopedJitter: TimeInterval = 0,
                      fetchedAt: Date? = now) -> UsageSnapshot {
    let reset = now.addingTimeInterval(daysLeft * 86_400)
    var limits: [UsageLimit] = []
    if let session {
        limits.append(UsageLimit(id: "session", kind: .session, title: "เซสชันปัจจุบัน",
                                 percent: session, resetsAt: now.addingTimeInterval(3600)))
    }
    if let weeklyAll {
        limits.append(UsageLimit(id: "weekly_all", kind: .weeklyAll, title: "สัปดาห์นี้ (ทุกโมเดล)",
                                 percent: weeklyAll, resetsAt: reset))
    }
    if let scoped {
        limits.append(UsageLimit(id: "weekly_scoped:Fable", kind: .weeklyScoped, title: "สัปดาห์ · Fable",
                                 percent: scoped, resetsAt: reset.addingTimeInterval(scopedJitter)))
    }
    return UsageSnapshot(limits: limits, plan: "Max (20×)", fetchedAt: fetchedAt, status: .live)
}

private func weeklyOnly(percent: Double, reset: Date, fetchedAt: Date?) -> UsageSnapshot {
    UsageSnapshot(limits: [UsageLimit(id: "weekly_all", kind: .weeklyAll, title: "สัปดาห์นี้ (ทุกโมเดล)",
                                      percent: percent, resetsAt: reset)],
                  plan: nil, fetchedAt: fetchedAt, status: .live)
}

func runPacingChecks(_ c: Checks) {

    c.suite("Pacing · สูตรหลัก (33% เหลือ 4.18 วัน → เป้า ~49%)")
    do {
        let store = InMemoryAnchorStore()
        let budgets = pacing(store).budgets(for: snapshot(weeklyAll: 33))
        if let b = c.notNil(budgets["weekly_all"], "มีเป้าของ weekly_all") {
            c.close(b.target, 49.0287, "เป้า = 33 + 67/4.18")
            c.equal(b.displayTarget, 49, "เป้าที่แสดง ~49%")
            c.close(b.remaining, 16.0287, "ใช้ได้อีก ~16%")
            c.close(b.daysLeft, 4.18, "เหลือ 4.18 วัน")
            c.equal(b.cappedByWeekly, false, "ไม่ถูกแคป")
            c.equal(b.isOverTarget, false, "ยังไม่เกินเป้า")
        }
        c.equal(store.anchors["weekly_all"]?.pct, 33, "anchor.pct ถูกบันทึก")
        c.equal(store.anchors["weekly_all"]?.day, "2026-09-17", "anchor.day เป็นวันนี้ (เวลาไทย)")
    }

    c.suite("Pacing · session ไม่มีเป้ารายวัน")
    do {
        let budgets = pacing(InMemoryAnchorStore()).budgets(for: snapshot(weeklyAll: 33, scoped: 10))
        c.isNil(budgets["session"], "ไม่มี entry ของ session")
        c.equal(budgets.keys.sorted(), ["weekly_all", "weekly_scoped:Fable"], "มีแค่ weekly")
    }

    c.suite("Pacing · ไม่มี resets_at / รีเซ็ตผ่านไปแล้ว")
    do {
        let noDate = UsageSnapshot(limits: [UsageLimit(id: "weekly_all", kind: .weeklyAll, title: "w",
                                                       percent: 10, resetsAt: nil)],
                                   plan: nil, fetchedAt: now, status: .live)
        c.expect(pacing(InMemoryAnchorStore()).budgets(for: noDate).isEmpty, "ไม่มี resets_at → ไม่มีเป้า")
        let past = weeklyOnly(percent: 10, reset: now.addingTimeInterval(-60), fetchedAt: now)
        c.expect(pacing(InMemoryAnchorStore()).budgets(for: past).isEmpty, "รีเซ็ตผ่านไปแล้ว → ไม่มีเป้า")
    }

    c.suite("Pacing · เป้าคงที่ทั้งวัน (ไม่ re-anchor ระหว่างวัน)")
    do {
        let store = InMemoryAnchorStore()
        _ = pacing(store).budgets(for: snapshot(weeklyAll: 33))
        let later = now.addingTimeInterval(3 * 3600)
        let snap = weeklyOnly(percent: 45, reset: now.addingTimeInterval(4.18 * 86_400), fetchedAt: later)
        if let b = c.notNil(pacing(store, at: later).budgets(for: snap)["weekly_all"], "ยังมีเป้า") {
            c.close(b.target, 49.0287, "เป้าเดิม (คิดจาก anchor.days = 4.18)")
            c.close(b.remaining, 4.0287, "ใช้ได้อีกลดลงตามการใช้จริง")
        }
        c.equal(store.anchors["weekly_all"]?.pct, 33, "anchor ไม่ถูกเขียนทับ")
    }

    c.suite("Pacing · ขึ้นวันใหม่ → anchor ใหม่")
    do {
        let store = InMemoryAnchorStore()
        _ = pacing(store).budgets(for: snapshot(weeklyAll: 33))
        let tomorrow = now.addingTimeInterval(86_400)
        let snap = weeklyOnly(percent: 45, reset: now.addingTimeInterval(4.18 * 86_400), fetchedAt: tomorrow)
        if let b = c.notNil(pacing(store, at: tomorrow).budgets(for: snap)["weekly_all"], "มีเป้าของวันใหม่") {
            c.close(b.target, 45 + 55 / 3.18, "เป้าใหม่คิดจาก 3.18 วันที่เหลือ")
        }
        c.equal(store.anchors["weekly_all"]?.day, "2026-09-18", "anchor.day ขยับ")
        c.equal(store.anchors["weekly_all"]?.pct, 45, "anchor.pct = ค่าตอนต้นวันใหม่")
    }

    c.suite("Pacing · ขึ้นรอบสัปดาห์ใหม่ (resets_at เปลี่ยนจริง) → anchor ใหม่")
    do {
        let store = InMemoryAnchorStore()
        _ = pacing(store).budgets(for: snapshot(weeklyAll: 90))
        c.equal(store.anchors["weekly_all"]?.pct, 90, "anchor เดิมของสัปดาห์ก่อน")
        let snap = weeklyOnly(percent: 2, reset: now.addingTimeInterval(7 * 86_400), fetchedAt: now)
        if let b = c.notNil(pacing(store).budgets(for: snap)["weekly_all"], "มีเป้าของสัปดาห์ใหม่") {
            c.close(b.target, 2 + 98 / 7, "เป้าใหม่ = 2 + 98/7")
        }
        c.equal(store.anchors["weekly_all"]?.pct, 2, "anchor.pct รีเซ็ตตาม")
    }

    c.suite("Pacing · resets_at สั่นระดับเศษวินาที → ห้าม re-anchor")
    do {
        let store = InMemoryAnchorStore()
        _ = pacing(store).budgets(for: snapshot(weeklyAll: 33))
        let anchored = store.anchors["weekly_all"]
        let jittered = weeklyOnly(percent: 40,
                                  reset: now.addingTimeInterval(4.18 * 86_400 + 0.98),
                                  fetchedAt: now)
        if let b = c.notNil(pacing(store).budgets(for: jittered)["weekly_all"], "ยังมีเป้า") {
            c.close(b.target, 49.0287, "เป้าไม่ถูกคำนวณใหม่")
        }
        c.equal(store.anchors["weekly_all"], anchored, "anchor ไม่ถูกเขียนทับเพราะเศษวินาที")
    }

    c.suite("Pacing · ข้อมูลไม่สด (fetch เมื่อวาน) → ห้ามตั้ง anchor")
    do {
        let store = InMemoryAnchorStore()
        let budgets = pacing(store).budgets(for: snapshot(weeklyAll: 33,
                                                          fetchedAt: now.addingTimeInterval(-86_400)))
        c.expect(store.anchors.isEmpty, "ไม่มี anchor ถูกเขียน")
        c.isNil(budgets["weekly_all"], "ยังบอกเป้าไม่ได้ ต้องรอข้อมูลสด")
        c.expect(pacing(store).budgets(for: snapshot(weeklyAll: 33, fetchedAt: nil)).isEmpty,
                 "fetchedAt = nil ก็ไม่ anchor")
    }

    c.suite("Pacing · มี anchor ของวันนี้แล้ว + fetch ไม่สด → ใช้ anchor เดิมได้")
    do {
        let store = InMemoryAnchorStore()
        _ = pacing(store).budgets(for: snapshot(weeklyAll: 33))
        let stale = snapshot(weeklyAll: 33, fetchedAt: now.addingTimeInterval(-86_400))
        if let b = c.notNil(pacing(store).budgets(for: stale)["weekly_all"], "ยังมีเป้า") {
            c.close(b.target, 49.0287, "เป้าเดิมยังใช้ได้")
        }
    }

    c.suite("Pacing · วันรีเซ็ต (<1 วัน) → เป้าชน cap 100")
    do {
        let store = InMemoryAnchorStore()
        if let b = c.notNil(pacing(store).budgets(for: snapshot(weeklyAll: 30, daysLeft: 0.5))["weekly_all"],
                            "มีเป้า") {
            c.equal(b.target, 100, "ปลดล็อกโควตาที่เหลือทั้งหมด")
            c.equal(b.remaining, 70, "ใช้ได้อีก 70%")
        }
    }

    c.suite("Pacing · แคปด้วย weekly รวม (weekly_all 70 / Fable 20)")
    do {
        let store = InMemoryAnchorStore()
        let budgets = pacing(store).budgets(for: snapshot(weeklyAll: 70, scoped: 20, daysLeft: 2))
        if let all = c.notNil(budgets["weekly_all"], "มีเป้า weekly_all") {
            c.equal(all.target, 85, "เป้า weekly รวม = 70 + 30/2")
        }
        if let fable = c.notNil(budgets["weekly_scoped:Fable"], "มีเป้า Fable") {
            c.equal(fable.target, 50, "เป้า Fable ถูกหั่นจาก 60 → min(60, 20 + (85−70)/0.5)")
            c.equal(fable.remaining, 30, "ใช้ได้อีก 30% บนสเกลของ bar Fable")
            c.equal(fable.cappedByWeekly, true, "ติดป้าย 'จำกัดโดยโควตาสัปดาห์รวม'")
            c.close(fable.daysLeft, 2, "วันที่เหลือเท่าเดิม")
        }
    }

    c.suite("Pacing · ใช้ Fable ล้วน (เส้นตัวเองตึงกว่า) → ไม่ถูกแคป")
    do {
        let budgets = pacing(InMemoryAnchorStore()).budgets(for: snapshot(weeklyAll: 10, scoped: 40, daysLeft: 2))
        if let fable = c.notNil(budgets["weekly_scoped:Fable"], "มีเป้า Fable") {
            c.equal(fable.target, 70, "เป้าของตัวเอง = 40 + 60/2")
            c.equal(fable.cappedByWeekly, false, "ไม่ถูกแคป")
        }
    }

    c.suite("Pacing · weekly รวมเกินเป้าแล้ว → เป้า Fable ติดลบ ถูกหนีบเป็น 0")
    do {
        // anchor ต้นวัน: weekly_all 50 / Fable 20 แล้วระหว่างวันใช้โมเดลอื่นหนักจน weekly_all = 95
        let resetKey = ISODate.resetKey(now.addingTimeInterval(2 * 86_400))
        let store = InMemoryAnchorStore([
            "weekly_all": Anchor(day: "2026-09-17", pct: 50, days: 2, reset: resetKey),
            "weekly_scoped:Fable": Anchor(day: "2026-09-17", pct: 20, days: 2, reset: resetKey),
        ])
        let budgets = pacing(store).budgets(for: snapshot(weeklyAll: 95, scoped: 20, daysLeft: 2))
        if let all = c.notNil(budgets["weekly_all"], "มีเป้า weekly_all") {
            c.equal(all.target, 75, "เป้า weekly รวม = 50 + 50/2")
            c.equal(all.remaining, -20, "เกินเป้าวันนี้ +20%")
            c.equal(all.isOverTarget, true, "ธงเกินเป้า")
        }
        if let fable = c.notNil(budgets["weekly_scoped:Fable"], "มีเป้า Fable") {
            c.equal(fable.target, 0, "เป้าติดลบ (−20) ถูกหนีบเป็น 0")
            c.equal(fable.displayTarget, 0, "แสดงเป็น 0%")
            c.equal(fable.remaining, -40, "ข้อความ 'เกินเป้าวันนี้ +40.0%'")
            c.equal(fable.cappedByWeekly, true, "ถูกแคปโดย weekly รวม")
        }
    }

    c.suite("Pacing · ไม่มี weekly_all → เป้า scoped ไม่ถูกแคป")
    do {
        let budgets = pacing(InMemoryAnchorStore()).budgets(for: snapshot(weeklyAll: nil, scoped: 20, daysLeft: 2))
        if let fable = c.notNil(budgets["weekly_scoped:Fable"], "มีเป้า Fable") {
            c.equal(fable.target, 60, "เป้าของตัวเองล้วน")
            c.equal(fable.cappedByWeekly, false, "ไม่ถูกแคป")
        }
    }

    c.suite("Pacing · anchor อยู่รอดข้ามการเปิดแอปใหม่")
    do {
        let store = InMemoryAnchorStore()
        _ = pacing(store).budgets(for: snapshot(weeklyAll: 33))
        let reloaded = InMemoryAnchorStore(store.anchors)
        if let b = c.notNil(pacing(reloaded).budgets(for: snapshot(weeklyAll: 38))["weekly_all"], "มีเป้า") {
            c.close(b.target, 49.0287, "เป้าเดิมถูกอ่านกลับมา")
        }
    }

    c.suite("UserDefaultsAnchorStore")
    do {
        let suiteName = "UsageCoreChecks." + UUID().uuidString
        if let defaults = c.notNil(UserDefaults(suiteName: suiteName), "สร้าง suite ได้") {
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = UserDefaultsAnchorStore(defaults: defaults)
            c.expect(store.load().isEmpty, "เริ่มต้นว่าง")
            let a = Anchor(day: "2026-09-17", pct: 33, days: 4.18, reset: "2026-09-21T06:00:00Z")
            store.save(["weekly_all": a])
            c.equal(UserDefaultsAnchorStore(defaults: defaults).load(), ["weekly_all": a], "เขียน/อ่านกลับได้")
        }
    }

    c.suite("Pacing · เดินจากข้อมูลจริง (response ของเครื่องนี้)")
    do {
        if let snap = try? UsageParser.parse(Sample.data(Sample.real)), let fetched = snap.fetchedAt {
            let store = InMemoryAnchorStore()
            let budgets = Pacing(store: store, now: { fetched }, calendar: tz).budgets(for: snap)
            c.equal(budgets.keys.sorted(), ["weekly_all", "weekly_scoped:Fable"], "ได้เป้าครบสอง bar")
            if let all = budgets["weekly_all"], let fable = budgets["weekly_scoped:Fable"] {
                c.expect(all.target > 24 && all.target <= 100, "เป้า weekly รวมอยู่ในช่วงที่สมเหตุสมผล")
                c.expect(fable.target >= 28, "เป้า Fable ไม่ต่ำกว่าที่ใช้ไปแล้ว")
                // fetched 2026-09-17T03:58:53Z → reset 2026-09-21T06:00:01Z = 4 วัน + 2:01:08
                c.close(all.daysLeft, 4.0841, "เหลือ ~4.08 วันถึงรีเซ็ต", tolerance: 0.01)
            }
        } else {
            c.expect(false, "parse ข้อมูลจริงไม่ผ่าน")
        }
    }
}
