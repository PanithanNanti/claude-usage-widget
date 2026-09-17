//
//  Harness.swift — ตัวรันเช็กแบบง่ายๆ (แทน XCTest)
//
//  ทำไมไม่ใช้ `swift test`: เครื่องนี้มีแค่ Command Line Tools
//    • XCTest      → ไม่มีเลย (`unable to resolve module dependency: 'XCTest'`)
//    • swift-testing → คอมไพล์ผ่านบ้างไม่ผ่านบ้าง — บิลด์เย็นๆ มักเจอ
//      `plugin for module 'TestingMacros' not found` แบบสุ่ม (บั๊กของ toolchain 6.4 ใน CLT)
//  → ใช้ executable ธรรมดาที่ assert เอง แล้ว exit 1 เมื่อพัง: `swift run UsageCoreChecks`
//

import Foundation
import UsageCore

final class Checks {
    private var failures: [String] = []
    private var passed = 0
    private var suiteName = ""

    func suite(_ name: String) {
        suiteName = name
        print("\n▸ \(name)")
    }

    func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if condition {
            passed += 1
        } else {
            let text = "  ✘ [\(suiteName):\(line)] \(message)"
            failures.append(text)
            print(text)
        }
    }

    func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: Int = #line) {
        expect(actual == expected, "\(message) — ได้ \(actual) แต่ควรเป็น \(expected)", line: line)
    }

    func close(_ actual: Double, _ expected: Double, _ message: String,
               tolerance: Double = 0.001, line: Int = #line) {
        expect(abs(actual - expected) < tolerance,
               "\(message) — ได้ \(actual) แต่ควรเป็น ~\(expected)", line: line)
    }

    func notNil<T>(_ value: T?, _ message: String, line: Int = #line) -> T? {
        expect(value != nil, "\(message) — ได้ nil", line: line)
        return value
    }

    func isNil<T>(_ value: T?, _ message: String, line: Int = #line) {
        expect(value == nil, "\(message) — ควรเป็น nil แต่ได้ \(String(describing: value))", line: line)
    }

    func throwsError(_ message: String, line: Int = #line, _ body: () throws -> Void) {
        do {
            try body()
            expect(false, "\(message) — ควร throw แต่ไม่ throw", line: line)
        } catch {
            passed += 1
        }
    }

    func throwsError(_ message: String, line: Int = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            expect(false, "\(message) — ควร throw แต่ไม่ throw", line: line)
        } catch {
            passed += 1
        }
    }

    /// ตรวจว่า throw แล้วได้ UsageError ตัวที่ต้องการ
    func throwsUsageError(_ expected: UsageErrorMatcher, _ message: String,
                          line: Int = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            expect(false, "\(message) — ควร throw แต่ไม่ throw", line: line)
        } catch {
            expect(expected.matches(error), "\(message) — ได้ error: \(error)", line: line)
        }
    }

    func summary() -> Never {
        print("\n" + String(repeating: "─", count: 52))
        if failures.isEmpty {
            print("✅ ผ่านทั้งหมด \(passed) ข้อ")
            exit(0)
        }
        print("❌ พัง \(failures.count) ข้อ (ผ่าน \(passed) ข้อ)")
        failures.forEach { print($0) }
        exit(1)
    }
}

enum UsageErrorMatcher {
    case timedOut
    case scriptNotFound(path: String)
    case invalidOutput(contains: [String])

    func matches(_ error: Error) -> Bool {
        guard let usage = error as? UsageError else { return false }
        switch (self, usage) {
        case (.timedOut, .timedOut):
            return true
        case (.scriptNotFound(let want), .scriptNotFound(let tried)):
            return tried == [want]
        case (.invalidOutput(let needles), .invalidOutput(let detail)):
            return needles.allSatisfy { detail.contains($0) }
        default:
            return false
        }
    }
}
