# Native UI Guidance

[Context index](README.md) · [Testing](TESTING.md)

## Current Screens

- [HarborApp](../Sources/Harbor/HarborApp.swift) provides the window, Settings scene, Command-N action, activation handling, and quit coordination.
- [MainView](../Sources/Harbor/MainView.swift) uses a NavigationSplitView with Downloads, Completed, and Failed collections. It includes search, progress rows, a detail inspector, a clipboard suggestion banner, and file actions.
- [AddDownloadView](../Sources/Harbor/AddDownloadView.swift) owns temporary input, inspection results, selections, preset, and destination. It also contains the browser-consent sheet.
- [SettingsView](../Sources/Harbor/SettingsView.swift) exposes destination, format, direct-file connection count, clipboard preferences, and engine update controls.

The [AppModel](../Sources/Harbor/AppModel.swift) is the main-actor observable source of app state. Views bind to it and keep transient presentation state local. Core job state and service work belong to the coordinator and adapters, not view-owned processes.

## Interaction Contracts

Keep downloading understandable through titles, thumbnails, duration, format descriptions, status, and destination controls. Users should not need executable paths or shell flags. Use native SwiftUI/AppKit controls and system styling appropriate for the macOS 14 deployment target.

Playlist previews start unselected; unavailable items cannot become jobs, and an empty selection disables downloading. Format choices reflect capabilities, including audio-only sources. Keep indeterminate progress for missing totals and file preparation. Do not imply completion until the finalized output exists.

Clipboard suggestions require the preference and an explicit Add action before inspection. Browser access explains the selected browser/profile and scope and offers a dismissal path. Destination errors provide a useful retry or folder-selection action. History removal describes retained files accurately.

Closing a window and quitting the app have different job behavior; preserve the lifecycle described in [PROJECT.md](PROJECT.md). A redesign should be scoped to the requested change while retaining these behavior contracts.

## Accessibility and Visual Checks

Preserve useful labels, keyboard shortcuts, focus behavior, and stable UI-test identifiers when changing controls. Give icon-only actions accessible names; do not encode state only by color. Check long titles, empty results, unavailable items, failure messages, and narrow windows for clipping.

Build and inspect the actual changed app for visual work. Capture screenshots for relevant states and note the app configuration used. Native UI tests cover specific interactions, not overall visual quality or a full VoiceOver audit. Consult [the validation record](../docs/VALIDATION.md) before claiming accessibility or prolonged-use coverage.
