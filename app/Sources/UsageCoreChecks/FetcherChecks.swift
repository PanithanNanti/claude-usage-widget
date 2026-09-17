import Foundation
import UsageCore

/// เขียนสคริปต์ปลอมลง temp dir (คืน URL ของไฟล์)
private func makeScript(_ body: String) throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("usagecore-checks-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("fake-usage.sh")
    try ("#!/bin/bash\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

func runFetcherChecks(_ c: Checks) async {

    c.suite("ScriptUsageFetcher · ทางปกติ")
    if let script = try? makeScript(#"echo '{"_status":"live","_plan":"Max (20×)","limits":[{"kind":"session","percent":7,"resets_at":null}]}'"#) {
        defer { cleanup(script) }
        do {
            let snapshot = try await ScriptUsageFetcher(scriptURL: script).fetch(force: false)
            c.equal(snapshot.status, .live, "สถานะ live")
            c.equal(snapshot.sessionPercent, 7, "อ่าน percent ได้")
            c.equal(snapshot.plan, "Max (20×)", "อ่าน plan ได้")
        } catch {
            c.expect(false, "ไม่ควร throw: \(error)")
        }
    }

    c.suite("ScriptUsageFetcher · args + PATH")
    if let script = try? makeScript(#"printf '{"_status":"live","_plan":"%s | %s","limits":[]}\n' "$*" "$PATH""#) {
        defer { cleanup(script) }
        let fetcher = ScriptUsageFetcher(scriptURL: script)
        if let plain = try? await fetcher.fetch(force: false), let echoed = plain.plan {
            c.expect(echoed.hasPrefix("--json |"), "ส่ง --json อย่างเดียวตอนไม่ force — ได้ '\(echoed.prefix(30))'")
            for dir in ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin"] {
                c.expect(echoed.contains(dir), "PATH ต้องมี \(dir) (แอป GUI ได้ env มาน้อย)")
            }
        } else {
            c.expect(false, "รันสคริปต์ปลอมไม่ผ่าน")
        }
        if let forced = try? await fetcher.fetch(force: true), let echoed = forced.plan {
            c.expect(echoed.hasPrefix("--json --force |"), "ส่ง --force ต่อท้ายตอน force")
        } else {
            c.expect(false, "รันแบบ --force ไม่ผ่าน")
        }
    }

    c.suite("ScriptUsageFetcher · ผลลัพธ์ไม่ใช่ JSON")
    if let script = try? makeScript("echo 'Just a moment...' ; echo 'boom' >&2") {
        defer { cleanup(script) }
        await c.throwsUsageError(.invalidOutput(contains: ["Just a moment", "boom"]),
                                 "error ต้องบอกทั้ง stdout และ stderr") {
            _ = try await ScriptUsageFetcher(scriptURL: script).fetch(force: false)
        }
    }

    c.suite("ScriptUsageFetcher · ไม่พ่นอะไรเลย")
    if let script = try? makeScript("exit 3") {
        defer { cleanup(script) }
        await c.throwsError("output ว่าง → throw") {
            _ = try await ScriptUsageFetcher(scriptURL: script).fetch(force: false)
        }
    }

    c.suite("ScriptUsageFetcher · timeout")
    if let script = try? makeScript("sleep 30") {
        defer { cleanup(script) }
        let started = Date()
        await c.throwsUsageError(.timedOut, "สคริปต์ค้าง → timedOut") {
            _ = try await ScriptUsageFetcher(scriptURL: script, timeout: 0.5).fetch(force: false)
        }
        c.expect(Date().timeIntervalSince(started) < 10, "ต้องฆ่าโปรเซสจริง ไม่ค้างยาว")
    }

    c.suite("ScriptUsageFetcher · หาสคริปต์ไม่เจอ")
    await c.throwsUsageError(.scriptNotFound(path: "/nope/claude-usage.sh"), "บอก path ที่หาไม่เจอ") {
        _ = try await ScriptUsageFetcher(scriptURL: URL(fileURLWithPath: "/nope/claude-usage.sh"))
            .fetch(force: false)
    }

    c.suite("ScriptLocator")
    do {
        let candidates = ScriptLocator.candidates(env: [:])
        c.expect(!candidates.isEmpty, "มี candidate อย่างน้อยหนึ่ง path")
        c.expect(candidates.allSatisfy { $0.lastPathComponent == ScriptLocator.scriptName },
                 "ทุก candidate ชี้ไปที่ claude-usage.sh")
        // รันจาก app/.build/debug → ต้องไล่ขึ้นไปเจอสคริปต์ที่รากของ repo
        if let found = try? ScriptLocator.find(env: [:]) {
            c.expect(found.lastPathComponent == ScriptLocator.scriptName, "เจอสคริปต์จริงตอน dev: \(found.path)")
        } else {
            print("  (ข้าม: รันจากที่ที่ไม่มี claude-usage.sh อยู่ในสายโฟลเดอร์แม่)")
        }
    }

    c.suite("ScriptLocator · env CLAUDE_USAGE_SCRIPT = คำสั่ง ไม่ใช่ข้อเสนอ")
    do {
        let env = ["CLAUDE_USAGE_SCRIPT": "/nope/fake-usage.sh"]
        c.equal(ScriptLocator.candidates(env: env).map(\.path), ["/nope/fake-usage.sh"],
                "ตั้ง env แล้ว = candidate ตัวเดียว (ห้าม fallback ไป bundle)")
        do {
            _ = try ScriptLocator.find(env: env)
            c.expect(false, "ไฟล์ตาม env ไม่มี → ควร throw")
        } catch {
            c.equal(error as? UsageError, .scriptNotFound(tried: ["/nope/fake-usage.sh"]),
                    "error บอก path ของ env ตัวเดียว")
        }
        c.expect(ScriptLocator.candidates(env: ["CLAUDE_USAGE_SCRIPT": ""]).count > 1,
                 "env ค่าว่าง = ไม่ได้ตั้ง → ไล่หาตามลำดับเดิม")
        c.equal(ScriptLocator.envOverride(["CLAUDE_USAGE_SCRIPT": "~/x.sh"])?.path,
                (("~/x.sh" as NSString).expandingTildeInPath), "ขยาย ~ ให้")
    }

    c.suite("UsageError · ข้อความบนจอต้องสั้นและไม่มีความลับ")
    do {
        let many = UsageError.scriptNotFound(tried: (1...15).map { "/a/very/long/candidate/path/number-\($0)/claude-usage.sh" })
        let shown = many.errorDescription ?? ""
        c.expect(shown.count < 120, "หลาย candidate → ข้อความสั้น (\(shown.count) ตัวอักษร)")
        c.expect(!shown.contains("number-7"), "ไม่มีรายการ path บนจอ")
        c.expect(many.diagnosticDescription.contains("number-7"), "รายการเต็มยังอยู่ใน diagnosticDescription")
        let one = UsageError.scriptNotFound(path: "/nope/fake-usage.sh")
        c.expect((one.errorDescription ?? "").contains("/nope/fake-usage.sh"),
                 "path เดียว (env บังคับ) → บอกไฟล์ที่หายไปเลย")

        let secret = #"+ curl -H 'Authorization: Bearer sk-ant-oat01-TESTTOKEN' ... token=sk-ant-oat01-TESTTOKEN"#
        let bad = UsageError.invalidOutput(detail: UsageError.redact(secret))
        for text in [bad.errorDescription ?? "", bad.diagnosticDescription, UsageError.redact(secret)] {
            c.expect(!text.contains("sk-ant"), "ห้ามมี token หลุดออกมา — ได้ '\(text.prefix(60))'")
            c.expect(!text.lowercased().contains("bearer"), "ห้ามมีคำว่า Bearer ตามด้วยของจริง")
        }
        c.expect((bad.errorDescription ?? "").contains("ไม่ใช่ JSON"), "ยังบอกผู้ใช้ว่าผลลัพธ์เพี้ยน")
        c.expect(UsageError.redact(String(repeating: "x", count: 900)).count <= 301, "detail ถูกจำกัดความยาว")
    }

    c.suite("ScriptUsageFetcher · stdout/stderr ที่มีความลับต้องถูกกลบ")
    if let script = try? makeScript(#"echo 'Bearer sk-ant-oat01-TESTTOKEN' ; echo 'x sk-ant-oat01-TESTTOKEN' >&2"#) {
        defer { cleanup(script) }
        do {
            _ = try await ScriptUsageFetcher(scriptURL: script).fetch(force: false)
            c.expect(false, "ผลลัพธ์ไม่ใช่ JSON → ควร throw")
        } catch let error as UsageError {
            c.expect(!error.diagnosticDescription.contains("sk-ant"), "token ไม่อยู่ใน diagnostic")
            c.expect(!(error.errorDescription ?? "").contains("sk-ant"), "token ไม่อยู่ในข้อความบนจอ")
            if case .invalidOutput(let detail) = error {
                c.expect(!detail.contains("sk-ant"), "token ไม่ถูกเก็บไว้ใน error ตั้งแต่ต้น")
            } else {
                c.expect(false, "ควรเป็น invalidOutput")
            }
        } catch {
            c.expect(false, "ควรเป็น UsageError: \(error)")
        }
    }

    c.suite("ScriptUsageFetcher · timeout ที่มาพร้อมกับโปรเซสจบพอดี")
    // สคริปต์จบเร็วกว่า timeout นิดเดียว → ห้ามถูกตีตรา timedOut แล้วทิ้งข้อมูลดี
    if let script = try? makeScript(#"sleep 0.4; echo '{"_status":"live","limits":[{"kind":"session","percent":3}]}'"#) {
        defer { cleanup(script) }
        do {
            let snapshot = try await ScriptUsageFetcher(scriptURL: script, timeout: 1.0).fetch(force: false)
            c.equal(snapshot.sessionPercent, 3, "ได้ payload ที่ดี ไม่โดน timeout ตัดทิ้ง")
        } catch {
            c.expect(false, "ไม่ควร throw: \(error)")
        }
    }
}
