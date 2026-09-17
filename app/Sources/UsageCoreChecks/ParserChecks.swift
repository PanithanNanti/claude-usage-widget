import Foundation
import UsageCore

func runParserChecks(_ c: Checks) {
    c.suite("Parser · response จริง")
    if let s = try? UsageParser.parse(Sample.data(Sample.real)) {
        c.equal(s.status, .live, "สถานะ live")
        c.equal(s.plan, "Max (20×)", "ป้าย plan")
        c.isNil(s.errorCode, "ไม่มี _error")
        c.equal(s.needsLogin, false, "ไม่ต้องล็อกอิน")
        c.equal(s.limits.map(\.id), ["session", "weekly_all", "weekly_scoped:Fable"], "id ของทุกแถว")
        c.equal(s.limits.map(\.title),
                ["เซสชันปัจจุบัน", "สัปดาห์นี้ (ทุกโมเดล)", "สัปดาห์ · Fable"], "ชื่อแถวภาษาไทย")
        c.equal(s.limits.map(\.kind), [.session, .weeklyAll, .weeklyScoped], "kind ของทุกแถว")
        c.equal(s.limits.map(\.percent), [19, 24, 28], "percent ของทุกแถว")
        c.equal(s.sessionPercent, 19, "sessionPercent")
        if let fetched = c.notNil(s.fetchedAt, "_fetched_at ถูก parse") {
            // 2026-09-17T10:58:53.325473+07:00
            c.close(fetched.timeIntervalSince1970, 1789617533.325, "_fetched_at ตรงเวลา", tolerance: 0.01)
        }
        if let weekly = c.notNil(s.limit(id: "weekly_all")?.resetsAt, "resets_at ของ weekly_all") {
            c.equal(ISODate.resetKey(weekly), "2026-09-21T06:00:00Z", "resetKey ของ weekly_all")
        }
    } else {
        c.expect(false, "parse response จริงไม่ผ่าน")
    }

    c.suite("Parser · fallback five_hour/seven_day")
    if let s = try? UsageParser.parse(Sample.data(Sample.fallback)) {
        c.equal(s.limits.count, 2, "ได้ 2 แถว")
        c.equal(s.limits.map(\.id), ["session", "weekly_all"], "id ของแถว fallback")
        c.equal(s.limits[0].percent, 41.5, "percent เก็บค่าดิบ (ไม่ปัด)")
        c.equal(s.limits[0].displayPercent, 42, "displayPercent ปัดให้")
        c.equal(s.limits[1].percent, 33, "weekly_all percent")
        c.expect(s.limits[1].resetsAt != nil, "weekly_all มี resets_at")
        c.equal(s.plan, "Max (5×)", "ป้าย plan")
    } else {
        c.expect(false, "parse fallback ไม่ผ่าน")
    }

    c.suite("Parser · fallback ที่ไม่มีตัวเลขเลย → ไม่มีแถว")
    // ห้ามปั้นแถว 0% มาทับข้อมูลดี — UsageViewModel อาศัยกติกา "ไม่มีแถว = คงของเดิม"
    if let s = try? UsageParser.parse(Sample.data(#"{"_status":"live","limits":[]}"#)) {
        c.equal(s.limits.count, 0, "limits[] ว่าง → ไม่มีแถว")
        c.equal(s.status, .live, "สถานะยัง live")
    } else {
        c.expect(false, "parse limits ว่างไม่ผ่าน")
    }
    if let s = try? UsageParser.parse(Sample.data(#"{"five_hour":null,"seven_day":null,"_status":"live"}"#)) {
        c.equal(s.limits.count, 0, "five_hour/seven_day = null → ไม่มีแถว")
    } else {
        c.expect(false, "parse five_hour/seven_day null ไม่ผ่าน")
    }
    if let s = try? UsageParser.parse(Sample.data(#"{"five_hour":{"utilization":null},"seven_day":{"utilization":null},"_status":"live"}"#)) {
        c.equal(s.limits.count, 0, "utilization = null ทั้งคู่ → ไม่มีแถว")
    }
    if let s = try? UsageParser.parse(Sample.data(#"{"seven_day":{"utilization":12},"_status":"live"}"#)) {
        c.equal(s.limits.count, 2, "มีตัวเลขฝั่งเดียวก็ยังได้ 2 แถว")
        c.equal(s.limits[0].percent, 0, "ฝั่งที่ไม่มีเลข = 0%")
        c.equal(s.limits[1].percent, 12, "ฝั่งที่มีเลขถูกอ่าน")
    }

    c.suite("Parser · ฟิลด์ null ทั้งหมด")
    if let s = try? UsageParser.parse(Sample.data(Sample.nulls)) {
        c.equal(s.limits.count, 0, "null ทุกอย่าง → ไม่มีแถว (ไม่ปั้น 0% หลอกตา)")
        c.isNil(s.plan, "_plan null → nil")
        c.isNil(s.fetchedAt, "_fetched_at null → nil")
        c.isNil(s.errorCode, "_error null → nil")
        c.equal(s.status, .live, "สถานะ live")
        c.isNil(s.sessionPercent, "ไม่มีแถว session → sessionPercent nil")
    } else {
        c.expect(false, "parse null sample ไม่ผ่าน")
    }

    c.suite("Parser · weekly_scoped 0% ต้องไม่หาย")
    if let s = try? UsageParser.parse(Sample.data(Sample.zeroScoped)) {
        c.equal(s.limits.map(\.id), ["session", "weekly_all", "weekly_scoped:Fable"],
                "แถว Fable 0% ยังอยู่ (และ kind แปลกใหม่ถูกข้าม)")
        c.equal(s.limit(id: "weekly_scoped:Fable")?.percent, 0, "Fable = 0%")
    } else {
        c.expect(false, "parse zeroScoped ไม่ผ่าน")
    }

    c.suite("Parser · scope/display_name หาย")
    let noName = #"{"limits":[{"kind":"weekly_scoped","percent":5,"resets_at":null,"scope":null}],"_status":"live"}"#
    if let s = try? UsageParser.parse(Sample.data(noName)) {
        c.equal(s.limits.map(\.id), ["weekly_scoped:โมเดล"], "ใช้ชื่อสำรอง 'โมเดล'")
        c.equal(s.limits.map(\.title), ["สัปดาห์ · โมเดล"], "ชื่อแถวสำรอง")
    } else {
        c.expect(false, "parse scope null ไม่ผ่าน")
    }

    c.suite("Parser · ผลลัพธ์ที่ไม่ใช่ JSON")
    c.throwsError("HTML ของ Cloudflare → throw") { _ = try UsageParser.parse(Sample.data("Just a moment...")) }
    c.throwsError("ข้อมูลว่าง → throw") { _ = try UsageParser.parse(Data()) }
    c.throwsError("JSON ที่ไม่ใช่ object → throw") { _ = try UsageParser.parse(Sample.data("[1,2,3]")) }

    // ── FetchStatus mapping (เทียบ errInfo() + render path ของ jsx) ──
    c.suite("FetchStatus · live")
    c.equal(status(#"{"_status":"live","limits":[]}"#), .live, "_status live")
    c.equal(status(#"{"limits":[]}"#), .live, "ไม่มี _status → live (เหมือน jsx)")

    c.suite("FetchStatus · stale")
    if let s = try? UsageParser.parse(Sample.data(#"{"_status":"stale","_error":"rate_limit","limits":[]}"#)) {
        c.equal(s.status, .stale(reason: "พัก 429 · รอรอบใหม่"), "backoff 429")
        c.equal(s.errorCode, "rate_limit", "errorCode ดิบ")
        c.equal(s.needsLogin, false, "429 ไม่ต้องล็อกอิน")
        c.equal(s.errorInfo?.message, "โดน rate limit (429) — พักยิง ~15 นาทีแล้วลองใหม่เอง", "ข้อความเต็ม")
    }
    if let s = try? UsageParser.parse(Sample.data(#"{"_status":"stale","_error":"auth","limits":[]}"#)) {
        c.equal(s.status, .stale(reason: "token หมดอายุ"), "token หมดอายุ")
        c.equal(s.needsLogin, true, "token หมดอายุ → โชว์ปุ่มล็อกอิน")
    }
    if let s = try? UsageParser.parse(Sample.data(#"{"_status":"stale","_error":"network"}"#)) {
        c.equal(s.status, .stale(reason: "เน็ตมีปัญหา"), "เน็ตมีปัญหา")
        c.equal(s.needsLogin, false, "network ไม่ต้องล็อกอิน")
    }
    if let s = try? UsageParser.parse(Sample.data(#"{"_status":"stale","_error":"http_502"}"#)) {
        c.equal(s.status, .stale(reason: "ดึงข้อมูลไม่ได้"), "รหัสที่ไม่รู้จัก")
        c.equal(s.errorCode, "http_502", "errorCode ดิบยังอยู่ให้ UI ใช้")
    }

    c.suite("FetchStatus · error (ไม่มี cache)")
    if let s = try? UsageParser.parse(Sample.data(#"{"_status":"error","_error":"no_token"}"#)) {
        c.equal(s.status, .error(message: "ยังไม่ได้ล็อกอิน Claude Code หรือหา token ไม่เจอ", needsLogin: true),
                "ยังไม่ได้ล็อกอิน")
        c.equal(s.needsLogin, true, "ต้องล็อกอิน")
    }
    c.equal(status(#"{"_status":"error","_error":"rate_limit"}"#),
            .error(message: "โดน rate limit (429) — พักยิง ~15 นาทีแล้วลองใหม่เอง", needsLogin: false),
            "429 ตอนไม่มี cache")
    c.equal(status(#"{"_status":"error"}"#),
            .error(message: "ดึงข้อมูลไม่ได้", needsLogin: false), "error ไม่มีรหัส")

    // ── ISODate / ResetFormat ──
    c.suite("ISODate")
    c.expect(ISODate.parse("2026-09-21T06:00:01.126168+00:00") != nil, "เศษวินาที 6 หลัก + offset")
    c.expect(ISODate.parse("2026-09-17T10:58:53.325473+07:00") != nil, "offset +07:00")
    c.expect(ISODate.parse("2026-09-28T06:00:00Z") != nil, "ไม่มีเศษวินาที")
    c.expect(ISODate.parse("2026-09-28T06:00:00.123Z") != nil, "เศษวินาที 3 หลัก")
    c.isNil(ISODate.parse(nil), "nil → nil")
    c.isNil(ISODate.parse(""), "ว่าง → nil")
    c.isNil(ISODate.parse("ไม่ใช่เวลา"), "ข้อความมั่ว → nil")
    if let a = ISODate.parse("2026-09-17T10:58:53.325473+07:00"),
       let b = ISODate.parse("2026-09-17T03:58:53.325473+00:00") {
        c.close(a.timeIntervalSince(b), 0, "offset ถูกคิดจริง ไม่ได้มองเป็น UTC")
    }

    c.suite("ISODate.resetKey (กัน resets_at สั่น)")
    if let base = ISODate.parse("2026-09-21T06:00:00Z") {
        c.equal(ISODate.resetKey(base.addingTimeInterval(1.126168)),
                ISODate.resetKey(base.addingTimeInterval(0.126364)),
                "เศษวินาทีต่างกัน → คีย์เดียวกัน")
        c.equal(ISODate.resetKey(base.addingTimeInterval(-0.4)), "2026-09-21T06:00:00Z", "ปัดเป็นนาที")
        c.equal(ISODate.resetKey(base.addingTimeInterval(120)), "2026-09-21T06:02:00Z", "คนละนาที = คนละคีย์")
    }

    c.suite("ResetFormat")
    let bangkok = gregorian("Asia/Bangkok")
    if let now = ISODate.parse("2026-09-17T04:00:00Z") {
        c.equal(ResetFormat.relative(now.addingTimeInterval(3 * 3600 + 42 * 60 + 30), now: now),
                "รีเซ็ตใน 3ชม. 42นาที", "เวลาเหลือแบบ relative")
        c.equal(ResetFormat.relative(now.addingTimeInterval(-500), now: now),
                "รีเซ็ตใน 0ชม. 0นาที", "เวลาติดลบถูกหนีบเป็น 0")
    }
    if let weekly = ISODate.parse("2026-09-21T06:00:01.126168+00:00") {
        c.equal(ResetFormat.absolute(weekly, calendar: bangkok), "รีเซ็ต จ 21/09 13:00", "เวลา reset แบบเต็ม")
        c.equal(ResetFormat.clock(weekly, calendar: bangkok), "13:00", "นาฬิกาในบรรทัดท้ายการ์ด")
    }
}

private func status(_ json: String) -> FetchStatus? {
    try? UsageParser.parse(Sample.data(json)).status
}

func gregorian(_ tz: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    return c
}
