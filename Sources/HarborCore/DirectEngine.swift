import Foundation
import Darwin
import Security

public struct DirectEngine: DownloadEngine {
    public init() {}
    public func inspect(_ url: URL, engines: EngineSet, consent: BrowserConsent?) async throws -> Inspection {
        let (_, title) = try await LinkRouter().route(url)
        return Inspection(kind: .file, title: title, items: [MediaItem(id: url.absoluteString, url: url, title: title)])
    }
    public func download(_ job: DownloadJob, engines: EngineSet, consent: BrowserConsent?, event: @escaping @Sendable (DownloadEvent) async -> Void) async throws -> URL {
        try FileSafety.prepare(job)
        let filename = FileSafety.filename(job.title)
        let output = job.stagingDirectory.appendingPathComponent(filename)
        let validatorURL = job.stagingDirectory.appendingPathComponent(".validator.json")
        let headers = try await LinkRouter().probe(job.source)
        guard headers.statusCode < 400 else { throw DownloadFailure.classify("HTTP \(headers.statusCode)") }
        let etag = headers.value(forHTTPHeaderField: "ETag")
        let validator = etag.flatMap { $0.hasPrefix("W/") ? nil : $0 }
        let previous = try? String(contentsOf: validatorURL, encoding: .utf8)
        let resumable = validator != nil && previous == validator && headers.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes"
        if !resumable {
            for file in [output, URL(fileURLWithPath: output.path + ".aria2")] where FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        }
        if let validator { try validator.write(to: validatorURL, atomically: true, encoding: .utf8) }
        let port = try Self.availablePort()
        var secretBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, secretBytes.count, &secretBytes) == errSecSuccess else { throw DownloadFailure(.engine, "Could not initialize the transfer service.") }
        let secret = Data(secretBytes).base64EncodedString()
        let rpc = AriaRPC(port: port, secret: secret)
        let executable = try engines.executable("aria2c")
        let args = ["--no-conf", "--enable-rpc=true", "--rpc-listen-all=false", "--rpc-allow-origin-all=false", "--rpc-listen-port=\(port)", "--rpc-secret=\(secret)", "--rpc-max-request-size=1M", "--disable-ipv6=true", "--max-concurrent-downloads=1", "--enable-dht=false", "--enable-dht6=false", "--enable-peer-exchange=false", "--file-allocation=none", "--auto-save-interval=1", "--summary-interval=0", "--console-log-level=error", "--check-certificate=true", "--stop-with-process=\(getpid())"]
        let process = Task { try await ProcessRunner().run(executable: executable, arguments: args) }
        defer { process.cancel() }
        return try await withTaskCancellationHandler {
            var ready = false
            for _ in 0..<60 {
                try Task.checkCancellation()
                do { _ = try await rpc.call("getVersion"); ready = true; break }
                catch { try await Task.sleep(for: .milliseconds(100)) }
            }
            guard ready else { throw DownloadFailure(.engine, "The file transfer service could not start.") }
            var options: [String: String] = ["dir": job.stagingDirectory.path, "out": filename, "continue": resumable ? "true" : "false", "max-connection-per-server": String(min(max(job.connections, 1), 16)), "split": String(min(max(job.connections, 1), 16)), "min-split-size": "5M", "max-tries": "1", "timeout": "30", "connect-timeout": "20", "auto-file-renaming": "false", "allow-overwrite": "false", "check-certificate": "true"]
            if resumable, let validator { options["header"] = "If-Range: \(validator)" }
            guard let gid = try await rpc.call("addUri", params: [[job.source.absoluteString], options]).string else { throw DownloadFailure(.engine, "The transfer service returned an invalid job identifier.") }
            while true {
                try Task.checkCancellation()
                let response = try await rpc.call("tellStatus", params: [gid, ["status", "totalLength", "completedLength", "downloadSpeed", "errorCode"]])
                let status = response.dictionary ?? [:]
                let bytes = Int64(status["completedLength"] ?? "0") ?? 0
                let total = Int64(status["totalLength"] ?? "0") ?? 0
                await event(.progress(bytes: bytes, total: total > 0 ? total : nil, speed: Double(status["downloadSpeed"] ?? "0")))
                if status["status"] == "complete" {
                    _ = try? await rpc.call("shutdown")
                    _ = try? await process.value
                    try Task.checkCancellation()
                    try FileSafety.validate(output, inside: job.stagingDirectory)
                    return output
                }
                if status["status"] == "error" || status["status"] == "removed" {
                    switch status["errorCode"] {
                    case "2", "5", "6", "7", "19", "29": throw DownloadFailure(.network, "The file transfer was interrupted. Retry when the server is available.")
                    case "9": throw DownloadFailure(.destination, "There is not enough space in the destination folder.")
                    case "3": throw DownloadFailure(.unsupported, "This file could not be found on the server.")
                    case "24": throw DownloadFailure(.authentication, "This file requires authentication. Direct-file browser authentication is not supported yet.")
                    default: throw DownloadFailure(.engine, "The file server could not complete this transfer.")
                    }
                }
                try await Task.sleep(for: .milliseconds(300))
            }
        } onCancel: { process.cancel() }
    }
    private static func availablePort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw DownloadFailure(.engine, "Could not create the local transfer connection.") }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { throw DownloadFailure(.engine, "Could not reserve a local transfer port.") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        return UInt16(bigEndian: address.sin_port)
    }
}

private struct RPCValue: Sendable { var string: String?; var dictionary: [String: String]? }
private struct AriaRPC: Sendable {
    let port: UInt16
    let secret: String
    // Heterogeneous JSON is created and consumed entirely within this method.
    func call(_ method: String, params: [Any] = []) async throws -> RPCValue {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": UUID().uuidString, "method": "aria2." + method, "params": ["token:" + secret] + params]
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/jsonrpc")!)
        request.httpMethod = "POST"; request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] == nil else { throw DownloadFailure(.engine, "The transfer service returned an error.") }
        return RPCValue(string: object["result"] as? String, dictionary: object["result"] as? [String: String])
    }
}
