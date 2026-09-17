// swift-tools-version:5.9
//
// ClaudeUsageBar — แอป macOS แสดง Claude plan usage (แทน widget Übersicht)
//
// tools-version 5.9 → ภาษาโหมด Swift 5 โดยปริยาย (เลี่ยง strict-concurrency error
// ของ Swift 6 ที่ไม่จำเป็นกับแอปเล็กๆ ตัวนี้ — ดู app/PLAN.md)
// เครื่องเป้าหมายมีแค่ Command Line Tools → SwiftPM ล้วน ไม่มี dependency ภายนอก
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "ClaudeUsageBar", targets: ["ClaudeUsageBar"]),
    ],
    targets: [
        // logic ล้วน — ห้าม import AppKit/SwiftUI (ต้องทดสอบได้แบบ headless)
        .target(name: "UsageCore"),
        .executableTarget(name: "ClaudeUsageBar", dependencies: ["UsageCore"]),
        // เทสต์: `swift run UsageCoreChecks` (exit ≠ 0 เมื่อพัง)
        // ไม่ใช้ .testTarget เพราะเครื่องนี้มีแค่ Command Line Tools —
        // XCTest ไม่มีเลย ส่วน swift-testing คอมไพล์ผ่านบ้างไม่ผ่านบ้าง
        // (`plugin for module 'TestingMacros' not found` แบบสุ่มตอนบิลด์เย็น)
        .executableTarget(name: "UsageCoreChecks", dependencies: ["UsageCore"]),
    ]
)
