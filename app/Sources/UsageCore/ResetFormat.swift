//
//  ResetFormat.swift — ข้อความเวลารีเซ็ต (ภาษาไทย, โซนเวลาของเครื่อง)
//
//  พอร์ตตรงจาก `resetRelative()` / `resetAbsolute()` ใน claude-usage.jsx
//    session : "รีเซ็ตใน 3ชม. 42นาที"
//    weekly  : "รีเซ็ต จ 21/09 13:00"
//

import Foundation

public enum ResetFormat {
    /// ชื่อวันแบบย่อ เรียงตาม weekday ของ Gregorian (1 = อาทิตย์)
    static let thaiWeekdays = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]

    /// "รีเซ็ตใน Xชม. Yนาที" — ติดลบถูกหนีบเป็น 0 เหมือน jsx
    public static func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return "รีเซ็ตใน \(seconds / 3600)ชม. \((seconds % 3600) / 60)นาที"
    }

    /// "รีเซ็ต <วัน> DD/MM HH:MM" ตามโซนเวลาของเครื่อง
    public static func absolute(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        let weekdayIndex = max(1, min(7, c.weekday ?? 1)) - 1
        return String(format: "รีเซ็ต %@ %d/%02d %02d:%02d",
                      thaiWeekdays[weekdayIndex],
                      c.day ?? 0, c.month ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// "HH:MM" — ใช้ในบรรทัดท้ายการ์ด ("อัปเดต HH:MM")
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
