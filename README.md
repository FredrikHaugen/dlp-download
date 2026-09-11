# Harbor

A native macOS download manager built with SwiftUI. Paste links, preview media or playlists, choose a format, and save to a folder on your Mac. “Harbor” is a provisional name.

## What works

- Streaming-page inspection and downloads through bundled yt-dlp, with Deno for JavaScript challenges.
- Direct HTTP(S) files through a private, authenticated, loopback-only aria2 process.
- Highest Quality, Mobile Compatible (H.264/AAC MP4, up to 1080p), M4A, and MP3 presets.
- Playlist previews with explicit selection, independent jobs, and a 1,000-entry preview limit.
- Three simultaneous jobs, one media preparation operation, persistent history, cancellation, retry, and restart recovery.
- Native destination selection, collision-safe filenames, Finder reveal, and local staging.
- Opt-in clipboard suggestions and explicit browser/profile access per job or batch.
- Signed engine-manifest verification, staged installation, code-signature checks, startup checks, and rollback.

Torrents, live recording, iOS, browser extensions, and cloud processing remain later releases. No DRM decryption is implemented. Source availability depends on the website and current engine support.

## Build

Requires Xcode 16+ with Swift 6, XcodeGen, and Python 3.12+. The app and portable source builds target macOS 14. Build on each architecture to produce its matching engine set.

```sh
python3 Scripts/bootstrap_engines.py
xcodegen generate
xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/xcode build
```

Open `build/xcode/Build/Products/Debug/Harbor.app`, or open `Harbor.xcodeproj` in Xcode and run Harbor. Engines are embedded automatically; end users do not need Python, Homebrew, or command-line tools.

The bootstrap fetches official versioned yt-dlp and Deno artifacts, builds aria2, and builds a minimal LGPL FFmpeg with static LAME and Apple media frameworks. Source archives, build logs, and generated binaries live in ignored `Vendor/`. `dependencies.lock.json` records fetched input hashes. No package is installed system-wide by the bootstrap.

## Validate

```sh
swift test --scratch-path build/swift-package
python3 Scripts/integration_test.py
python3 Scripts/integration_test.py --ui
```

The first command runs unit tests; five local engine integration tests are skipped unless fixture environment variables are set. The second generates a two-second test film, starts a loopback HTTP server, and runs every core test, including real downloads, conversion, routing, and resume. The third also runs native UI tests for downloading, history recovery, and playlist selection against isolated history and destination storage. These tests do not download third-party media.

To test the exact engines in a built application:

```sh
python3 Scripts/integration_test.py build/xcode/Build/Products/Debug/Harbor.app/Contents
```

CI builds and validates separate Apple silicon and Intel artifacts. Local evidence and limitations are recorded in [docs/VALIDATION.md](docs/VALIDATION.md).

## Data and behavior

SwiftData stores history in `~/Library/Application Support/Harbor/Downloads.store`. Preferences use the app’s UserDefaults domain. Original source URLs are retained for retry; they can contain private or expiring link tokens, so the history should be treated as private local data. Browser consent and cookie contents are not persisted.

Closing the window keeps the app and jobs running. Quitting cancels its helper processes and preserves jobs for explicit resume at next launch. Restarting never silently starts a large queue. Direct files resume only with matching strong ETags and byte-range support; otherwise they restart safely. Streaming retries resolve the original source again and use yt-dlp’s resumable partial files.

Partial files remain in hidden `.harbor-<job UUID>` directories inside the selected destination until a successful completion. Removing history keeps completed files and any partial staging directory. Choosing a new destination leaves the old partial directory untouched.

## Distribution and engine updates

This checkout can produce an ad-hoc-signed development DMG:

```sh
xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/xcode build
python3 Scripts/package_app.py --development
```

Public release needs a Developer ID identity, notarization credentials, a publisher-controlled HTTPS update channel, an Ed25519 public key embedded in `Resources/EngineChannel.json`, and an audited dependency source/license package. None of those publisher credentials are included. The empty channel configuration is intentional: the app uses its bundled engines and reports that automatic updates are not configured.

See [docs/RELEASING.md](docs/RELEASING.md) for signing, notarization, engine publishing artifacts, and source provenance. Packaging tools create local artifacts and do not publish a release.

## Structure

`Sources/HarborCore` contains Sendable domain values, routing, engines, the coordinator, SwiftData persistence, process ownership, and updates. `Sources/Harbor` contains the SwiftUI app and AppKit integration. The shared core has no UI dependency; macOS subprocess implementations will need separate alternatives for any future iOS client.

No app source license has been selected yet. Third-party engine licenses remain applicable independently; review the source archives and notices before redistribution.
