//
//  main.swift — รันเช็กทั้งหมดของ UsageCore
//
//    cd app && swift run UsageCoreChecks      (exit 0 = ผ่าน, exit 1 = พัง)
//
//  ไม่ใช้ `swift test` เพราะเครื่องเป้าหมายมีแค่ Command Line Tools — ดูเหตุผลใน Harness.swift
//

import Foundation
import UsageCore

// `swift run UsageCoreChecks --live` = ยิงสคริปต์จริงแล้วพิมพ์สิ่งที่ core อ่านได้
// (ใช้ตอน integrate/verify เทียบกับ widget Übersicht — ไม่ส่ง --force จึงใช้ cache 5 นาทีของสคริปต์)
if CommandLine.arguments.contains("--live") {
    do {
        let script = try ScriptLocator.find()
        print("script: \(script.path)")
        let snapshot = try await ScriptUsageFetcher(scriptURL: script).fetch(force: false)
        print("status: \(snapshot.status) · plan: \(snapshot.plan ?? "-") · fetched: \(snapshot.fetchedAt.map { ResetFormat.clock($0) } ?? "-")")
        let budgets = Pacing(store: InMemoryAnchorStore()).budgets(for: snapshot)
        for limit in snapshot.limits {
            var line = "  \(limit.title): \(limit.displayPercent)%"
            if let reset = limit.resetsAt {
                line += limit.kind == .session
                    ? " · " + ResetFormat.relative(reset, now: Date())
                    : " · " + ResetFormat.absolute(reset)
            }
            if let b = budgets[limit.id] {
                line += String(format: " · เป้าวันนี้ ~%d%% (เหลือ %.1f วัน%@)",
                               b.displayTarget, b.daysLeft, b.cappedByWeekly ? " · ถูกแคป" : "")
            }
            print(line)
        }
        exit(0)
    } catch {
        print("❌ \(error.localizedDescription)")
        exit(1)
    }
}

let checks = Checks()

print("UsageCore checks")
print(String(repeating: "═", count: 52))

runParserChecks(checks)
runPacingChecks(checks)
await runFetcherChecks(checks)

checks.summary()
