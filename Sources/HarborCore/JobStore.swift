import Foundation
import SwiftData

@Model public final class JobRecord {
    @Attribute(.unique) public var id: UUID
    public var payload: Data
    public init(_ job: DownloadJob) throws { id = job.id; payload = try JSONEncoder().encode(job) }
}

@ModelActor public actor PersistentJobStore: JobRepository {
    public func load() throws -> [DownloadJob] {
        try modelContext.fetch(FetchDescriptor<JobRecord>()).map { try JSONDecoder().decode(DownloadJob.self, from: $0.payload) }.sorted { $0.createdAt < $1.createdAt }
    }
    public func save(_ job: DownloadJob) throws {
        let id = job.id
        let descriptor = FetchDescriptor<JobRecord>(predicate: #Predicate { $0.id == id })
        if let record = try modelContext.fetch(descriptor).first { record.payload = try JSONEncoder().encode(job) }
        else { modelContext.insert(try JobRecord(job)) }
        try modelContext.save()
    }
    public func remove(_ id: UUID) throws {
        let descriptor = FetchDescriptor<JobRecord>(predicate: #Predicate { $0.id == id })
        for record in try modelContext.fetch(descriptor) { modelContext.delete(record) }
        try modelContext.save()
    }
}

public actor MemoryJobStore: JobRepository {
    private var jobs: [UUID: DownloadJob]
    public init(_ jobs: [DownloadJob] = []) { self.jobs = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) }) }
    public func load() -> [DownloadJob] { Array(jobs.values) }
    public func save(_ job: DownloadJob) { jobs[job.id] = job }
    public func remove(_ id: UUID) { jobs[id] = nil }
}
