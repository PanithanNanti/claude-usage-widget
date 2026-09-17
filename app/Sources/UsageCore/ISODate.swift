//
//  ISODate.swift — แปลงสตริงเวลา ISO-8601 ที่ API/สคริปต์ส่งมา
//
//  ตัวอย่างจริงที่เจอ:
//    "2026-09-21T06:00:01.126168+00:00"   ← resets_at (เศษวินาที 6 หลัก)
//    "2026-09-17T10:58:53.325473+07:00"   ← _fetched_at (จาก python isoformat())
//    "2026-09-21T06:00:00Z"               ← เผื่อรูปแบบไม่มีเศษวินาที
//
//  ISO8601DateFormatter ของ Apple รับเศษวินาทีได้ไม่เกิน 3 หลักในบางเวอร์ชัน
//  → ตัดเศษเหลือ 3 หลักก่อนเป็น fallback
//

import Foundation

public enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let lock = NSLock()

    /// คืน nil เมื่อ string เป็น nil/ว่าง/แปลงไม่ได้ (ห้าม crash — ฟิลด์นี้ null ได้เสมอ)
    public static func parse(_ string: String?) -> Date? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let d = withFraction.date(from: raw) { return d }
        if let d = plain.date(from: raw) { return d }
        // เศษวินาทียาวเกิน → ตัดเหลือ 3 หลักแล้วลองใหม่ (เช่น .126168 → .126)
        if let trimmed = truncatingFraction(raw) {
            if let d = withFraction.date(from: trimmed) { return d }
            if let d = plain.date(from: trimmed) { return d }
        }
        return nil
    }

    /// ตัดเศษวินาทีให้เหลือไม่เกิน 3 หลัก (คืน nil ถ้าไม่มีเศษวินาทีให้ตัด)
    private static func truncatingFraction(_ s: String) -> String? {
        guard let dot = s.firstIndex(of: ".") else { return nil }
        var digitsEnd = s.index(after: dot)
        while digitsEnd < s.endIndex, s[digitsEnd].isNumber {
            digitsEnd = s.index(after: digitsEnd)
        }
        let digits = s[s.index(after: dot)..<digitsEnd]
        guard digits.count > 3 else { return nil }
        let keep = digits.prefix(3)
        return String(s[s.startIndex...dot]) + keep + String(s[digitsEnd...])
    }

    /// คีย์เปรียบเทียบเวลา reset — **ปัดเป็นนาที** แล้วเขียนเป็น UTC
    ///
    /// ทำไมต้องปัด: `resets_at` ที่ API ส่งมา "สั่น" ระดับเศษวินาทีทุกครั้งที่ยิง
    /// (ของจริง: weekly_all = …T06:00:01.126168Z แต่ weekly_scoped = …T06:00:00.126364Z
    ///  และค่าเปลี่ยนไปเรื่อยๆ ระหว่าง fetch) — jsx เทียบสตริง ISO ดิบ (`a.reset !== resetIso`)
    /// จึงเข้าใจผิดว่า "ขึ้นรอบสัปดาห์ใหม่" แล้ว re-anchor ทิ้งทุกรอบ poll ทำให้เป้ารายวัน
    /// วิ่งตามการใช้งานระหว่างวันแทนที่จะคงที่ → ฝั่ง Swift ปัดเป็นนาทีเพื่ออุดรูนี้
    public static func resetKey(_ date: Date) -> String {
        let minutes = (date.timeIntervalSince1970 / 60).rounded()
        let rounded = Date(timeIntervalSince1970: minutes * 60)
        lock.lock()
        defer { lock.unlock() }
        return plain.string(from: rounded)
    }
}
