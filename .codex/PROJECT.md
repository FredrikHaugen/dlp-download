# Project Context

[Context index](README.md) · [Product README](../README.md)

## Product

Harbor is the provisional name for a native macOS download manager. The primary flow is paste links, inspect available media, select a format and destination, then follow progress without entering terminal commands. The repository currently targets macOS 14+ with Swift 6 and SwiftUI. Distribution is through a standalone Mac app, with development DMG tooling already present.

## Implemented Scope

- Media-page inspection and downloads use bundled yt-dlp, Deno, FFmpeg, and ffprobe. Direct HTTP(S) files use aria2 through private loopback RPC.
- The Add sheet accepts up to 100 links. Playlist previews contain at most 1,000 entries and start unselected; selected entries become independent jobs.
- Formats are Highest Quality, Mobile Compatible (H.264/AAC MP4 up to 1080p), M4A, and MP3. Available choices depend on inspected media. Direct files retain their original content.
- The queue supports progress, cancellation, retry, persistent history, destination selection, and Finder reveal. Three jobs may run concurrently; media preparation is serialized.
- Browser access is explicitly scoped to a job or batch. Clipboard suggestions are opt-in. Engine update verification and rollback are implemented, but a publisher channel is not configured.

Implementation does not establish source compatibility or public-release readiness; consult [status](STATUS.md).

## Defaults and Lifecycle

| Setting or event | Current behavior |
| --- | --- |
| Destination | The user's Downloads folder, replaceable through a native folder picker |
| Media format | Highest Quality |
| Direct-file connections | Four per server, configurable from one to sixteen |
| Clipboard suggestions | Off; when enabled, changed text is checked on app activation |
| Automatic engine updates | Preference on; network checks require a configured channel |
| Window close | App and active jobs remain running |
| App quit and relaunch | Helpers stop; pending jobs become interrupted and require explicit resume |
| Remove history | Completed files and partial staging directories remain |

History is local SwiftData storage, and preferences use UserDefaults. Original URLs are retained for retry and can contain private tokens. See [security](SECURITY.md) for data handling.

## Deferred Work

Torrents and magnet downloads, live recording, iOS, browser extensions, and cloud processing are deferred. A torrent enum case and routing detection do not mean torrent downloading is implemented. The shared core has macOS subprocess dependencies; future iOS support needs an execution alternative. No DRM decryption or account service is implemented. The app source license remains undecided.
