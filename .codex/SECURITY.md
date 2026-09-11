# Security and Data Boundaries

[Context index](README.md) · [Architecture](ARCHITECTURE.md)

This guide records implementation boundaries and review points. It is not a completed security audit or a release certification.

## Input and Subprocesses

[LinkRouter](../Sources/HarborCore/LinkRouter.swift) parses complete HTTP(S) URLs, rejects embedded credentials, and recognizes deferred magnet/torrent inputs. Network response headers inform routing; a filename extension is not sufficient evidence of content type. Parsing clipboard text should not itself trigger network inspection.

[ProcessRunner](../Sources/HarborCore/ProcessRunner.swift) executes explicit executable URLs with argument arrays, a controlled environment, and no interactive stdin. Preserve this boundary when adding options; never interpolate user input into a shell command. It drains stdout and stderr concurrently and propagates cancellation to descendants with PID identity checks. Keep bounded output handling and timeout behavior when changing process plumbing.

[DirectEngine](../Sources/HarborCore/DirectEngine.swift) starts a private aria2 instance with a random RPC secret, loopback binding, and DHT/peer exchange disabled. Preserve certificate verification and isolation between jobs. Avoid logging RPC tokens or raw subprocess arguments containing private data.

## Browser Access and Local Data

Browser sign-in access requires explicit consent for a job or batch. Consent is held in coordinator memory and cleared when its task finishes; it is not stored in history. Do not add implicit cookie retries or persist cookie exports. Permission-denied browser access must remain a user-visible failure. Browser profiles may contain sign-in data for multiple sites; keep that scope clear in the UI.

Production history lives under `~/Library/Application Support/Harbor/Downloads.store`; preferences live in the app's UserDefaults domain. Stored original URLs can include private tokens. Redact sensitive URL components and profile information before sharing diagnostics, logs, or screenshots. Use fixture data for routine tests and preserve existing personal history.

## Files and Updates

Downloads stage inside their selected destination. Preserve filename sanitization, checks against unsafe staging links and escaped output paths, nonempty-file validation, and final moves that fail on existing filenames. Removing history keeps files. Resume requires matching strong validators and range support; partial-file cleanup is limited to the job's own output.

[EngineUpdater](../Sources/HarborCore/EngineUpdater.swift) verifies the signed payload bytes before trusting manifest fields. Keep HTTPS, signature, compatibility, sequence, size/hash, archive-path, symlink, code-signature, and startup checks. Stage outside the app bundle, activate atomically, and preserve prior engine versions for rollback and running jobs.

Dependency input checks and publisher update signatures serve separate purposes. Follow [RELEASING.md](../docs/RELEASING.md) for their actual formats, trust roots, signing entitlements, and release gates. Store no private signing keys, credentials, or exported cookies in this repository. Do not mark `releaseReady` true merely because a development build passes. The current channel configuration is deliberately empty.
