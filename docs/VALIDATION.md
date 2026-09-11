# Validation — 2026-09-11

## Verified here

Host: Apple silicon Mac, Xcode 26.6, Swift 6.3.3. The app deployment target is macOS 14. The compiled helpers declare minimum versions of macOS 14 or earlier; this is a binary compatibility check, not evidence of a real macOS 14 run.

- **23 Swift Testing tests passed**, including five integration tests using real bundled engines and controlled loopback fixtures.
- **2 native XCTest UI tests passed**: entering a link, inspecting, downloading, relaunching, and finding completed history; and playlist preview starting unselected, Select All enabling two downloads, and Clear disabling downloading again.
- Debug and Release Xcode builds succeeded.
- An actual download was also entered through Harbor using computer UI automation, displayed transfer progress, and appeared in Completed. The fixture file was saved inside this workspace.
- Development packaging verifies nested code signatures, macOS minimum versions, and absence of Homebrew runtime dependencies. The generated DMG is ad-hoc signed, not notarized.

The tests cover URL parsing, extensionless files, redirects, misleading extensions, HEAD rejection, unknown totals, split Unicode stdout, heavy stderr, cancellation, filename collisions, Unicode filename bounds, restart recovery, SwiftData round trips, concurrency limits, playlist failure isolation, transient retry, shutdown, signed-manifest tampering, architecture/build rejection, unsafe manifest paths, artifact hash changes, live-stream rejection, audio-only format availability, range/no-range transfers, resume, all four conversion presets, and real playlist item routing.

One integration regression was found and fixed: generic multi-video pages can share their parent webpage URL across entries. Jobs now retain their selected item index and parent extraction source so retries refresh the correct media link.

## Evidence

- `build/final-tests.log` — complete core/integration and native UI run.
- `build/xcode/Logs/Test/Test-Harbor-2026.09.11_19-16-13-+0200.xcresult` — successful native UI test result.
- `build/release-build.log` — Release build.
- `build/release-integration-tests.log` — tests against engines embedded in the Release application.
- `build/package.log` — dependency/signature checks and DMG creation.
- `Vendor/cache/aria2-build.log`, `lame-build.log`, `ffmpeg-build.log` — portable source builds.

Generated logs, build products, and dependency archives are ignored by Git. Rerun the documented commands to regenerate them.

## Not claimed as verified

- Apple notarization, Gatekeeper acceptance on a clean external Mac, or Developer ID signing: no signing identity is installed here.
- A live publisher-signed update installation/rollback round trip: the channel URL, public key, and Team ID are unconfigured. Cryptographic and compatibility rejection tests pass, but these do not replace a staging-channel acceptance test.
- Intel hardware or a physical macOS 14 machine. CI defines separate ARM and Intel jobs but has not been run remotely from this workspace.
- Browser cookie access, Full Disk Access, Keychain prompts, authenticated streaming sources, or a maintained live-source compatibility matrix. No browser profiles were read during development.
- A complete distribution license/source audit for the standalone yt-dlp/PyInstaller and Deno dependency bundles. FFmpeg, LAME, and aria2 source archives are included; `releaseReady` remains false.
- Extended sleep/wake, multi-day use, a full VoiceOver audit, or every possible streaming codec/site.

These are public-release follow-ups, not claims hidden behind passing local tests. Torrents and iOS remain explicitly deferred product phases.
