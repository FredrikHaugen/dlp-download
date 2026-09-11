import Foundation

public actor ConversionGate {
    private var busy = false
    public init() {}
    public func acquire() async throws {
        while busy { try await Task.sleep(for: .milliseconds(100)) }
        try Task.checkCancellation(); busy = true
    }
    public func release() { busy = false }
}

public struct MediaEngine: DownloadEngine {
    private let runner = ProcessRunner()
    private let conversions: ConversionGate
    public init(conversions: ConversionGate = ConversionGate()) { self.conversions = conversions }

    public func baseArguments(engines: EngineSet, consent: BrowserConsent?) throws -> [String] {
        var args = ["--ignore-config", "--no-plugin-dirs", "--no-cache-dir", "--no-warnings", "--no-colors", "--no-update", "--no-remote-components", "--socket-timeout", "30", "--retries", "0", "--fragment-retries", "0", "--ffmpeg-location", engines.root.appendingPathComponent("MacOS").path, "--js-runtimes", "deno:" + (try engines.executable("deno")).path]
        if let consent { args += ["--cookies-from-browser", consent.argument] }
        return args
    }

    public func inspect(_ url: URL, engines: EngineSet, consent: BrowserConsent?) async throws -> Inspection {
        let args = try baseArguments(engines: engines, consent: consent) + ["--flat-playlist", "--dump-single-json", "--skip-download", "--ignore-errors", "--playlist-end", "1000", "--", url.absoluteString]
        let result = try await runner.run(executable: engines.executable("yt-dlp"), arguments: args, timeout: 120)
        guard !result.stdout.isEmpty, let data = result.stdout.data(using: .utf8) else { throw DownloadFailure.classify(result.stderr) }
        return try Self.decodeInspection(data, source: url)
    }

    public static func decodeInspection(_ data: Data, source: URL) throws -> Inspection {
        guard let info = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DownloadFailure(.engine, "The source returned invalid media information.") }
        let title = info["title"] as? String ?? source.host ?? "Media"
        let entries = info["entries"] as? [Any]
        let rawItems = entries ?? [info]
        let items = rawItems.enumerated().compactMap { index, raw -> MediaItem? in
            guard let entry = raw as? [String: Any] else { return nil }
            let id = entry["id"] as? String ?? String(index)
            let title = entry["title"] as? String ?? "Unavailable item"
            let candidate = (entry["webpage_url"] as? String) ?? (entry["url"] as? String)
            let resolved = candidate.flatMap(URL.init(string:))
            let valid = resolved.flatMap { ["http", "https"].contains($0.scheme ?? "") ? $0 : nil }
            let url = entries == nil ? source : valid
            let availability = entry["availability"] as? String ?? ""
            let unavailable = title == "[Deleted video]" || title == "[Private video]" || availability == "private" || url == nil
            let thumbnails = entry["thumbnails"] as? [[String: Any]]
            let thumbnail = ((entry["thumbnail"] as? String) ?? (thumbnails?.last?["url"] as? String)).flatMap(URL.init(string:))
            return MediaItem(id: "\(index):\(id)", url: url ?? source, title: title, duration: entry["duration"] as? Double, thumbnail: thumbnail, available: !unavailable)
        }
        guard !items.isEmpty else { throw DownloadFailure(.unsupported, "No downloadable items were found at this link.") }
        return Inspection(kind: .media, title: title, items: items, isPlaylist: entries != nil, truncated: (info["playlist_count"] as? Int ?? items.count) > 1000 || items.count >= 1000)
    }

    public static func progressEvent(_ line: String) -> DownloadEvent? {
        guard line.hasPrefix("HARBOR_PROGRESS "), let data = line.dropFirst(16).data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let bytes = (value["downloaded_bytes"] as? NSNumber)?.int64Value ?? 0
        let total = (value["total_bytes"] as? NSNumber)?.int64Value ?? (value["total_bytes_estimate"] as? NSNumber)?.int64Value
        return .progress(bytes: bytes, total: total.flatMap { $0 > 0 ? $0 : nil }, speed: (value["speed"] as? NSNumber)?.doubleValue)
    }

    public func download(_ job: DownloadJob, engines: EngineSet, consent: BrowserConsent?, event: @escaping @Sendable (DownloadEvent) async -> Void) async throws -> URL {
        try FileSafety.prepare(job)
        // Download only here; all merge/conversion work takes the shared conversion slot.
        let selector = switch job.preset {
        case .highest: "bv*+ba/b"
        case .mobile: "bv*[height<=1080]+ba/b[height<=1080]"
        case .m4a, .mp3: "ba/b"
        }
        let paths = OutputPaths()
        var args = try baseArguments(engines: engines, consent: consent)
        args += ["--no-playlist", "--newline", "--progress", "--progress-delta", "0.3", "--progress-template", "download:HARBOR_PROGRESS %(progress)j", "--print", "before_dl:HARBOR_TITLE %(title)j", "--print", "after_video:HARBOR_FILES %(requested_downloads.:.filepath)j", "--print", "after_move:HARBOR_FILE %(filepath)j", "--no-simulate", "--continue", "--no-overwrites", "--no-mtime", "--restrict-filenames", "--trim-filenames", "150", "--fixup", "never", "--format", selector, "--output", "%(title).120B [%(id)s].%(ext)s", "--paths", job.stagingDirectory.path]
        // yt-dlp can download separate streams without merging when ffmpeg is unavailable.
        // --allow-unplayable-formats would change DRM behavior, so use separate format output instead.
        if job.preset == .highest || job.preset == .mobile {
            args[args.firstIndex(of: selector)!] = job.preset == .highest ? "bv,ba/b" : "bv[height<=1080],ba/b[height<=1080]"
        }
        args += ["--", job.source.absoluteString]
        let result = try await runner.run(executable: engines.executable("yt-dlp"), arguments: args) { line in
            if let progress = Self.progressEvent(line) { await event(progress) }
            if line.hasPrefix("HARBOR_TITLE "), let data = line.dropFirst(13).data(using: .utf8), let title = try? JSONDecoder().decode(String.self, from: data) { await event(.title(title)) }
            if line.hasPrefix("HARBOR_FILE "), let data = line.dropFirst(12).data(using: .utf8), let path = try? JSONDecoder().decode(String.self, from: data) { await paths.add(URL(fileURLWithPath: path)) }
        }
        guard result.status == 0 else { throw DownloadFailure.classify(result.stderr) }
        let files = await paths.values
        guard !files.isEmpty else { throw DownloadFailure(.engine, "The engine finished without reporting an output file.") }
        for file in files { try FileSafety.validate(file, inside: job.stagingDirectory) }
        await event(.status("Waiting to prepare file"))
        try await conversions.acquire()
        do {
            await event(.processing)
            let output = try await processMedia(files, job: job, engines: engines)
            await conversions.release()
            return output
        } catch { await conversions.release(); throw error }
    }

    private func processMedia(_ files: [URL], job: DownloadJob, engines: EngineSet) async throws -> URL {
        let probe = try await runner.run(executable: engines.executable("ffprobe"), arguments: ["-v", "error", "-show_streams", "-show_format", "-of", "json", files[0].path], timeout: 30)
        guard probe.status == 0, let data = probe.stdout.data(using: .utf8), let info = try JSONSerialization.jsonObject(with: data) as? [String: Any], let streams = info["streams"] as? [[String: Any]], !streams.isEmpty else { throw DownloadFailure(.engine, "The downloaded media could not be validated.") }
        let video = streams.first { $0["codec_type"] as? String == "video" }
        let audio = streams.first { $0["codec_type"] as? String == "audio" }
        let duration = ((info["format"] as? [String: Any])?["duration"] as? String).flatMap(Double.init) ?? 0
        guard duration > 0 || !streams.isEmpty else { throw DownloadFailure(.engine, "The downloaded media is empty.") }
        let ext: String
        switch job.preset {
        case .highest: ext = video == nil ? files[0].pathExtension : ((video?["codec_name"] as? String == "h264" || video?["codec_name"] as? String == "hevc") ? "mp4" : "mkv")
        case .mobile: ext = "mp4"
        case .m4a: ext = "m4a"
        case .mp3: ext = "mp3"
        }
        let output = job.stagingDirectory.appendingPathComponent(FileSafety.filename(job.title) + "." + ext)
        if files.count == 1 && job.preset == .highest { return files[0] }
        let target = files.contains(output) ? job.stagingDirectory.appendingPathComponent("Prepared " + output.lastPathComponent) : output
        var args = ["-hide_banner", "-nostdin", "-loglevel", "error", "-y"]
        for file in files.prefix(2) { args += ["-i", file.path] }
        switch job.preset {
        case .highest:
            args += ["-map", "0:v?", "-map", files.count > 1 ? "1:a?" : "0:a?", "-c", "copy"]
        case .mobile:
            guard video != nil else { throw DownloadFailure(.unsupported, "This source has no video for the Mobile preset. Choose Audio instead.") }
            args += ["-map", "0:v:0", "-map", files.count > 1 ? "1:a:0" : "0:a:0?", "-c:v", video?["codec_name"] as? String == "h264" ? "copy" : "h264_videotoolbox"]
            if video?["codec_name"] as? String != "h264" { args += ["-b:v", "5M", "-pix_fmt", "yuv420p"] }
            args += ["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case .m4a:
            args += ["-vn", "-c:a", audio?["codec_name"] as? String == "aac" ? "copy" : "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case .mp3:
            args += ["-vn", "-c:a", audio?["codec_name"] as? String == "mp3" ? "copy" : "libmp3lame", "-q:a", "2"]
        }
        args.append(target.path)
        let result = try await runner.run(executable: engines.executable("ffmpeg"), arguments: args)
        guard result.status == 0 else { throw DownloadFailure.classify(result.stderr) }
        try FileSafety.validate(target, inside: job.stagingDirectory)
        let check = try await runner.run(executable: engines.executable("ffprobe"), arguments: ["-v", "error", "-show_entries", "format=duration", "-of", "json", target.path], timeout: 30)
        guard check.status == 0 else { throw DownloadFailure(.engine, "The converted file could not be validated.") }
        return target
    }
}

private actor OutputPaths {
    var values: [URL] = []
    func add(_ url: URL) { if !values.contains(url) { values.append(url) } }
}
