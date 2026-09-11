import Foundation

public struct LinkRouter: Sendable {
    public init() {}
    public func parse(_ text: String) throws -> [URL] {
        let values = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !values.isEmpty else { throw DownloadFailure(.unsupported, "Paste a download link to get started.") }
        var seen = Set<URL>()
        return try values.map { value in
            guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
                  ["http", "https", "magnet"].contains(scheme), let url = components.url,
                  scheme == "magnet" || (components.host?.isEmpty == false && components.user == nil && components.password == nil) else {
                throw DownloadFailure(.unsupported, "Use a complete HTTP or HTTPS link. Links with embedded passwords are not supported.")
            }
            return url
        }.filter { seen.insert($0).inserted }
    }
    public func route(_ url: URL) async throws -> (DownloadKind, String) {
        if url.scheme?.lowercased() == "magnet" || url.pathExtension.lowercased() == "torrent" { return (.torrent, "Torrent") }
        let headers = try await probe(url)
        let mime = headers.mimeType?.lowercased() ?? ""
        if mime == "application/x-bittorrent" { return (.torrent, "Torrent") }
        let filename = FileSafety.filename(headers.suggestedFilename ?? url.lastPathComponent)
        if mime.contains("mpegurl") || mime.contains("dash+xml") { return (.media, filename) }
        if mime.contains("text/html") || mime.contains("xhtml") { return (.media, filename) }
        if headers.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") == true { return (.file, filename) }
        if mime.hasPrefix("video/") || mime.hasPrefix("audio/") || mime.hasPrefix("image/") ||
            ["application/octet-stream", "application/pdf", "application/zip", "application/x-apple-diskimage", "application/x-gzip", "application/x-tar"].contains(mime) { return (.file, filename) }
        let fileExtensions: Set<String> = ["zip", "pkg", "dmg", "mp4", "mov", "mkv", "mp3", "m4a", "pdf", "gz", "tar", "7z", "iso", "png", "jpg"]
        return (fileExtensions.contains(url.pathExtension.lowercased()) ? .file : .media, filename)
    }
    public func probe(_ url: URL) async throws -> HTTPURLResponse {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, first) = try await session.data(for: request)
        guard let response = first as? HTTPURLResponse else { throw DownloadFailure(.network, "The server returned an invalid response.") }
        if [400, 403, 405, 501].contains(response.statusCode) || response.mimeType == nil {
            request.httpMethod = "GET"
            request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
            // Obtaining headers through AsyncBytes avoids buffering a server that ignores Range.
            let (_, second) = try await session.bytes(for: request)
            return (second as? HTTPURLResponse) ?? response
        }
        return response
    }
}

public enum FileSafety {
    public static func filename(_ value: String) -> String {
        let sanitized = value.components(separatedBy: CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty || sanitized == "." || sanitized == ".." ? "Download" : String(sanitized.prefix(180))
    }
    public static func prepare(_ job: DownloadJob) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: job.destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DownloadFailure(.destination, "The destination folder is unavailable. Choose a folder and retry.")
        }
        let values = try job.destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < 50_000_000 {
            throw DownloadFailure(.destination, "There is less than 50 MB free at the destination. Free some space and retry.")
        }
        try FileManager.default.createDirectory(at: job.stagingDirectory, withIntermediateDirectories: true)
        let staging = try job.stagingDirectory.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard staging.isSymbolicLink != true else { throw DownloadFailure(.destination, "The temporary download folder is not safe to use.") }
    }
    public static func validate(_ file: URL, inside directory: URL) throws {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let resolved = file.resolvingSymlinksInPath().standardizedFileURL
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard resolved.path.hasPrefix(root), values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw DownloadFailure(.engine, "The engine did not produce a valid output file.")
        }
    }
    public static func finish(_ source: URL, job: DownloadJob) throws -> URL {
        try validate(source, inside: job.stagingDirectory)
        let base = filename(source.deletingPathExtension().lastPathComponent)
        let ext = source.pathExtension
        for index in 0..<10_000 {
            let name = base + (index == 0 ? "" : " (\(index + 1))") + (ext.isEmpty ? "" : "." + ext)
            let target = job.destination.appendingPathComponent(name)
            do {
                // moveItem fails if target already exists; never overwrite in a race.
                try FileManager.default.moveItem(at: source, to: target)
                try? FileManager.default.removeItem(at: job.stagingDirectory)
                return target
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
        }
        throw DownloadFailure(.destination, "Too many files share this name. Choose another folder.")
    }
}
