import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

/// Owns the small synchronous Foundation surface behind a lock. Pipe reads run
/// on dedicated queues, never on Swift's cooperative executor or the UI thread.
private final class ProcessLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func start(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.process = process
        try process.run()
    }
    func stop() {
        lock.lock(); cancelled = true
        let process = self.process
        guard let process, process.isRunning else { lock.unlock(); return }
        let pid = process.processIdentifier
        lock.unlock()
        let descendants = Self.children(of: pid).compactMap { child -> (pid_t, UInt64)? in
            Self.identity(child).map { (child, $0) }
        }
        for (child, _) in descendants.reversed() { kill(child, SIGTERM) }
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            // Do not kill a recycled parent PID after Foundation reaps it.
            if process.isRunning { kill(pid, SIGKILL) }
            for (child, start) in descendants {
                // Start time protects against PID reuse even after an orphan is reparented.
                if Self.identity(child) == start { kill(child, SIGKILL) }
            }
        }
    }
    private static func identity(_ pid: pid_t) -> UInt64? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == MemoryLayout<proc_bsdinfo>.size else { return nil }
        return info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }
    private static func children(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 4096)
        let size = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard size > 0 else { return [] }
        let direct = Array(buffer.prefix(Int(size) / MemoryLayout<pid_t>.size)).filter { $0 > 0 }
        return direct + direct.flatMap { children(of: $0) }
    }
}

public struct ProcessRunner: Sendable {
    public init() {}
    public func run(executable: URL, arguments: [String], directory: URL? = nil, timeout: Double = 0,
                    line: (@Sendable (String) async -> Void)? = nil) async throws -> ProcessResult {
        let lifetime = ProcessLifetime()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8", "PYTHONNOUSERSITE": "1"]
            let out = Pipe(), err = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = out; process.standardError = err
            let termination = AsyncStream<Int32> { continuation in
                process.terminationHandler = { p in continuation.yield(p.terminationStatus); continuation.finish() }
            }
            let lines = AsyncStream<String>(bufferingPolicy: .bufferingNewest(2048)) { continuation in
                // Both pipes are read before waiting for process exit.
                DispatchQueue.global(qos: .utility).async {
                    Self.readLines(out.fileHandleForReading, limit: 16_000_000) { continuation.yield($0) }
                    continuation.finish()
                }
            }
            let stderrTask = Task.detached(priority: .utility) {
                await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                    DispatchQueue.global(qos: .utility).async {
                        var text = ""
                        Self.readLines(err.fileHandleForReading, limit: 1_000_000) {
                            text += $0 + "\n"
                            if text.utf8.count > 65_536 { text = String(text.suffix(32_768)) }
                        }
                        continuation.resume(returning: text)
                    }
                }
            }
            do { try lifetime.start(process) }
            catch {
                try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
                throw error
            }
            try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
            let timer = timeout > 0 ? Task {
                try? await Task.sleep(for: .seconds(timeout))
                if !Task.isCancelled { lifetime.stop() }
            } : nil
            defer { timer?.cancel() }
            var stdout = ""
            for await value in lines {
                if line == nil {
                    stdout += value + "\n"
                    if stdout.utf8.count > 16_000_000 { lifetime.stop(); throw DownloadFailure(.engine, "The source returned too much metadata. Try a smaller playlist.") }
                }
                await line?(value)
            }
            var status: Int32 = -1
            for await value in termination { status = value }
            let stderr = await stderrTask.value
            try Task.checkCancellation()
            return ProcessResult(status: status, stdout: stdout, stderr: stderr)
        } onCancel: { lifetime.stop() }
    }

    private static func readLines(_ handle: FileHandle, limit: Int, receive: (String) -> Void) {
        defer { try? handle.close() }
        var pending = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                receive(String(decoding: pending[..<newline], as: UTF8.self).trimmingCharacters(in: .newlines))
                pending.removeSubrange(...newline)
            }
            if pending.count > limit { receive(String(decoding: pending, as: UTF8.self)); pending.removeAll(keepingCapacity: true) }
        }
        if !pending.isEmpty { receive(String(decoding: pending, as: UTF8.self)) }
    }
}
