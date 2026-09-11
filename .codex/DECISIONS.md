# Established Decisions

Recorded from the implementation and repository documentation on 2026-09-11. These explain the current baseline; revise them explicitly when a requested change supersedes one.

[Context index](README.md) · [Architecture](ARCHITECTURE.md)

| Decision | Rationale and consequence |
| --- | --- |
| Ship the macOS foundation first | Current helpers use macOS subprocess APIs. iOS requires a different execution approach and is deferred. |
| Keep core services outside SwiftUI | Actors and Sendable values separate scheduling, persistence, and engine work from presentation and allow controlled test adapters. |
| Use response-informed routing | Extensionless downloads and misleading extensions occur. Probe headers before falling back to a path extension. |
| Use aria2 for direct files | A private per-job RPC instance exposes transfer status and connection controls. The current media adapter uses yt-dlp's own downloading; aria2 is not injected into yt-dlp. |
| Require playlist selection and stable item identity | Avoid unexpected large batches. Generic multi-video pages can share a parent URL, so retain extraction source and selected index across retries. |
| Limit download and preparation concurrency separately | Up to three jobs make progress while one conversion/preparation operation controls heavier media work. |
| Keep user-visible presets capability-aware | Highest preserves available quality; Mobile targets compatible MP4; M4A and MP3 cover audio. Raw extractor format IDs stay inside the engine layer. |
| Stage beside the destination and never overwrite | Per-job partials support recovery, and finalization chooses an unused filename. Removing history does not delete user files. |
| Resume explicitly after relaunch | Reopening the app does not silently start a large stored queue. Direct partials resume only when server validators establish continuity. |
| Make clipboard and browser access deliberate | Clipboard suggestions default off; inspection follows Add. Browser consent is temporary and scoped to the requested work. |
| Update complete publisher-verified engine sets | Compatibility and provenance require more than downloading the newest upstream executable. Atomic activation, pinned running jobs, and retained versions support rollback. |
| Separate development packaging from public readiness | Ad-hoc DMGs permit local use. Publisher configuration, redistribution audit, signing, notarization, and external validation remain release requirements. |
| Use local fixtures for routine integration tests | Generated media and loopback endpoints make regressions reproducible without depending on personal profiles or changing external websites. |

For current defaults see [PROJECT.md](PROJECT.md); for evidence gaps see [STATUS.md](STATUS.md). Keep this file focused on decisions and reasons rather than a chronological work log. When changing persisted job fields, engine interfaces, or one of these behaviors, update the affected guide and relevant regression coverage together.
