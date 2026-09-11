import Foundation

public enum DownloadKind: String, Codable, Sendable { case media, file, torrent }
public enum DownloadState: String, Codable, CaseIterable, Sendable {
    case queued, inspecting, downloading, processing, interrupted, completed, failed, cancelled
    public var isActive: Bool { [.inspecting, .downloading, .processing].contains(self) }
    public var canRetry: Bool { [.failed, .interrupted, .cancelled].contains(self) }
}
public enum FormatPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case highest, mobile, m4a, mp3
    public var id: String { rawValue }
    public var title: String {
        switch self { case .highest: "Highest Quality"; case .mobile: "Mobile Compatible"; case .m4a: "Audio · M4A"; case .mp3: "Audio · MP3" }
    }
    public var subtitle: String {
        switch self {
        case .highest: "Best available video and audio"
        case .mobile: "1080p or lower · MP4 · H.264 / AAC"
        case .m4a: "Audio only · compact and compatible"
        case .mp3: "Audio only · widely supported"
        }
    }
}
public struct BrowserConsent: Codable, Equatable, Sendable {
    public enum Browser: String, CaseIterable, Codable, Sendable { case safari, chrome, firefox, edge, brave }
    public var browser: Browser
    public var profile: String?
    public init(browser: Browser, profile: String? = nil) { self.browser = browser; self.profile = profile }
    public var argument: String { browser.rawValue + (profile.flatMap { $0.isEmpty ? nil : ":" + $0 } ?? "") }
}
public struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var url: URL
    public var title: String
    public var duration: Double?
    public var thumbnail: URL?
    public var available: Bool
    public var availablePresets: [FormatPreset]?
    public var extractionSource: URL?
    public var playlistIndex: Int?
    public init(id: String, url: URL, title: String, duration: Double? = nil, thumbnail: URL? = nil, available: Bool = true, availablePresets: [FormatPreset]? = nil, extractionSource: URL? = nil, playlistIndex: Int? = nil) {
        self.id = id; self.url = url; self.title = title; self.duration = duration; self.thumbnail = thumbnail; self.available = available; self.availablePresets = availablePresets
        self.extractionSource = extractionSource; self.playlistIndex = playlistIndex
    }
}
public struct Inspection: Sendable {
    public var kind: DownloadKind
    public var title: String
    public var items: [MediaItem]
    public var isPlaylist: Bool
    public var truncated: Bool
    public init(kind: DownloadKind, title: String, items: [MediaItem], isPlaylist: Bool = false, truncated: Bool = false) {
        self.kind = kind; self.title = title; self.items = items; self.isPlaylist = isPlaylist; self.truncated = truncated
    }
}
public struct DownloadJob: Identifiable, Codable, Sendable {
    public var id: UUID
    public var source: URL
    public var title: String
    public var kind: DownloadKind
    public var preset: FormatPreset
    public var destination: URL
    public var groupID: UUID?
    public var groupTitle: String?
    public var playlistIndex: Int?
    public var state: DownloadState = .queued
    public var createdAt: Date = .now
    public var updatedAt: Date = .now
    public var progress: Double?
    public var downloadedBytes: Int64 = 0
    public var totalBytes: Int64?
    public var bytesPerSecond: Double?
    public var status: String = "Waiting"
    public var error: DownloadFailure?
    public var output: URL?
    public var engineVersion: String?
    public var attempts: Int = 0
    public var connections: Int = 4
    public init(id: UUID = UUID(), source: URL, title: String, kind: DownloadKind, preset: FormatPreset, destination: URL, groupID: UUID? = nil, groupTitle: String? = nil) {
        self.id = id; self.source = source; self.title = title; self.kind = kind; self.preset = preset; self.destination = destination; self.groupID = groupID; self.groupTitle = groupTitle
    }
    public var stagingDirectory: URL { destination.appendingPathComponent(".harbor-" + id.uuidString, isDirectory: true) }
}
public struct DownloadFailure: Error, Codable, Equatable, LocalizedError, Sendable {
    public enum Kind: String, Codable, Sendable { case network, authentication, restricted, unsupported, destination, engine, integrity, cancelled }
    public var kind: Kind
    public var message: String
    public var errorDescription: String? { message }
    public init(_ kind: Kind, _ message: String) { self.kind = kind; self.message = message }
    public static func classify(_ diagnostic: String) -> Self {
        let text = diagnostic.lowercased()
        if text.contains("no space left") { return .init(.destination, "There isn’t enough space in the destination. Free up space and retry.") }
        if text.contains("cookies") && (text.contains("permission") || text.contains("could not") || text.contains("failed")) {
            return .init(.authentication, "The browser profile could not be read. Check the selected profile and macOS privacy permissions, then retry.")
        }
        if ["sign in", "login required", "log in", "authentication", "private video", "confirm your age"].contains(where: text.contains) {
            return .init(.authentication, "This source requires sign-in. You can retry using a browser profile you are signed into.")
        }
        if ["drm", "geo", "copyright", "403", "forbidden", "not available in your country"].contains(where: text.contains) {
            return .init(.restricted, "The source denied this download. It may be restricted or temporarily blocked.")
        }
        if ["timed out", "timeout", "connection", "network", "429", "502", "503", "504", "resolve host"].contains(where: text.contains) {
            return .init(.network, "The connection was interrupted. Try again when the source is available.")
        }
        if ["unsupported url", "not supported", "unavailable", "has been removed", "404"].contains(where: text.contains) {
            return .init(.unsupported, "This link is unavailable or is not supported by the current engine.")
        }
        if text.contains("permission denied") { return .init(.destination, "Harbor cannot write to this folder. Choose another destination.") }
        return .init(.engine, "The download engine could not finish this item. Retry or check for an engine update.")
    }
}
public enum DownloadEvent: Sendable {
    case progress(bytes: Int64, total: Int64?, speed: Double?)
    case status(String)
    case title(String)
    case processing
}
public struct EngineSet: Codable, Sendable {
    public var version: String
    public var root: URL
    public init(version: String, root: URL) { self.version = version; self.root = root }
    public func executable(_ name: String) throws -> URL {
        let path = root.appendingPathComponent("MacOS").appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: path.path) else {
            throw DownloadFailure(.engine, "A required download component is missing (\(name)). Reinstall Harbor or check for an engine update.")
        }
        return path
    }
}
public protocol DownloadEngine: Sendable {
    func inspect(_ url: URL, engines: EngineSet, consent: BrowserConsent?) async throws -> Inspection
    func download(_ job: DownloadJob, engines: EngineSet, consent: BrowserConsent?, event: @escaping @Sendable (DownloadEvent) async -> Void) async throws -> URL
}
public protocol JobRepository: Sendable {
    func load() async throws -> [DownloadJob]
    func save(_ job: DownloadJob) async throws
    func remove(_ id: UUID) async throws
}
