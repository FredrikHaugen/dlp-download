# Architecture

[Context index](README.md) · [Decision rationale](DECISIONS.md)

## Ownership and Interfaces

| Component | Responsibility |
| --- | --- |
| [AppModel](../Sources/Harbor/AppModel.swift) | Main-actor Observation model; owns service references, preferences, and the snapshot subscription exposed to SwiftUI |
| [DownloadCoordinator](../Sources/HarborCore/DownloadCoordinator.swift) | Actor owning job state, scheduling, ephemeral consent, running tasks, retries, and engine selection |
| [Domain types](../Sources/HarborCore/Models.swift) | Sendable job, inspection, preset, failure, event, and engine-set values; `DownloadEngine` and `JobRepository` protocols |
| [Job stores](../Sources/HarborCore/JobStore.swift) | SwiftData model actor for persistence and an in-memory repository for controlled tests |
| [LinkRouter and FileSafety](../Sources/HarborCore/LinkRouter.swift) | Input parsing, response-informed routing, staging, output validation, and collision-safe finalization |
| [MediaEngine](../Sources/HarborCore/MediaEngine.swift) / [DirectEngine](../Sources/HarborCore/DirectEngine.swift) | yt-dlp/FFmpeg media flow and aria2 direct transfer implementation |
| [ProcessRunner](../Sources/HarborCore/ProcessRunner.swift) | Process lifetime, pipe draining, line delivery, timeout, and cancellation |
| [EngineUpdater](../Sources/HarborCore/EngineUpdater.swift) | Channel verification, staged installation, startup validation, activation, and rollback |

`DownloadEngine.inspect` returns an `Inspection`; `download` emits asynchronous `DownloadEvent` values and returns a staged file URL. The coordinator finalizes that file. `JobRepository` provides asynchronous load, save, and removal. Keep these injection points usable by fixture engines and stores.

## Download Flow

1. The Add sheet parses links and asks the coordinator to inspect them. Routing uses response MIME and disposition headers, with extension fallback. A rejected HEAD request can fall back to a bounded headers-oriented GET. Torrent inputs receive an unsupported response.
2. Inspection produces selectable items and supported presets. Selected playlist items retain `extractionSource` and `playlistIndex` when entries share the parent URL, so retries resolve the intended item.
3. Enqueue persists jobs before scheduling. The coordinator starts up to three tasks and pins an `EngineSet` for each task. It publishes the newest job snapshot through `AsyncStream`.
4. Media jobs use structured yt-dlp progress and output-path markers. `ConversionGate` serializes preparation; FFmpeg handles conversion/merging and ffprobe checks outputs. Direct jobs use a per-job authenticated aria2 process and poll RPC progress.
5. Engines write beneath the destination's hidden `.harbor-<job UUID>` directory. FileSafety validates the output and moves it to an unused filename before the job becomes completed.

## Recovery and Concurrency

Network failures receive up to three retries with delays of 2, 4, and 8 seconds. Unsupported or authentication failures await user action. Unknown totals remain indeterminate; preparation is a separate state. Storage failures suspend further scheduling instead of allowing untracked work.

On startup, stored queued or active jobs become interrupted. Removing a history entry does not remove its files. Direct resume requires a matching strong ETag and byte-range support; otherwise that job's direct partial output restarts. Media retries re-extract the source and retain resumable staging.

`JobRecord` stores a unique UUID and a JSON-encoded `DownloadJob` payload. Changes to persisted Codable values need compatibility consideration for existing history. Browser consent is held separately in memory.

The core has no SwiftUI dependency, but uses macOS APIs. Keep process execution and blocking pipe reads outside views and the main actor. Preserve cancellation propagation to helper descendants. Engine activation affects newly scheduled work; installed versions remain available to existing jobs. See [security](SECURITY.md) and [testing](TESTING.md) before changing these boundaries.
