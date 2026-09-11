# Development Workflow

[Context index](README.md) · [Contributor guide](../AGENTS.md)

## Start a Change

Read the task's relevant guides, inspect `git status --short`, and identify existing edits before changing files. Use `rg` and source reads to confirm current behavior. Preserve unrelated work and keep the change within the requested product scope. Follow the established Swift/Python indentation and naming conventions in `AGENTS.md`.

## Build Locally

Run from the repository root. Prerequisites are Xcode 16+ with Swift 6, XcodeGen, and Python 3.12+. Build on the intended CPU architecture so bundled helpers match the app. Engines do not come from a system-wide Homebrew runtime.

```sh
python3 Scripts/bootstrap_engines.py
xcodegen generate
xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/xcode build
open build/xcode/Build/Products/Debug/Harbor.app
```

Bootstrap downloads pinned inputs and builds portable engines; it is needed for initial setup or changed dependencies, not every Swift edit. The Xcode post-build phase embeds engines automatically.

Edit [project.yml](../project.yml) for target configuration and regenerate the Xcode project. [Package.swift](../Package.swift) defines the core package and its tests; it does not build the SwiftUI application or native UI test target. Keep generated-project changes consistent with the YAML source.

## Generated Outputs

`Vendor/` contains cached inputs, source builds, and the assembled EngineSet. `build/` contains fixtures, logs, generated Info.plist, Swift build output, and Xcode products. `artifacts/` contains packaged apps and DMGs. These directories are ignored. Treat [dependencies.lock.json](../dependencies.lock.json) as reviewed source, not disposable cache data.

## Finish a Change

Choose checks from [TESTING.md](TESTING.md) based on affected behavior. Record commands, results, skipped work, and material limitations. A successful build alone does not validate downloads or UI behavior. Review the diff and whitespace; for new documents also check their links because untracked files are not covered by a normal `git diff --check`.

Update affected context and established decisions when behavior changes. Keep reproducible evidence in [the validation record](../docs/VALIDATION.md) and generated logs in ignored output directories. Describe PR behavior and validation for a reviewer who has not read the conversation; include screenshots for UI changes.

For local development packaging or publisher release work, follow [RELEASING.md](../docs/RELEASING.md) and the [engine maintenance skill](../.agents/skills/harbor-engine-maintenance/SKILL.md). Public packaging includes an Apple notarization upload; release publication is a separate external action. Run those actions only within the user's authorized task.
