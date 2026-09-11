---
name: harbor-engine-maintenance
description: Maintain Harbor's pinned download engines, portable builds, embedding, and local release artifacts. Use when updating yt-dlp, Deno, aria2, FFmpeg, LAME, or engine packaging; ordinary SwiftUI changes do not need this workflow.
---

# Maintain Harbor Engines

Read [RELEASING.md](../../../docs/RELEASING.md) for canonical release requirements and [SECURITY.md](../../../.codex/SECURITY.md) for execution and update boundaries. Inspect the requested component, current pins, lock entries, and local changes before editing. Keep the task limited to the authorized dependency or artifact work.

## Update Inputs and Build

1. Inspect [bootstrap_engines.py](../../../Scripts/bootstrap_engines.py), [build_portable_media.py](../../../Scripts/build_portable_media.py), and [dependencies.lock.json](../../../dependencies.lock.json). Versions and downloads are defined by the scripts; the lock records downloaded input hashes. An engine version identifier and the updated lock must describe the same assembled set.
2. For a version change, verify the intended upstream release, artifact/source URL, digest evidence, and compatibility using official project sources. Preserve checksum enforcement. A changed checksum is a failure to investigate, not a reason to disable verification or silently accept new bytes. Update relevant lock entries deliberately after establishing provenance.
3. Bootstrap on the intended CPU architecture. Check the generated set's component versions and source/recipe provenance. Preserve macOS 14 compatibility and portable runtime dependencies. Separate ARM and Intel builds require separate validation.
4. Regenerate the Xcode project if configuration changed, build the app, and run local engine integration checks against the exact embedded set using the [testing guide](../../../.codex/TESTING.md). Review [embed_engines.py](../../../Scripts/embed_engines.py) when bundle layout or signing changes.

Bootstrap currently emits `releaseReady: false`. Do not flip it to bypass an incomplete license/source audit or a packaging error. Use the release guide for actual redistribution requirements; do not infer them solely from an upstream project's top-level license name.

## Package Within the Requested Scope

Development packaging follows a Release build and uses [package_app.py](../../../Scripts/package_app.py) with `--development`. Verify the resulting artifact and report its ad-hoc signing status. Keep generated sets, logs, and DMGs in their existing ignored directories.

For explicitly requested publisher work, use the configured signing identity, Keychain notary profile, and public engine channel described in the release guide. Keep private keys and credentials outside the repository. Public packaging uploads to Apple; [create_engine_release.py](../../../Scripts/create_engine_release.py) creates local signed channel artifacts, and publication is separate. Run external actions only when covered by the user's authorization.

Preserve the updater's signature, hash, compatibility, sequence, archive, and code-signature checks. Test complete sets before activation; keep previous versions available for rollback and running jobs. The [upstream workflow](../../../.github/workflows/upstream.yml) reports availability and does not authorize automatic dependency changes or publication.

## Completion Evidence

Summarize changed pins and hashes, source provenance, architecture/minimum-OS checks, exact bundled-engine results, packaging status, and remaining release gates. Update relevant repository guides and dated validation evidence when warranted. If publisher inputs or external test environments are missing, finish the authorized local work and identify the remaining requirement without claiming public-release readiness.
