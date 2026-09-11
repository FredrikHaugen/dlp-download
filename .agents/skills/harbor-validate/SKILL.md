---
name: harbor-validate
description: Build and validate Harbor changes using core, local engine, native UI, and bundled-artifact checks. Use for Harbor testing, regression investigation, or validation requests; documentation-only edits need link and instruction checks rather than app tests.
---

# Validate Harbor

Read the repository [testing guide](../../../.codex/TESTING.md) and use the [workflow guide](../../../.codex/WORKFLOW.md) for build prerequisites. Run commands from the repository root. Inspect current changes and choose checks for affected behavior; do not rebuild every dependency for an unrelated Swift edit.

## Select and Run Checks

- Use Swift Testing for core state, parsing, persistence, and process behavior. Confirm the final executed/skipped summary, including a nonzero count for any filtered run.
- Use `Scripts/integration_test.py` for routing, transfer, playlist identity, conversion, or resume changes. It generates local media, supplies fixture environment variables, and owns the loopback server lifetime. Plain `swift test` can skip these cases.
- Add `--ui` for changed interactions or lifecycle; use `--ui-only` when only that layer needs repeating. UI tests require the generated Xcode project and embedded engines, and use isolated history and destination storage.
- For engine embedding or packaging changes, build the intended configuration and pass that exact app's `Contents` directory to the integration runner. This selects core integration engines, not the app launched by XCTest UI automation.
- For documentation-only changes, check claims, relative links, reachability from `AGENTS.md`, skill frontmatter where applicable, and whitespace. Application builds are unnecessary.

Keep a failing regression as evidence, fix the cause, and rerun the affected checks. Distinguish setup failures from application failures. Use existing fixture infrastructure and add regression coverage when behavior warrants it; avoid personal browser profiles and third-party media for routine tests.

For visual work, inspect the actual changed app using the available native/UI tooling, following [UI.md](../../../.codex/UI.md). Record unavailable manual checks accurately. Keep `HARBOR_UI_TEST_ROOT` isolation limited to Debug; Release ignores it. If a manual fixture server is started, stop the owned process afterward.

## Report Evidence

Report commands, outcome, executed/skipped tests, app or engine path, configuration, architecture, and relevant limitations. Include screenshot or log locations when they support the requested change. Use [VALIDATION.md](../../../docs/VALIDATION.md) as the canonical dated record when updating repository evidence.

A configured CI workflow is not a completed remote run. A passing build or ad-hoc signature is not notarization, clean-machine compatibility, or a live signed update acceptance test. Do not replace historical evidence with a stronger claim than the checks performed support.
