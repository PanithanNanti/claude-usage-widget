//
//  ScriptLocator.swift — หา claude-usage.sh ให้เจอ
//
//  ลำดับการค้นหา (ตาม app/PLAN.md):
//    0) env `CLAUDE_USAGE_SCRIPT` ตั้งไว้ (ไม่ว่าง) = **คำสั่ง** — ใช้ path นั้นตัวเดียว
//       ไม่มีไฟล์ก็ error ที่ path นั้น ห้ามแอบตกไปใช้ตัวใน bundle (ไม่งั้นเทสต์/ดีบักหลอกตัวเอง)
//    1) `Bundle.main` → Contents/Resources/claude-usage.sh  (ตอนรันเป็น .app จริง)
//    2) โฟลเดอร์ของไบนารีและโฟลเดอร์แม่ขึ้นไปไม่เกิน 6 ชั้น (ตอน dev: `swift run` จาก app/.build/debug
//       → เจอ claude-usage.sh ที่ราก repo)
//  ไม่เจอเลย → throw `UsageError.scriptNotFound` (ข้อความสั้น; รายการ path เต็มอยู่ใน diagnosticDescription)
//

import Foundation

public enum ScriptLocator {
    public static let scriptName = "claude-usage.sh"

    /// path ที่ env บังคับไว้ — nil = ไม่ได้ตั้ง (หรือตั้งเป็นค่าว่าง)
    public static func envOverride(_ env: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let raw = env["CLAUDE_USAGE_SCRIPT"], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    }

    public static func candidates(bundle: Bundle = .main,
                                  env: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        if let override = envOverride(env) { return [override] }
        var urls: [URL] = []
        if let inBundle = bundle.url(forResource: "claude-usage", withExtension: "sh") {
            urls.append(inBundle)
        }
        urls.append(bundle.bundleURL.appendingPathComponent("Contents/Resources/\(scriptName)"))

        // ไล่ขึ้นจากโฟลเดอร์ของไบนารี (ครอบทั้ง .app/Contents/MacOS และ .build/debug ตอน dev)
        if let exeDir = bundle.executableURL?.deletingLastPathComponent() {
            var dir = exeDir.standardizedFileURL
            for _ in 0..<6 {
                urls.append(dir.appendingPathComponent(scriptName))
                urls.append(dir.appendingPathComponent("Resources/\(scriptName)"))
                let parent = dir.deletingLastPathComponent().standardizedFileURL
                if parent == dir { break }
                dir = parent
            }
        }
        return urls
    }

    public static func find(bundle: Bundle = .main,
                            env: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let tried = candidates(bundle: bundle, env: env)
        for url in tried where FileManager.default.fileExists(atPath: url.path) {
            return url.standardizedFileURL
        }
        throw UsageError.scriptNotFound(tried: tried.map(\.path))
    }
}
