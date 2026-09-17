//
//  SampleJSON.swift — ผลจริงจาก `bash claude-usage.sh --json` (2026-09-17)
//  เก็บไว้ทั้งก้อนเพราะ "null เต็มไปหมด" คือส่วนที่ parser ต้องทน
//

import Foundation

enum Sample {
    /// response จริง (ตัดไม่ได้ — ต้องการ null ครบทุกแบบ)
    static let real = """
    {"five_hour": {"utilization": 19.0, "resets_at": "2026-09-17T05:10:00.126147+00:00", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null, "locked_reason": null}, "seven_day": {"utilization": 24.0, "resets_at": "2026-09-21T06:00:01.126168+00:00", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null, "locked_reason": null}, "seven_day_oauth_apps": null, "seven_day_opus": null, "seven_day_sonnet": null, "seven_day_cowork": null, "seven_day_omelette": null, "tangelo": null, "iguana_necktie": null, "omelette_promotional": null, "nimbus_quill": {"utilization": 0.0, "resets_at": null, "limit_dollars": null, "used_dollars": null, "remaining_dollars": null, "locked_reason": null}, "cinder_cove": null, "copper_kite": null, "harbor_lantern": null, "amber_ladder": null, "juniper_tide": null, "cedar_ember": null, "amber_gauge": null, "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null, "currency": null, "decimal_places": null, "disabled_reason": null, "user_disabled": true, "spend_limit_reached": false, "credits_ever_enabled": true, "daily": null, "weekly": null}, "limits": [{"kind": "session", "group": "session", "percent": 19, "severity": "normal", "resets_at": "2026-09-17T05:10:00.126147+00:00", "scope": null, "is_active": false}, {"kind": "weekly_all", "group": "weekly", "percent": 24, "severity": "normal", "resets_at": "2026-09-21T06:00:01.126168+00:00", "scope": null, "is_active": false}, {"kind": "weekly_scoped", "group": "weekly", "percent": 28, "severity": "normal", "resets_at": "2026-09-21T06:00:00.126364+00:00", "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": true}], "spend": {"used": {"amount_minor": 0, "currency": "USD", "exponent": 2}, "limit": null, "percent": 0, "severity": "normal", "enabled": false, "disabled_reason": null, "cap": null, "balance": null, "auto_reload": null, "disclaimer": "Usage credits cover you when you hit your plan limits.", "can_purchase_credits": false, "can_toggle": false}, "member_dashboard_available": false, "seven_day_breakdown": {"as_of": "2026-09-17T03:58:53.143279+00:00", "window_started_at": "2026-09-14T06:00:01.126168+00:00", "rows": [{"key": "claude_code", "display_name": "Claude Code", "percent": 83}, {"key": "chat", "display_name": "Chats", "percent": 3}, {"key": "cowork", "display_name": "Cowork", "percent": 14}, {"key": "other", "display_name": "Other", "percent": 0}]}, "_status": "live", "_plan": "Max (20\\u00d7)", "_fetched_at": "2026-09-17T10:58:53.325473+07:00"}
    """

    /// บัญชี/เวอร์ชันที่ไม่มี `limits[]`
    static let fallback = """
    {"five_hour": {"utilization": 41.5, "resets_at": "2026-09-17T05:10:00.126147+00:00"},
     "seven_day": {"utilization": 33, "resets_at": "2026-09-21T06:00:01.126168+00:00"},
     "seven_day_opus": null, "_status": "live", "_plan": "Max (5×)",
     "_fetched_at": "2026-09-17T10:58:53.325473+07:00"}
    """

    /// เคสโหดสุด: ทุกอย่าง null / ไม่มีเลย
    static let nulls = """
    {"five_hour": null, "seven_day": null, "limits": null, "_status": "live",
     "_plan": null, "_fetched_at": null, "_error": null}
    """

    /// สัปดาห์ใหม่ — Fable ยัง 0% (ต้องไม่หายไปจากผลลัพธ์)
    static let zeroScoped = """
    {"limits": [{"kind": "session", "percent": 0, "resets_at": null, "scope": null},
                {"kind": "weekly_all", "percent": 0.0, "resets_at": "2026-09-28T06:00:00Z", "scope": null},
                {"kind": "weekly_scoped", "percent": 0, "resets_at": "2026-09-28T06:00:00Z",
                 "scope": {"model": {"display_name": "Fable"}}},
                {"kind": "brand_new_kind", "percent": 99, "resets_at": null}],
     "_status": "live"}
    """

    static func data(_ s: String) -> Data { Data(s.utf8) }
}
