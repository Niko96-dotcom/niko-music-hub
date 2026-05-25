# Phase 02 - Pattern Map

**Phase:** 02 - BPM Tapper
**Created:** 2026-05-04
**Mode:** Inline GSD pattern mapping

## Purpose

This map connects planned Phase 2 files to existing code patterns so execution can reuse the established architecture instead of inventing a parallel app shape.

## Planned Files and Closest Analogs

| Planned file | Role | Closest existing analog | Pattern to copy |
|--------------|------|-------------------------|-----------------|
| `Package.swift` | Add feature target and tests. | Existing AppCore / OutsideCubaseHub / AppCoreTests target declarations. | Keep SwiftPM simple; add `FeatureBPMTapper` as a library target and `FeatureBPMTapperTests` as a test target. |
| `Sources/FeatureBPMTapper/BPMTapperFeature.swift` | ToolFeature registration adapter. | `Sources/OutsideCubaseHub/DevTool/DevToolFeature.swift` | Expose `metadata` and `makeView(context:) -> AnyView`; avoid shell-specific state. |
| `Sources/FeatureBPMTapper/BPMTapperView.swift` | Native SwiftUI tool surface. | `Sources/OutsideCubaseHub/DevTool/DevToolFeature.swift` and `Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift` | Top-leading compact layout, native controls, explicit 12/13/16/40px typography, no landing page. |
| `Sources/FeatureBPMTapper/BPMTapperViewModel.swift` | UI-facing state/use case boundary. | `Sources/OutsideCubaseHub/DevTool/DevToolFeature.swift` for view state, but keep math separate. | View model owns state transitions and calls pure estimator/history/clipboard collaborators. |
| `Sources/FeatureBPMTapper/TempoEstimator.swift` | Pure tap math. | `Sources/AppCore/Jobs/Job.swift` for small value/state types. | Use Sendable value types and XCTest-friendly methods; no SwiftUI/AppKit imports. |
| `Sources/FeatureBPMTapper/BPMAdjustment.swift` | Deterministic half/double display logic. | `Sources/AppCore/Settings/AudioPreset.swift` | Small enum/value type with defaults and Codable/Sendable conformance if saved in history. |
| `Sources/FeatureBPMTapper/BPMHistoryStore.swift` | Feature-local persistence port. | `Sources/AppCore/Services/SettingsStore.swift` and `OutputInboxStore.swift` | Define a tiny protocol with list/add/clear methods. |
| `Sources/FeatureBPMTapper/UserDefaultsBPMHistoryStore.swift` | Feature-local persistence adapter. | `Sources/AppCore/Settings/UserDefaultsSettingsStore.swift` | Injectable `UserDefaults`, JSON encoding, deterministic tests. |
| `Tests/FeatureBPMTapperTests/*.swift` | Focused feature tests. | `Tests/AppCoreTests/SettingsStoreTests.swift`, `FeatureRegistryTests.swift` | Small XCTest cases, fakes for stores/clipboard, explicit expected values. |
| `Sources/OutsideCubaseHub/AppComposition.swift` | Startup registration. | Current `DevToolFeature()` registration. | Import feature module and append `BPMTapperFeature()` to the static features array. |

## Existing Code Excerpts to Preserve

### ToolFeature View Factory

Current feature boundary:

```swift
public protocol ToolFeature: Sendable {
    var metadata: ToolMetadata { get }

    @MainActor
    func makeView(context: ToolContext) -> AnyView
}
```

BPM should implement this exactly and return the BPM view from `makeView(context:)`.

### Static Composition Root

Current registration shape:

```swift
let features: [any ToolFeature] = [
    DevToolFeature()
]
let registry = try! ToolRegistry(features: features)
let context = ToolContext(
    registeredToolCount: features.count,
    settingsStore: UserDefaultsSettingsStore(),
    outputInboxStore: JSONOutputInboxStore(storageURL: AppPaths.outputInboxStoreURL()),
    jobRunner: JobRunner(),
    fileActions: AppKitFileActions(),
    diagnostics: ConsoleDiagnostics()
)
```

Phase 2 should only add the BPM feature to this array and keep `registeredToolCount: features.count`.

### UserDefaults Adapter Shape

Current settings store pattern:

```swift
public struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key: String

    public func loadSettings() throws -> AppSettings {
        guard let data = userDefaults.data(forKey: key) else {
            return .default
        }

        return try JSONDecoder().decode(AppSettings.self, from: data)
    }
}
```

`UserDefaultsBPMHistoryStore` should mirror this style with an injectable suite/key and JSON encoding.

## Data Flow

```text
Tap surface click / Space
    -> BPMTapperViewModel.recordTap(at:)
    -> TempoEstimator.tap(at:)
    -> raw BPM + status
    -> BPMAdjustment.apply(to:)
    -> displayed BPM
    -> Copy/Save actions
    -> BPMClipboardWriting / BPMHistoryStore
```

## Plan Dependency Notes

| Plan | Dependency reason |
|------|-------------------|
| 02-01 | First because it creates the feature target and pure domain types. |
| 02-02 | Depends on 02-01 because the UI imports `TempoEstimator` and `BPMAdjustment`. |
| 02-03 | Depends on 02-02 because history/copy/action polish updates the view model and view created in the UI plan. |

## Anti-Patterns to Avoid

- Do not add a hard-coded BPM case to `AppShellView`.
- Do not put estimator math inside SwiftUI button actions.
- Do not use the shared Output Inbox for saved BPM history.
- Do not add global keyboard monitors for Space or Escape.
- Do not add network/helper imports to `FeatureBPMTapper`.
- Do not copy `128 BPM`; copy only `128` or the displayed numeric string.
