import Foundation
import Testing
@testable import HarborCore

private var fixtureBase: URL? { ProcessInfo.processInfo.environment["HARBOR_FIXTURE_URL"].flatMap(URL.init(string:)) }
private var engineRoot: URL? { ProcessInfo.processInfo.environment["HARBOR_ENGINE_ROOT"].map { URL(fileURLWithPath: $0) } }

@Test(.enabled(if: fixtureBase != nil && engineRoot != nil)) func realPlaylistInspectionKeepsIndividualSourceURLs() async throws {
    let base = try #require(fixtureBase)
    let root = try #require(engineRoot)
    let result = try await MediaEngine().inspect(base.appendingPathComponent("playlist"), engines: EngineSet(version: "test", root: root), consent: nil)
    #expect(result.isPlaylist)
    #expect(result.items.count == 2)
    #expect(result.items.allSatisfy { $0.available })
    #expect(Set(result.items.map(\.url)).count == 2)
    #expect(result.items.allSatisfy { $0.url.path == "/sample.mp4" })
    #expect(result.items.map(\.playlistIndex) == [1, 2])
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let item = result.items[1]
    var job = DownloadJob(source: try #require(item.extractionSource), title: item.title, kind: .media, preset: .highest, destination: folder)
    job.playlistIndex = item.playlistIndex
    let output = try await MediaEngine().download(job, engines: EngineSet(version: "test", root: root), consent: nil) { _ in }
    try FileSafety.validate(output, inside: job.stagingDirectory)
}

@Test(.enabled(if: fixtureBase != nil)) func responseBasedRouting() async throws {
    let base = try #require(fixtureBase)
    let router = LinkRouter()
    #expect(try await router.route(base.appendingPathComponent("file")).0 == .file)
    #expect(try await router.route(base.appendingPathComponent("misleading.mp4")).0 == .media)
    #expect(try await router.route(base.appendingPathComponent("redirect")).0 == .file)
    #expect(try await router.route(base.appendingPathComponent("head-denied")).0 == .file)
    #expect(try await router.route(base.appendingPathComponent("torrent")).0 == .torrent)
}
@Test(.enabled(if: fixtureBase != nil && engineRoot != nil)) func realDirectTransferMatchesFixture() async throws {
    let base = try #require(fixtureBase)
    let root = try #require(engineRoot)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for route in ["file", "no-range", "redirect"] {
        let job = DownloadJob(source: base.appendingPathComponent(route), title: "fixture.bin", kind: .file, preset: .highest, destination: folder)
        let output = try await DirectEngine().download(job, engines: EngineSet(version: "fixture", root: root), consent: nil) { _ in }
        let data = try Data(contentsOf: output)
        #expect(data.count == 8_388_608)
        #expect(data.prefix(256) == Data((0...255).map(UInt8.init)))
        let final = try FileSafety.finish(output, job: job)
        #expect(FileManager.default.fileExists(atPath: final.path))
    }
}
@Test(.enabled(if: fixtureBase != nil && engineRoot != nil)) func realMediaPresetsProduceValidFiles() async throws {
    let base = try #require(fixtureBase)
    let root = try #require(engineRoot)
    let engines = EngineSet(version: "fixture", root: root)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let engine = MediaEngine()
    let inspection = try await engine.inspect(base.appendingPathComponent("page"), engines: engines, consent: nil)
    #expect(!inspection.items.isEmpty)
    for preset in FormatPreset.allCases {
        let job = DownloadJob(source: base.appendingPathComponent("page"), title: "Harbor fixture", kind: .media, preset: preset, destination: folder)
        let output = try await engine.download(job, engines: engines, consent: nil) { _ in }
        try FileSafety.validate(output, inside: job.stagingDirectory)
        let result = try await ProcessRunner().run(executable: engines.executable("ffprobe"), arguments: ["-v", "error", "-show_streams", "-of", "json", output.path])
        #expect(result.status == 0)
        let info = try #require(try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        let streams = try #require(info["streams"] as? [[String: Any]])
        #expect(streams.contains { $0["codec_type"] as? String == "audio" })
        if preset == .mobile {
            #expect(output.pathExtension == "mp4")
            #expect(streams.contains { $0["codec_name"] as? String == "h264" })
            #expect(streams.contains { $0["codec_name"] as? String == "aac" })
        }
        if preset == .m4a || preset == .mp3 { #expect(!streams.contains { $0["codec_type"] as? String == "video" }) }
    }
}
@Test(.enabled(if: fixtureBase != nil && engineRoot != nil)) func directCancellationRetainsPartialAndCanResume() async throws {
    let base = try #require(fixtureBase)
    let root = try #require(engineRoot)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let job = DownloadJob(source: base.appendingPathComponent("slow"), title: "slow.bin", kind: .file, preset: .highest, destination: folder)
    let engine = DirectEngine(), engines = EngineSet(version: "fixture", root: root)
    let task = Task { try await engine.download(job, engines: engines, consent: nil) { _ in } }
    try await Task.sleep(for: .seconds(1)); task.cancel()
    do { _ = try await task.value; Issue.record("Expected cancellation") } catch {}
    let output = try await engine.download(job, engines: engines, consent: nil) { _ in }
    #expect(try Data(contentsOf: output).count == 8_388_608)
}
