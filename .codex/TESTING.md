# Testing and Evidence

[Context index](README.md) · [Validation skill](../.agents/skills/harbor-validate/SKILL.md)

## Choose the Smallest Relevant Check

Run commands from the repository root after the prerequisites in [WORKFLOW.md](WORKFLOW.md).

| Change | Command or check |
| --- | --- |
| Core values, state, parsing, or persistence | `swift test --scratch-path build/swift-package` |
| Routing, transfer, resume, progress, or conversion | `python3 Scripts/integration_test.py` |
| SwiftUI interaction or application lifecycle | `python3 Scripts/integration_test.py --ui` |
| Only native UI checks need repeating | `python3 Scripts/integration_test.py --ui-only` |
| Engine embedding or release artifact | Pass the exact app's `Contents` directory to the integration script |
| Documentation or instruction-only skills | Verify claims, local links, discovery paths, frontmatter, and whitespace |

For example, after building Release:

```sh
python3 Scripts/integration_test.py build/xcode/Build/Products/Release/Harbor.app/Contents
```

The optional directory selects engines for the core integration checks. UI tests launch the Xcode-built test app; passing another directory does not make UI tests exercise that other app. Report the artifact each check actually used.

## Test Layers

[CoreTests.swift](../Tests/HarborCoreTests/CoreTests.swift) covers URL input, filename/output safety, metadata/progress, process pipes and cancellation, and persistence. [QueueAndUpdateTests.swift](../Tests/HarborCoreTests/QueueAndUpdateTests.swift) covers queue behavior, shutdown, retry, and update rejection. These use Swift Testing and descriptive `@Test` functions.

[IntegrationTests.swift](../Tests/HarborCoreTests/IntegrationTests.swift) uses real helpers for local routing, playlist extraction, transfers, formats, and resume. The [integration runner](../Scripts/integration_test.py) generates a short media fixture, starts the [loopback server](../Scripts/fixture_server.py), sets `HARBOR_FIXTURE_URL` and `HARBOR_ENGINE_ROOT`, and stops the server on exit. Plain `swift test` skips fixture-dependent cases when their environment is absent. Inspect the final Swift Testing executed/skipped summary; an XCTest summary with zero tests is not the complete Swift Testing result.

[DownloadFlowTests.swift](../Tests/HarborUITests/DownloadFlowTests.swift) uses XCTest for paste/inspect/download/history recovery and explicit playlist selection. Debug builds accept `HARBOR_UI_TEST_ROOT` to isolate history, preferences, and destination; Release ignores that variable. The runner supplies `build/ui-fixture-url` for UI tests. Avoid launching isolated UI tests through a bare Xcode command before arranging fixtures.

## Verification Expectations

Add meaningful regression coverage for changed runtime behavior. Exercise failure and cancellation paths when ownership or asynchronous state changes. For persisted model changes, verify older payload handling as well as new round trips. No numeric coverage threshold is configured. Documentation-only edits do not require app builds.

Use generated media and local destinations. Browser cookies, authenticated websites, and user download history are not default test fixtures. Manual UI checks should cover the changed state, keyboard access, and window resizing; use [UI.md](UI.md) for expectations.

If checks fail, retain the failing output and distinguish missing engines, missing fixture variables, permission problems, compile failures, and behavioral regressions. Fix the cause before rerunning the affected layer. Do not weaken verification to obtain a pass.

## Evidence Limits

[CI](../.github/workflows/ci.yml) defines separate ARM and Intel jobs, a Release build, bundled-engine checks, and development packaging. A configured workflow is not a completed run. Host architecture, deployment target, actual tested OS, and signing status are separate facts. [VALIDATION.md](../docs/VALIDATION.md) records dated results and outstanding manual checks; update it only with evidence from work actually performed.
