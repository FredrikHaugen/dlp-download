import CryptoKit
import Foundation
import Testing
@testable import HarborCore

private actor FixtureEngine: DownloadEngine {
    var active = 0
    var maximum = 0
    var calls: [UUID: Int] = [:]
    func inspect(_ url: URL, engines: EngineSet, consent: BrowserConsent?) async throws -> Inspection {
        Inspection(kind: .file, title: "Fixture", items: [])
    }
    func download(_ job: DownloadJob, engines: EngineSet, consent: BrowserConsent?, event: @escaping @Sendable (DownloadEvent) async -> Void) async throws -> URL {
        active += 1; maximum = max(active, maximum); calls[job.id, default: 0] += 1
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(job.title == "slow" ? 500 : 80))
        if job.title == "unavailable" { throw DownloadFailure(.unsupported, "Unavailable fixture") }
        if job.title == "retry" && calls[job.id] == 1 { throw DownloadFailure(.network, "Interrupted fixture") }
        try FileSafety.prepare(job)
        let path = job.stagingDirectory.appendingPathComponent("fixture.bin")
        try Data([1, 2, 3, 4]).write(to: path)
        await event(.progress(bytes: 4, total: 4, speed: nil))
        return path
    }
}
private func waitFor(_ store: MemoryJobStore, count: Int) async throws -> [DownloadJob] {
    for _ in 0..<300 {
        let jobs = await store.load()
        if jobs.count == count && jobs.allSatisfy({ !$0.state.isActive && $0.state != .queued }) { return jobs }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Queue did not settle within six seconds")
    return await store.load()
}
@Test func queueCapsConcurrencyAndIsolatesPlaylistFailures() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = MemoryJobStore(), engine = FixtureEngine()
    let coordinator = DownloadCoordinator(repository: store, engines: EngineSet(version: "pinned-one", root: folder), media: engine, direct: engine)
    try await coordinator.start()
    let group = UUID()
    let jobs = (0..<8).map { DownloadJob(source: URL(string: "https://example.com/\($0)")!, title: $0 == 3 ? "unavailable" : "Item \($0)", kind: .media, preset: .highest, destination: folder, groupID: group) }
    try await coordinator.enqueue(jobs)
    let finished = try await waitFor(store, count: 8)
    #expect(finished.filter { $0.state == .completed }.count == 7)
    #expect(finished.filter { $0.state == .failed }.count == 1)
    #expect(await engine.maximum <= 3)
    #expect(finished.allSatisfy { $0.engineVersion == "pinned-one" })
    let complete = try #require(finished.first { $0.state == .completed })
    try await coordinator.remove(complete.id)
    #expect(FileManager.default.fileExists(atPath: try #require(complete.output).path))
    await coordinator.shutdown()
}
@Test func transientFailureRetriesButUnsupportedDoesNot() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = MemoryJobStore(), engine = FixtureEngine()
    let coordinator = DownloadCoordinator(repository: store, engines: EngineSet(version: "test", root: folder), media: engine, direct: engine)
    let retry = DownloadJob(source: URL(string: "https://example.com/retry")!, title: "retry", kind: .file, preset: .highest, destination: folder)
    let unavailable = DownloadJob(source: retry.source, title: "unavailable", kind: .file, preset: .highest, destination: folder)
    try await coordinator.enqueue([retry, unavailable])
    let finished = try await waitFor(store, count: 2)
    #expect(finished.first { $0.id == retry.id }?.state == .completed)
    #expect(await engine.calls[retry.id] == 2)
    #expect(await engine.calls[unavailable.id] == 1)
    await coordinator.shutdown()
}
@Test func shutdownLeavesRecoverableJobs() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = MemoryJobStore(), engine = FixtureEngine()
    let coordinator = DownloadCoordinator(repository: store, engines: EngineSet(version: "test", root: folder), media: engine, direct: engine)
    try await coordinator.enqueue((0..<5).map { _ in DownloadJob(source: URL(string: "https://example.com/slow")!, title: "slow", kind: .file, preset: .highest, destination: folder) })
    try await Task.sleep(for: .milliseconds(80))
    await coordinator.shutdown()
    #expect(await store.load().allSatisfy { $0.state == .interrupted })
    #expect(await engine.active == 0)
}
@Test func signedManifestRejectsTamperingAndIncompatibleBuilds() throws {
    let key = Curve25519.Signing.PrivateKey()
    let value = EngineManifest(version: "2026.07.04-2", sequence: 2, architecture: "arm64", minimumAppBuild: 1, url: URL(string: "https://example.com/engines.zip")!, sha256: String(repeating: "a", count: 64), size: 100)
    let data = try JSONEncoder().encode(value)
    var envelope = SignedEngineManifest(payload: data.base64EncodedString(), signature: try key.signature(for: data).base64EncodedString())
    #expect(try envelope.verified(key: key.publicKey.rawRepresentation, appBuild: 1, architecture: "arm64").sequence == 2)
    #expect(throws: DownloadFailure.self) { try envelope.verified(key: key.publicKey.rawRepresentation, appBuild: 0, architecture: "arm64") }
    #expect(throws: DownloadFailure.self) { try envelope.verified(key: key.publicKey.rawRepresentation, appBuild: 1, architecture: "x86_64") }
    #expect(throws: DownloadFailure.self) { try envelope.verified(key: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation, appBuild: 1, architecture: "arm64") }
    envelope.payload = Data("tampered".utf8).base64EncodedString()
    #expect(throws: DownloadFailure.self) { try envelope.verified(key: key.publicKey.rawRepresentation, appBuild: 1, architecture: "arm64") }
}
@Test func signedManifestStillRejectsUnsafePathsAndInsecureURLs() throws {
    let key = Curve25519.Signing.PrivateKey()
    for (version, url) in [("../escape", "https://example.com/a"), ("valid", "http://example.com/a")] {
        let value = EngineManifest(version: version, sequence: 1, architecture: "arm64", minimumAppBuild: 1, url: URL(string: url)!, sha256: String(repeating: "a", count: 64), size: 100)
        let data = try JSONEncoder().encode(value)
        let envelope = SignedEngineManifest(payload: data.base64EncodedString(), signature: try key.signature(for: data).base64EncodedString())
        #expect(throws: DownloadFailure.self) { try envelope.verified(key: key.publicKey.rawRepresentation, appBuild: 1, architecture: "arm64") }
    }
}
@Test func binaryHashDetectsChangedBytes() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("before".utf8).write(to: file)
    let first = try EngineUpdater.sha256(file)
    try Data("after".utf8).write(to: file)
    #expect(try EngineUpdater.sha256(file) != first)
}
@Test func rejectsLiveStreamsDuringInspection() {
    #expect(throws: DownloadFailure.self) { try MediaEngine.decodeInspection(Data(#"{"title":"Live","is_live":true}"#.utf8), source: URL(string: "https://example.com/live")!) }
}
