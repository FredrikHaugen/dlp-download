import Foundation
import SwiftData
import Testing
@testable import HarborCore

@Test func linkParsingRejectsCommandsAndCredentials() throws {
    let router = LinkRouter()
    #expect(throws: DownloadFailure.self) { try router.parse("file:///etc/passwd") }
    #expect(throws: DownloadFailure.self) { try router.parse("https://user:password@example.com/video") }
    #expect(throws: DownloadFailure.self) { try router.parse("--exec bad") }
    #expect(try router.parse("https://example.com/a\nhttps://example.com/a").count == 1)
    #expect(try router.parse("magnet:?xt=urn:btih:abc").first?.scheme == "magnet")
}
@Test func filenameSafety() {
    #expect(FileSafety.filename("../../bad/name") == ".._.._bad_name")
    #expect(FileSafety.filename("..") == "Download")
    #expect(!FileSafety.filename("a\0b").contains("\0"))
}
@Test func progressHandlesMissingAndEstimatedTotals() throws {
    let event = try #require(MediaEngine.progressEvent("HARBOR_PROGRESS {\"downloaded_bytes\":50,\"total_bytes_estimate\":100,\"speed\":20}"))
    guard case let .progress(bytes, total, speed) = event else { Issue.record("Wrong event"); return }
    #expect(bytes == 50); #expect(total == 100); #expect(speed == 20)
    let unknown = try #require(MediaEngine.progressEvent("HARBOR_PROGRESS {\"downloaded_bytes\":2,\"total_bytes\":null}"))
    guard case let .progress(_, unknownTotal, _) = unknown else { return }
    #expect(unknownTotal == nil)
    #expect(MediaEngine.progressEvent("[download] 50%") == nil)
}
@Test func playlistPreservesUnavailableItems() throws {
    let data = Data(#"{"title":"Playlist","playlist_count":1500,"entries":[{"id":"a","title":"One","url":"https://example.com/watch/a"},{"id":"b","title":"[Deleted video]","url":"https://example.com/watch/b"}]}"#.utf8)
    let inspection = try MediaEngine.decodeInspection(data, source: URL(string: "https://example.com/list")!)
    #expect(inspection.isPlaylist); #expect(inspection.truncated)
    #expect(inspection.items.count == 2); #expect(!inspection.items[1].available)
}
@Test func errorsDistinguishLoginFromForbidden() {
    #expect(DownloadFailure.classify("HTTP 403 Forbidden").kind == .restricted)
    #expect(DownloadFailure.classify("Please sign in to confirm your age").kind == .authentication)
    #expect(DownloadFailure.classify("No space left on device").kind == .destination)
    #expect(DownloadFailure.classify("connection timed out").kind == .network)
}
@Test func finalizationNeverOverwritesAndRejectsOutsideFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let job = DownloadJob(source: URL(string: "https://example.com/file")!, title: "File", kind: .file, preset: .highest, destination: folder)
    try FileSafety.prepare(job)
    let source = job.stagingDirectory.appendingPathComponent("file.zip")
    try Data([1, 2, 3]).write(to: source)
    let existing = folder.appendingPathComponent("file.zip")
    try Data([9]).write(to: existing)
    let result = try FileSafety.finish(source, job: job)
    #expect(result.lastPathComponent == "file (2).zip")
    #expect(try Data(contentsOf: existing) == Data([9]))
    #expect(throws: (any Error).self) { try FileSafety.validate(existing, inside: job.stagingDirectory) }
}
@Test func processDrainsBothPipesAndKeepsSplitUnicode() async throws {
    let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import os\nfor _ in range(40): os.write(2,b'x'*4096)\nos.write(1,b'hello ' + bytes([0xe2]))\nos.write(1,bytes([0x98,0x83])+b'\\n')"], timeout: 10)
    #expect(result.status == 0); #expect(result.stdout == "hello ☃\n"); #expect(result.stderr.count > 0)
}
@Test func processCancellationReturnsPromptly() async throws {
    let task = Task { try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]) }
    try await Task.sleep(for: .milliseconds(150)); task.cancel()
    do { _ = try await task.value; Issue.record("Cancellation did not throw") } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
}
@Test func restartMarksPendingWorkInterrupted() async throws {
    var first = fixtureJob(); first.state = .downloading
    var second = fixtureJob(); second.state = .completed
    let store = MemoryJobStore([first, second])
    let coordinator = DownloadCoordinator(repository: store, engines: EngineSet(version: "test", root: URL(fileURLWithPath: "/tmp")))
    try await coordinator.start()
    let loaded = await store.load()
    #expect(loaded.first { $0.id == first.id }?.state == .interrupted)
    #expect(loaded.first { $0.id == second.id }?.state == .completed)
}
@Test func swiftDataRoundTrip() async throws {
    let container = try ModelContainer(for: JobRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = PersistentJobStore(modelContainer: container)
    let job = fixtureJob()
    try await store.save(job)
    #expect(try await store.load().first?.id == job.id)
    try await store.remove(job.id)
    #expect(try await store.load().isEmpty)
}
func fixtureJob() -> DownloadJob {
    DownloadJob(source: URL(string: "https://example.com/file")!, title: "Fixture", kind: .file, preset: .highest, destination: FileManager.default.temporaryDirectory)
}
