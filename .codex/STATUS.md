# Project Status

Snapshot: 2026-09-11. This summarizes current source and the existing validation record; it is not evidence of a new test run.

[Context index](README.md) · [Validation evidence](../docs/VALIDATION.md)

## Implemented Baseline

The repository contains a runnable SwiftUI macOS app with media/direct download engines, playlist selection, format preparation, persistent queue/history, cancellation and recovery, browser-consent UI, clipboard preferences, and verified-update machinery. Development packaging produces an ad-hoc-signed app and DMG. Detailed behavior is in [PROJECT.md](PROJECT.md).

The dated validation record reports passing core/real-engine integration tests, native UI tests, Debug and Release builds, bundled-engine checks, and development packaging on Apple silicon. It records exact counts and available log paths. Generated logs and artifacts are ignored and may need regeneration in another checkout. See [TESTING.md](TESTING.md) for reproducible commands.

## Public-Release Follow-ups

| Area | Remaining work |
| --- | --- |
| Publisher configuration | Provide the HTTPS channel, public verification key, and signing Team ID; the current fields are empty |
| Signing and installation | Developer ID signing, notarization, and clean-machine Gatekeeper acceptance |
| Dependency redistribution | Complete the dependency license/source audit; generated `releaseReady` remains false |
| Update acceptance | Exercise a live signed staging-channel install, failure, and rollback round trip |
| Hardware and OS | Real Intel and macOS 14 validation; configured CI alone is not execution evidence |
| Browser access | Permission denial, platform prompts, and authenticated sources using explicitly authorized test profiles |
| Sustained UX | Extended sleep/wake, prolonged use, and a full VoiceOver audit |

Follow [release procedures](../docs/RELEASING.md) for prerequisites and evidence. These follow-ups require different environments or publisher inputs; they are not all addressed by rerunning unit tests.

## Deferred Product Work

Torrents/magnets, live recording, iOS, browser extensions, and cloud processing remain outside the implemented baseline. Harbor is a provisional name, and no app source license has been selected. Choose work from the current user request rather than treating this list as automatic authorization to expand the product.

## Updating This Snapshot

Refresh the date and affected rows when status changes. Link new evidence from the canonical validation record. Keep implementation progress, configuration readiness, and executed checks distinct. Do not carry temporary dirty-tree listings, local credentials, or personal information into this document.
