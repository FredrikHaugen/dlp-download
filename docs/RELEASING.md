# Releasing Harbor

## Current boundary

The development app uses ad-hoc signatures and has no configured remote update channel. It is usable locally, but is not a notarized public release. Release tooling deliberately refuses public packaging until publisher configuration and the dependency audit are complete.

## Reproducible engine inputs

The bootstrap pins yt-dlp 2026.07.04, aria2 1.37.0, Deno 2.9.4, FFmpeg 8.1.2, and LAME 3.100. Hashes of downloaded source/artifact inputs are recorded in `dependencies.lock.json` and enforced on subsequent bootstraps. yt-dlp release checksums and Deno asset digests are additionally checked. These are bootstrap checks; client updates use a separate publisher-controlled Ed25519 trust root.

FFmpeg and aria2 build for macOS 14 against the selected Xcode SDK; FFmpeg links LAME statically and has no Homebrew dylib dependencies. Build scripts and exact source archives accompany the generated engine set. ARM and Intel builds are separate artifacts. Do not mark an Intel package validated solely because the Swift target compiles for Intel.

Before redistribution, audit the standalone yt-dlp/PyInstaller dependency licenses and corresponding sources, Deno’s bundled dependencies, aria2, and the actual FFmpeg configuration. The PyInstaller yt-dlp binary includes GPL-covered code despite yt-dlp’s own Unlicense. Add all required notices and corresponding sources to `Vendor/EngineSet/Resources`, then set `releaseReady` in its generated manifest only after the audit is complete. The current manifest remains false. This is not a claim that the generated source folder alone meets every redistribution obligation.

## Public app package

1. Set `manifestURL`, `publicKey` (base64 Ed25519 public key), `teamID`, and `appBuild` in `Resources/EngineChannel.json`. The Team ID must match the Developer ID that signs every engine helper.
2. Build Release and run `Scripts/integration_test.py` against that exact app’s `Contents` directory.
3. Provide `HARBOR_SIGNING_IDENTITY` and `HARBOR_NOTARY_PROFILE` in the local environment, using an existing notarytool Keychain profile. Do not commit credentials.
4. Run `python3 Scripts/package_app.py`. It signs nested helpers, notarizes/staples the app, checks Gatekeeper, creates a DMG, and notarizes/staples the DMG. This uploads artifacts to Apple’s notarization service, but publishes nothing to users.

Only Deno receives the JIT entitlement; only the PyInstaller helper receives library-validation relaxation for its bundled Python runtime. The UI application receives neither entitlement. Verify these signed helpers on clean machines before release.

## Engine channel

Clients fetch a small JSON envelope with two base64 strings: `payload` and `signature`. The signature covers the exact decoded payload bytes. The payload contains `version`, monotonic `sequence`, `architecture`, `minimumAppBuild`, HTTPS artifact `url`, `sha256`, and `size`. Archives contain `MacOS`, `Frameworks`, and `Resources` at their root.

Create local channel artifacts from a publicly packaged app:

```sh
python3 Scripts/create_engine_release.py \
  --app artifacts/Harbor.app --output build/engine-release \
  --url https://YOUR-RELEASE-HOST/engines-arm64.zip \
  --sequence 1 --key-file /secure/location/engine.private-key
```

The private key file contains the base64 representation of a 32-byte Ed25519 private key. Provision it outside the repository; the script prints only the public key. Verify that it matches the embedded app key before publishing. The script creates `engines.zip` and `manifest.json`; publishing them is a separate deployment action.

Publish complete tested sets, never arbitrary upstream newest binaries. An upstream release should trigger a dependency-lock update and CI run, followed by signed channel artifact creation. Keep the last known working release accessible. Update active pointers atomically; preserve installed versions because running jobs remain pinned to them.

## Release verification

Verify clean installation, Gatekeeper, real Apple silicon and Intel downloads, browser permission denial, updated-engine startup, corruption rejection, interrupted staging, and rollback. Test signed channel installation against a staging channel before enabling it publicly. Repository tests currently cover manifest cryptography and compatibility, hash mismatch, coordinator behavior, and real local engine transfers; Apple notarization and a live signed update round trip require publisher credentials and are not claimed as completed.
