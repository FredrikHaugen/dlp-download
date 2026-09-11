import CryptoKit
import Foundation

public struct EngineChannel: Codable, Sendable {
    public var manifestURL: String
    public var publicKey: String
    public var teamID: String
    public var appBuild: Int
    public var isConfigured: Bool { URL(string: manifestURL)?.scheme == "https" && Data(base64Encoded: publicKey)?.count == 32 && !teamID.isEmpty }
}
public struct EngineManifest: Codable, Sendable {
    public var version: String
    public var sequence: Int
    public var architecture: String
    public var minimumAppBuild: Int
    public var url: URL
    public var sha256: String
    public var size: Int64
}
public struct SignedEngineManifest: Codable, Sendable {
    public var payload: String
    public var signature: String
    public func verified(key: Data, appBuild: Int, architecture: String) throws -> EngineManifest {
        guard let data = Data(base64Encoded: payload), let signature = Data(base64Encoded: signature),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key), publicKey.isValidSignature(signature, for: data) else {
            throw DownloadFailure(.integrity, "The engine update signature is invalid. Your existing engines are unchanged.")
        }
        let manifest = try JSONDecoder().decode(EngineManifest.self, from: data)
        guard manifest.architecture == architecture, manifest.minimumAppBuild <= appBuild,
              manifest.url.scheme == "https", manifest.url.user == nil, manifest.url.password == nil,
              manifest.version.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$", options: .regularExpression) != nil,
              manifest.sequence > 0, manifest.size > 0, manifest.size <= 1_500_000_000,
              manifest.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw DownloadFailure(.integrity, "This engine update is incompatible with your app or Mac.")
        }
        return manifest
    }
}

public actor EngineUpdater {
    public static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
    private let channel: EngineChannel
    private let support: URL
    private let bundled: EngineSet
    private let runner = ProcessRunner()
    private var checking = false
    private struct Activation: Codable { var active: String; var previous: String?; var sequence: Int }
    public init(channel: EngineChannel, support: URL, bundled: EngineSet) { self.channel = channel; self.support = support; self.bundled = bundled }
    private var activationURL: URL { support.appendingPathComponent("engines/active.json") }
    private func activation() -> Activation? { (try? Data(contentsOf: activationURL)).flatMap { try? JSONDecoder().decode(Activation.self, from: $0) } }
    private func installed(_ version: String) -> EngineSet { EngineSet(version: version, root: support.appendingPathComponent("engines/" + version)) }

    public func current() async -> EngineSet {
        guard channel.isConfigured, let state = activation() else { return bundled }
        for version in [state.active, state.previous].compactMap({ $0 }) {
            let set = installed(version)
            if (try? await verifyInstallation(set)) != nil { return set }
        }
        return bundled
    }
    public func check(force: Bool = false) async throws -> EngineSet? {
        guard channel.isConfigured else { throw DownloadFailure(.engine, "Automatic updates become available when the publisher configures a signed release channel. Bundled engines are ready to use.") }
        guard !checking else { return nil }
        checking = true; defer { checking = false }
        let timestamp = support.appendingPathComponent("engines/last-check")
        let last = (try? String(contentsOf: timestamp, encoding: .utf8)).flatMap(Double.init) ?? 0
        guard force || Date.now.timeIntervalSince1970 - last >= 86_400 else { return nil }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: channel.manifestURL)!)
        request.timeoutInterval = 30
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.scheme == "https" else { throw DownloadFailure(.network, "The engine release channel is unavailable.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 64_000 else { throw DownloadFailure(.integrity, "The engine manifest is too large.") }
            data.append(byte)
        }
        let envelope = try JSONDecoder().decode(SignedEngineManifest.self, from: data)
        let manifest = try envelope.verified(key: Data(base64Encoded: channel.publicKey)!, appBuild: channel.appBuild, architecture: Self.architecture)
        try FileManager.default.createDirectory(at: timestamp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try String(Date.now.timeIntervalSince1970).write(to: timestamp, atomically: true, encoding: .utf8)
        let prior = activation()
        guard manifest.sequence > (prior?.sequence ?? 0) else { return nil }
        let destination = installed(manifest.version)
        guard !FileManager.default.fileExists(atPath: destination.root.path) else { throw DownloadFailure(.integrity, "This engine version has already been staged. The installed version is unchanged.") }
        let stage = support.appendingPathComponent("engines/.staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        let archive = stage.appendingPathComponent("engines.zip")
        let (temporary, artifactResponse) = try await session.download(from: manifest.url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let artifactHTTP = artifactResponse as? HTTPURLResponse, artifactHTTP.statusCode == 200, artifactHTTP.url?.scheme == "https",
              try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(manifest.size), try Self.sha256(temporary) == manifest.sha256 else {
            throw DownloadFailure(.integrity, "The engine download failed verification. Your installed engines are unchanged.")
        }
        try FileManager.default.moveItem(at: temporary, to: archive)
        let listing = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-Z1", archive.path], timeout: 20)
        guard listing.status == 0 else { throw DownloadFailure(.integrity, "The engine archive is invalid.") }
        for path in listing.stdout.split(separator: "\n") {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), ["MacOS", "Frameworks", "Resources"].contains(String(path.split(separator: "/").first ?? "")) else {
                throw DownloadFailure(.integrity, "The engine archive contains unexpected paths.")
            }
        }
        let contents = stage.appendingPathComponent("unpacked")
        let extraction = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", archive.path, contents.path], timeout: 120)
        guard extraction.status == 0 else { throw DownloadFailure(.integrity, "The engine archive could not be unpacked.") }
        let candidate = EngineSet(version: manifest.version, root: contents)
        try await verifyInstallation(candidate)
        try await smokeTest(candidate)
        try data.write(to: contents.appendingPathComponent("Resources/signed-manifest.json"), options: .atomic)
        try FileManager.default.moveItem(at: contents, to: destination.root)
        let newState = Activation(active: manifest.version, previous: prior?.active, sequence: manifest.sequence)
        try JSONEncoder().encode(newState).write(to: activationURL, options: .atomic)
        return destination
    }
    public func rollback() async throws -> EngineSet {
        guard var state = activation() else { return bundled }
        guard let previous = state.previous else { return bundled }
        let set = installed(previous)
        try await verifyInstallation(set)
        state.previous = state.active; state.active = previous
        try JSONEncoder().encode(state).write(to: activationURL, options: .atomic)
        return set
    }
    private func verifyInstallation(_ set: EngineSet) async throws {
        guard set.root.lastPathComponent != "..", set.root.standardizedFileURL.path.hasPrefix(support.standardizedFileURL.path + "/") else { throw DownloadFailure(.integrity, "Invalid engine installation path.") }
        guard let enumerator = FileManager.default.enumerator(at: set.root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]) else { throw DownloadFailure(.integrity, "The engine installation is missing.") }
        let paths = enumerator.compactMap { $0 as? URL }
        for file in paths {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true else { throw DownloadFailure(.integrity, "The engine installation contains unexpected links.") }
            if values.isRegularFile == true && (file.path.contains("/MacOS/") || file.path.contains("/Frameworks/")) {
                let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(channel.teamID)\""
                let check = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--verify", "--strict", "-R=" + requirement, file.path], timeout: 20)
                guard check.status == 0 else { throw DownloadFailure(.integrity, "An engine component has an invalid code signature.") }
            }
        }
        for name in ["yt-dlp", "ffmpeg", "ffprobe", "aria2c", "deno"] { _ = try set.executable(name) }
    }
    private func smokeTest(_ set: EngineSet) async throws {
        for name in ["yt-dlp", "ffmpeg", "ffprobe", "aria2c", "deno"] {
            let result = try await runner.run(executable: set.executable(name), arguments: [name.hasPrefix("ff") ? "-version" : "--version"], timeout: 30)
            guard result.status == 0 else { throw DownloadFailure(.integrity, "The updated engines failed their startup checks.") }
        }
    }
    public static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
