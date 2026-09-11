import AppKit
import Foundation
import HarborCore
import Observation
import SwiftData

@MainActor @Observable final class AppModel {
    let coordinator: DownloadCoordinator
    let updater: EngineUpdater
    private let container: ModelContainer
    private let preferences: UserDefaults
    var jobs: [DownloadJob] = []
    var errorMessage: String?
    var isReady = false
    var showAdd = false
    var initialLink = ""
    var clipboardLink: String?
    var engineVersion = "Bundled"
    var updateStatus = ""
    var checkingUpdate = false
    var clipboardEnabled: Bool { didSet { preferences.set(clipboardEnabled, forKey: "clipboardEnabled") } }
    var automaticUpdates: Bool { didSet { preferences.set(automaticUpdates, forKey: "automaticUpdates") } }
    var destination: URL { didSet { preferences.set(destination.path, forKey: "destination") } }
    var connections: Int { didSet { preferences.set(connections, forKey: "connections") } }
    var defaultPreset: FormatPreset { didSet { preferences.set(defaultPreset.rawValue, forKey: "preset") } }
    private var lastClipboardChange = -1
    private var dismissedClipboard: String?
    private var watcher: Task<Void, Never>?
    private let channelConfigured: Bool

    init() throws {
        #if DEBUG
        let testRoot = ProcessInfo.processInfo.environment["HARBOR_UI_TEST_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        #else
        let testRoot: URL? = nil
        #endif
        let defaults = testRoot.flatMap { UserDefaults(suiteName: "com.harborapp.Harbor.UITests." + $0.lastPathComponent) } ?? .standard
        preferences = defaults
        defaults.register(defaults: ["automaticUpdates": true, "clipboardEnabled": false, "connections": 4])
        clipboardEnabled = defaults.bool(forKey: "clipboardEnabled")
        automaticUpdates = defaults.bool(forKey: "automaticUpdates")
        connections = min(16, max(1, defaults.integer(forKey: "connections")))
        defaultPreset = FormatPreset(rawValue: defaults.string(forKey: "preset") ?? "") ?? .highest
        destination = defaults.string(forKey: "destination").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? testRoot ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let support = testRoot?.appendingPathComponent("Support") ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Harbor", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        container = try ModelContainer(for: JobRecord.self, configurations: ModelConfiguration(url: support.appendingPathComponent("Downloads.store")))
        let root = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let manifestData = try Data(contentsOf: root.appendingPathComponent("Resources/engine-set.json"))
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        let bundled = EngineSet(version: manifest?["version"] as? String ?? "bundled", root: root)
        let channelURL = try Self.requiredResource("EngineChannel", ext: "json")
        let channel = try JSONDecoder().decode(EngineChannel.self, from: Data(contentsOf: channelURL))
        channelConfigured = channel.isConfigured
        updater = EngineUpdater(channel: channel, support: support, bundled: bundled)
        coordinator = DownloadCoordinator(repository: PersistentJobStore(modelContainer: container), engines: bundled)
        engineVersion = bundled.version
        updateStatus = channelConfigured ? "Ready to check for updates" : "Bundled engines are ready. Automatic updates are not configured for this development build."
    }
    private static func requiredResource(_ name: String, ext: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { throw DownloadFailure(.engine, "A required app resource is missing. Rebuild or reinstall Harbor.") }
        return url
    }
    func start() async {
        do {
            let set = await updater.current()
            await coordinator.activate(set); engineVersion = set.version
            try await coordinator.start()
            isReady = true
            watcher = Task {
                for await values in await coordinator.snapshots() {
                    if Task.isCancelled { break }
                    self.jobs = values
                }
            }
            if automaticUpdates && channelConfigured { await checkUpdates(force: false) }
        } catch { errorMessage = "Download history could not be opened. Your existing data has been preserved. " + error.localizedDescription }
    }
    func checkUpdates(force: Bool = true) async {
        guard !checkingUpdate else { return }
        checkingUpdate = true
        defer { checkingUpdate = false }
        do {
            if let set = try await updater.check(force: force) {
                await coordinator.activate(set); engineVersion = set.version
                updateStatus = "Engines updated. Active downloads will finish with their original version."
            } else { updateStatus = "Your engines are up to date." }
        } catch { updateStatus = error.localizedDescription }
    }
    func rollback() async {
        do {
            let set = try await updater.rollback()
            await coordinator.activate(set); engineVersion = set.version
            updateStatus = "Previous engines restored for new downloads."
        } catch { updateStatus = error.localizedDescription }
    }
    func activated() {
        guard clipboardEnabled else { clipboardLink = nil; return }
        let board = NSPasteboard.general
        guard board.changeCount != lastClipboardChange else { return }
        lastClipboardChange = board.changeCount
        guard let text = board.string(forType: .string), text.utf8.count <= 32_000, text != dismissedClipboard,
              let urls = try? LinkRouter().parse(text), !urls.isEmpty else { clipboardLink = nil; return }
        clipboardLink = text
    }
    func dismissClipboard() { dismissedClipboard = clipboardLink; clipboardLink = nil }
    func addClipboard() { initialLink = clipboardLink ?? ""; dismissClipboard(); showAdd = true }
    func addLinks(_ text: String = "") { initialLink = text; showAdd = true }
    func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "Choose Folder"; panel.directoryURL = destination
        return panel.runModal() == .OK ? panel.url : nil
    }
    func cancel(_ job: DownloadJob) { Task { do { try await coordinator.cancel(job.id) } catch { errorMessage = error.localizedDescription } } }
    func retry(_ job: DownloadJob, consent: BrowserConsent? = nil, folder: URL? = nil) {
        Task { do { try await coordinator.retry(job.id, consent: consent, destination: folder) } catch { errorMessage = error.localizedDescription } }
    }
    func remove(_ job: DownloadJob) { Task { do { try await coordinator.remove(job.id) } catch { errorMessage = error.localizedDescription } } }
    func reveal(_ job: DownloadJob) { if let output = job.output { NSWorkspace.shared.activateFileViewerSelecting([output]) } }
    func shutdown() async { watcher?.cancel(); await coordinator.shutdown() }
}
