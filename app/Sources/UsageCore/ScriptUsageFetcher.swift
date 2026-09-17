//
//  ScriptUsageFetcher.swift — รัน `claude-usage.sh --json` แล้วแปลงผลเป็น UsageSnapshot
//
//  ทำไมต้องผ่าน shell script: ตัวสคริปต์จัดการ token discovery / auto-refresh /
//  TTL cache / backoff 429 / log ไว้ครบและผ่านสนามจริงมาแล้ว (ดู CLAUDE.md) — ห้ามเขียนใหม่ใน Swift
//
//  ข้อควรระวังที่โค้ดนี้ต้องกัน:
//   • แอป GUI ได้ env มาน้อยมาก — PATH อาจไม่มี /usr/bin ด้วยซ้ำ ทำให้ python3/curl/security หายหมด
//   • pipe เต็ม/ลูกหลานค้าง → อ่านแบบ readabilityHandler ไม่บล็อกเธรด
//   • timeout ต้อง "ฆ่าโปรเซสจริง" ไม่ใช่แค่เลิกรอ
//

import Foundation
#if canImport(Darwin)
import Darwin
#endif

public protocol UsageFetching {
    func fetch(force: Bool) async throws -> UsageSnapshot
}

public final class ScriptUsageFetcher: UsageFetching, Sendable {

    public let scriptURL: URL
    public let timeout: TimeInterval

    private let queue = DispatchQueue(label: "io.github.panithannanti.ClaudeUsageBar.fetch", qos: .utility)

    /// - Parameters:
    ///   - scriptURL: path เต็มของ `claude-usage.sh`
    ///   - timeout: วินาทีก่อนสั่งหยุดโปรเซส (สคริปต์เองตั้ง curl ไว้ 15 วิ)
    public init(scriptURL: URL, timeout: TimeInterval = 30) {
        self.scriptURL = scriptURL
        self.timeout = timeout
    }

    public func fetch(force: Bool) async throws -> UsageSnapshot {
        let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
            queue.async {
                do { cont.resume(returning: try self.runScript(force: force)) }
                catch { cont.resume(throwing: error) }
            }
        }

        let text = String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let data = text.data(using: .utf8) else {
            throw UsageError.invalidOutput(detail: "สคริปต์ไม่พ่นอะไรเลย (exit \(result.code))"
                                           + detailSuffix(result))
        }
        do {
            return try UsageParser.parse(data)
        } catch {
            throw UsageError.invalidOutput(detail: UsageError.redact(text) + detailSuffix(result))
        }
    }

    /// stdout/stderr ถูก redact ตั้งแต่ตอนสร้าง error — ความลับจะได้ไม่มีทางถูกเก็บไว้เลย
    private func detailSuffix(_ r: ProcessResult) -> String {
        let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return err.isEmpty ? "" : " · stderr: " + UsageError.redact(err)
    }

    // MARK: - process

    private struct ProcessResult {
        let stdout: Data
        let stderr: String
        let code: Int32
    }

    private func runScript(force: Bool) throws -> ProcessResult {
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw UsageError.scriptNotFound(path: scriptURL.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        var arguments = [scriptURL.path, "--json"]
        if force { arguments.append("--force") }
        process.arguments = arguments
        process.environment = childEnvironment()
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let outBox = DataBox(), errBox = DataBox()
        let outEOF = DispatchSemaphore(value: 0), errEOF = DispatchSemaphore(value: 0)
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                outEOF.signal()
            } else {
                outBox.append(chunk)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                errEOF.signal()
            } else {
                errBox.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw UsageError.launchFailed(reason: error.localizedDescription)
        }

        // timeout: SIGTERM ก่อน แล้วตาม SIGKILL ถ้ายังไม่ตาย
        let expired = Flag()
        let killer = DispatchWorkItem {
            // เช็ก isRunning **ก่อน** ตีตรา expired — timeout ที่ยิงพร้อมกับโปรเซสจบพอดี
            // ไม่งั้นจะทิ้ง payload ที่ดีไปเฉยๆ
            guard process.isRunning else { return }
            expired.set()
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        process.waitUntilExit()
        killer.cancel()
        // รอ EOF สั้นๆ ทั้งสองทาง (งบรวม ~2 วิ) เผื่อยังมีข้อมูลค้างใน pipe; ถ้าลูกหลาน (curl)
        // ยังถือ write end อยู่ก็ไม่รอต่อ — bash พ่น JSON จบก่อนตัวเองจบอยู่แล้ว
        let eofDeadline = DispatchTime.now() + 2
        _ = outEOF.wait(timeout: eofDeadline)
        _ = errEOF.wait(timeout: eofDeadline)
        // ⚠️ ห้าม close() เอง — readabilityHandler อาจกำลังทำงานอยู่บนคิวของ FileHandle
        // (close ชนกับ handler = อ่าน fd ที่ถูกปิดไปแล้ว) เคลียร์ handler แล้วปล่อยให้ Pipe ปิดตอน deinit
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        if expired.value { throw UsageError.timedOut(seconds: timeout) }
        return ProcessResult(stdout: outBox.value,
                             stderr: String(decoding: errBox.value, as: UTF8.self),
                             code: process.terminationStatus)
    }

    /// env ของแอป GUI มีน้อยมาก — ต้องเติม PATH ให้สคริปต์เจอ python3/curl/security/pgrep
    private func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let required = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin"]
        var parts = (env["PATH"] ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
        for dir in required where !parts.contains(dir) { parts.append(dir) }
        env["PATH"] = parts.joined(separator: ":")
        if (env["HOME"] ?? "").isEmpty { env["HOME"] = NSHomeDirectory() }
        return env
    }
}

// MARK: - ตัวช่วยเล็กๆ (thread-safe)

private final class DataBox {
    private let lock = NSLock()
    private var storage = Data()
    func append(_ data: Data) {
        lock.lock(); storage.append(data); lock.unlock()
    }
    var value: Data {
        lock.lock(); defer { lock.unlock() }; return storage
    }
}

private final class Flag {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
