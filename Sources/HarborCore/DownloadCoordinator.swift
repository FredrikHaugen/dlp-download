import Foundation

public actor DownloadCoordinator {
    private let repository: any JobRepository
    private let media: any DownloadEngine
    private let direct: any DownloadEngine
    private var engines: EngineSet
    private var jobs: [UUID: DownloadJob] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var consents: [UUID: BrowserConsent] = [:]
    private var observers: [UUID: AsyncStream<[DownloadJob]>.Continuation] = [:]
    private var lastSaved: [UUID: Date] = [:]
    private var stopping = false
    private var storageFailure: String?
    public init(repository: any JobRepository, engines: EngineSet, media: any DownloadEngine = MediaEngine(), direct: any DownloadEngine = DirectEngine()) {
        self.repository = repository; self.engines = engines; self.media = media; self.direct = direct
    }
    public func start() async throws {
        for var job in try await repository.load() {
            if job.state.isActive || job.state == .queued {
                job.state = .interrupted; job.status = "Ready to resume"; job.progress = nil
                try await repository.save(job)
            }
            jobs[job.id] = job
        }
        publish()
    }
    public func snapshots() -> AsyncStream<[DownloadJob]> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers[id] = continuation
            continuation.yield(sortedJobs)
            continuation.onTermination = { @Sendable _ in Task { await self.removeObserver(id) } }
        }
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
    private var sortedJobs: [DownloadJob] { jobs.values.sorted { $0.createdAt > $1.createdAt } }
    private func publish() { for continuation in observers.values { continuation.yield(sortedJobs) } }
    public func currentEngines() -> EngineSet { engines }
    public func activate(_ value: EngineSet) { engines = value }
    public func inspect(_ url: URL, consent: BrowserConsent? = nil) async throws -> Inspection {
        let (kind, title) = try await LinkRouter().route(url)
        switch kind {
        case .torrent: throw DownloadFailure(.unsupported, "Torrent and magnet downloads are planned for the next release.")
        case .file: return Inspection(kind: .file, title: title, items: [MediaItem(id: url.absoluteString, url: url, title: title)])
        case .media: return try await media.inspect(url, engines: engines, consent: consent)
        }
    }
    public func enqueue(_ values: [DownloadJob], consent: BrowserConsent? = nil) async throws {
        guard !stopping else { return }
        if let storageFailure { throw DownloadFailure(.destination, storageFailure + " Restart Harbor after freeing disk space.") }
        for job in values {
            guard job.kind != .torrent else { throw DownloadFailure(.unsupported, "Torrent downloads are not available yet.") }
            try await repository.save(job)
            jobs[job.id] = job
            consents[job.id] = consent
        }
        publish(); schedule()
    }
    public func retry(_ id: UUID, consent: BrowserConsent? = nil, destination: URL? = nil) async throws {
        if let storageFailure { throw DownloadFailure(.destination, storageFailure + " Restart Harbor after freeing disk space.") }
        guard var job = jobs[id], job.state.canRetry, tasks[id] == nil else { return }
        if let destination { job.destination = destination }
        job.state = .queued; job.error = nil; job.progress = nil; job.status = "Waiting"; job.attempts = 0
        try await repository.save(job)
        jobs[id] = job; consents[id] = consent
        publish(); schedule()
    }
    public func cancel(_ id: UUID) async throws {
        guard var job = jobs[id], job.state.isActive || job.state == .queued else { return }
        job.state = .cancelled; job.status = "Cancelled"; job.progress = nil
        jobs[id] = job
        tasks[id]?.cancel()
        try await repository.save(job)
        publish()
    }
    public func remove(_ id: UUID) async throws {
        guard let job = jobs[id], !job.state.isActive, job.state != .queued, tasks[id] == nil else { return }
        try await repository.remove(id)
        jobs[id] = nil; consents[id] = nil
        publish()
    }
    public func shutdown() async {
        stopping = true
        let running = tasks
        for (_, task) in running { task.cancel() }
        for (_, task) in running { await task.value }
        for id in Array(jobs.keys) {
            guard var job = jobs[id], job.state == .queued || job.state.isActive else { continue }
            job.state = .interrupted; job.status = "Ready to resume"; jobs[id] = job
            try? await repository.save(job)
        }
    }
    private func schedule() {
        guard !stopping, storageFailure == nil else { return }
        let queue = jobs.values.filter { $0.state == .queued && tasks[$0.id] == nil }.sorted { $0.createdAt < $1.createdAt }
        for job in queue.prefix(max(0, 3 - tasks.count)) {
            let pinned = engines
            tasks[job.id] = Task { await self.execute(job.id, engines: pinned) }
        }
    }
    private func execute(_ id: UUID, engines: EngineSet) async {
        defer { tasks[id] = nil; consents[id] = nil; schedule() }
        guard var job = jobs[id], job.state == .queued else { return }
        job.engineVersion = engines.version; jobs[id] = job
        let engine = job.kind == .file ? direct : media
        do {
            for attempt in 0...3 {
                try Task.checkCancellation()
                guard jobs[id]?.state != .cancelled else { return }
                jobs[id]?.state = .downloading; jobs[id]?.status = attempt == 0 ? "Connecting" : "Retrying connection"; jobs[id]?.attempts = attempt
                try await persist(id)
                do {
                    let output = try await engine.download(job, engines: engines, consent: consents[id]) { event in await self.receive(event, id: id) }
                    try Task.checkCancellation()
                    let final = try FileSafety.finish(output, job: jobs[id] ?? job)
                    jobs[id]?.output = final; jobs[id]?.state = .completed; jobs[id]?.status = "Complete"; jobs[id]?.progress = 1; jobs[id]?.error = nil
                    try await persist(id)
                    return
                } catch {
                    if error is CancellationError || Task.isCancelled { throw CancellationError() }
                    let failure = normalized(error)
                    if failure.kind == .network && attempt < 3 {
                        jobs[id]?.status = "Connection interrupted · retry \(attempt + 1) of 3"
                        publish()
                        try await Task.sleep(for: .seconds(pow(2, Double(attempt + 1))))
                    } else { throw failure }
                }
            }
        } catch {
            if Task.isCancelled || error is CancellationError {
                if jobs[id]?.state != .cancelled { jobs[id]?.state = .interrupted; jobs[id]?.status = "Ready to resume" }
            } else {
                jobs[id]?.state = .failed; jobs[id]?.error = normalized(error); jobs[id]?.status = "Needs attention"
            }
            jobs[id]?.progress = nil
            do { try await persist(id) } catch { storageFailure = "Download history could not be saved."; publish() }
        }
    }
    private func receive(_ event: DownloadEvent, id: UUID) async {
        guard jobs[id]?.state.isActive == true else { return }
        switch event {
        case let .progress(bytes, total, speed):
            jobs[id]?.downloadedBytes = bytes; jobs[id]?.totalBytes = total; jobs[id]?.bytesPerSecond = speed
            jobs[id]?.progress = total.flatMap { $0 > 0 ? min(1, max(0, Double(bytes) / Double($0))) : nil }
            jobs[id]?.status = "Downloading"
        case .processing: jobs[id]?.state = .processing; jobs[id]?.status = "Preparing file"; jobs[id]?.progress = nil; jobs[id]?.bytesPerSecond = nil
        case .status(let status): jobs[id]?.status = status
        case .title(let title): jobs[id]?.title = title
        }
        publish()
        if Date.now.timeIntervalSince(lastSaved[id] ?? .distantPast) > 1 {
            do { try await persist(id) }
            catch { storageFailure = "Download history could not be saved."; tasks[id]?.cancel() }
        }
    }
    private func persist(_ id: UUID) async throws {
        guard var job = jobs[id] else { return }
        job.updatedAt = .now; jobs[id] = job
        try await repository.save(job)
        lastSaved[id] = .now; publish()
    }
    private func normalized(_ error: Error) -> DownloadFailure {
        if let failure = error as? DownloadFailure { return failure }
        if let urlError = error as? URLError { return .init(.network, urlError.code == .notConnectedToInternet ? "You’re offline. Connect to the internet and retry." : "The connection could not be completed.") }
        if (error as NSError).domain == NSCocoaErrorDomain { return .init(.destination, "The download could not be saved. Check the destination folder and available space.") }
        return .init(.engine, "The download could not be completed.")
    }
}
