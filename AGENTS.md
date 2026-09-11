# Repository Guidelines

## Project Structure & Module Organization

- `Sources/Harbor/`: SwiftUI screens, app lifecycle, and AppKit integration.
- `Sources/HarborCore/`: download coordination, engine adapters, routing, SwiftData persistence, and verified updates.
- `Tests/HarborCoreTests/` and `Tests/HarborUITests/`: core/integration tests and native UI tests.
- `Resources/`: entitlements and update-channel configuration. `Scripts/`: engine bootstrapping, fixtures, and packaging.
- `project.yml` defines the Xcode project; regenerate `Harbor.xcodeproj` after configuration changes. `Package.swift` defines the core package.
- `Vendor/`, `build/`, and `artifacts/` are generated and ignored. Release guidance and validation evidence belong in `docs/`.

## Build, Test, and Development Commands

Use Xcode 16+ with Swift 6, XcodeGen, and Python 3.12+. Target macOS 14 or later.

- `python3 Scripts/bootstrap_engines.py`: fetch pinned inputs and assemble portable engines.
- `xcodegen generate`: regenerate the Xcode project.
- Build the app:

  ```sh
  xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath build/xcode build
  ```

- `open build/xcode/Build/Products/Debug/Harbor.app`: launch locally.
- `swift test --scratch-path build/swift-package`: run unit tests; fixture-dependent integration tests are skipped.
- `python3 Scripts/integration_test.py --ui`: run core, local engine, and native UI tests.

## Coding Style & Naming Conventions

Use four-space indentation for Swift and Python, and two spaces for YAML. Name types in `UpperCamelCase` and functions/properties in `lowerCamelCase`; follow existing `Engine`, `View`, and `Tests` suffixes. No repository formatter or linter is configured; match surrounding code and avoid unrelated reformatting.

Keep process execution outside views and the main actor. Preserve coordinator ownership of scheduling, Sendable domain values, and explicit engine interfaces.

## Testing Guidelines

Use Swift Testing (`@Test`) for core behavior and XCTest for UI flows. Choose descriptive behavior names; XCTest methods begin with `test`. Add regression coverage for changed behavior, especially cancellation, recovery, routing, and update integrity. Use generated media and loopback fixtures instead of personal browser profiles or external downloads. No numeric coverage threshold is configured. CI validates ARM and Intel builds separately.

## Commit & Pull Request Guidelines

History currently contains one imperative subject: “Implement core download functionality with persistent and in-memory job storage.” Continue concise, imperative subjects; no Conventional Commits convention is established. Keep commits focused. PRs should explain behavior changes, link relevant issues, report validation and limitations, and include screenshots for UI changes.

## Security & Configuration

Preserve `dependencies.lock.json` verification and argument-array process execution. Never commit credentials, private signing keys, or cookie exports. Follow `docs/RELEASING.md` for public packaging and signed engine updates.

## Agent Context

Start with the [agent context index](.codex/README.md) and [project context](.codex/PROJECT.md), then read the task-specific guides linked there. Use [status](.codex/STATUS.md) for dated readiness and remaining work. Keep these guides current when commands, architecture, or accepted behavior change.

Repository skills: [Harbor validation](.agents/skills/harbor-validate/SKILL.md) and [engine maintenance](.agents/skills/harbor-engine-maintenance/SKILL.md). They reuse existing scripts and canonical release/validation documentation.
