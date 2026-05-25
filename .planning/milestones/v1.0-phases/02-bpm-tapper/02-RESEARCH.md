# Phase 02 - BPM Tapper Research

**Phase:** 02 - BPM Tapper
**Researched:** 2026-05-04
**Mode:** Inline GSD research
**Confidence:** HIGH for estimator, persistence, registry integration; MEDIUM for exact SwiftUI focus polish until execution verifies the running app.

## Research Question

What needs to be known to plan Phase 2 well?

Phase 2 is intentionally low-risk compared with conversion, recording, and downloader work, but it is the first real tool. The plan should prove that a focused production utility can plug into the Phase 1 registry without growing shell coupling, while keeping tap math and local history testable outside SwiftUI.

## Relevant Source Context

| Area | Current state | Planning implication |
|------|---------------|----------------------|
| Feature boundary | `ToolFeature` exposes metadata and `makeView(context:) -> AnyView`. | BPM should register as a normal feature, not as a hard-coded `AppShellView` case. |
| Composition root | `AppComposition.make()` builds a static `[any ToolFeature]` array with `DevToolFeature()`. | BPM registration should add `BPMTapperFeature()` to this array and update `registeredToolCount`. |
| App shell | `AppShellView` renders selected features from `registry.features`. | No shell navigation work should be necessary beyond registration. |
| Shared services | `ToolContext` provides settings, output inbox, job runner, file actions, and diagnostics. | BPM does not produce files or run jobs; feature-local history can use a small store rather than the output inbox. |
| Tests | `AppCoreTests` cover registry, settings, output inbox, jobs, and context fakes. | BPM estimator/history tests should live in a new focused test target so UI work does not dilute AppCore. |

## Recommended Technical Approach

### Package and Module Shape

Add a separate `FeatureBPMTapper` library target that depends on `AppCore`, plus `FeatureBPMTapperTests`. The executable target should depend on both `AppCore` and `FeatureBPMTapper`, then `AppComposition` can import `FeatureBPMTapper` and register `BPMTapperFeature()`.

This keeps the first real tool isolated enough to validate the architecture, while avoiding a large refactor into many feature targets before the app needs them.

### Estimator Model

Use a pure Swift `TempoEstimator` with an explicit configuration:

- `recentIntervalLimit = 4`
- `pauseResetThreshold` around `2.5` seconds
- `minimumInterval` around `0.24` seconds
- `maximumInterval` around `2.0` seconds
- outlier tolerance around `35%` from the current recent average once there is enough history

The estimator should return a structured state instead of forcing the view to infer behavior:

- tap count
- accepted interval count
- optional raw BPM
- status: idle / waitingForSecondTap / firstEstimate / stableEstimate / longPauseReset / outlierIgnored
- whether the last interval was accepted

The exact numeric thresholds are implementation discretion, but tests must prove:

- first tap has no fake BPM
- second tap produces the first estimate
- last four intervals drive the estimate
- long pauses reset stale runs
- obvious outliers are ignored while the run stays alive

### Adjustment Modes

Use a small `BPMAdjustment` enum with `original`, `halfTime`, and `doubleTime`. Applying the adjustment should be deterministic and test-covered:

- original: `bpm`
- half-time: `bpm / 2`
- double-time: `bpm * 2`

The view model should keep raw tapped BPM and displayed BPM separate so saved history can record the adjustment context.

### UI and Focus

SwiftUI can satisfy the Phase 2 interaction contract:

- a large focused tap surface
- `.focusable()` and `@FocusState` for initial focus
- `.onKeyPress(.space)` for tap
- `.onKeyPress(.escape)` for reset
- `Picker` with `.segmented` style for adjustment modes
- native buttons for copy, save, reset, row copy, and clear history

The keyboard behavior is scoped to the active BPM surface; do not add global event monitors or app-wide shortcuts in Phase 2.

### History Persistence

Use a feature-local `BPMHistoryStore` protocol and a `UserDefaultsBPMHistoryStore` concrete adapter. A history entry should contain:

- `id`
- `bpm`
- `timestamp`
- `adjustment`
- `rawTappedBPM`

The store should support list, append, and clear-all. Individual row deletion is intentionally out of scope.

### Clipboard

Use a small `BPMClipboardWriting` protocol with an AppKit-backed pasteboard implementation in the feature target. The only copied string should be the displayed plain number, such as `128`, with no `BPM`, timestamp, or mode text.

## Plan Slices

| Plan | Purpose | Key files |
|------|---------|-----------|
| 02-01 | Tempo estimator, adjustment domain, package target, tests. | `Package.swift`, `Sources/FeatureBPMTapper/TempoEstimator.swift`, `Sources/FeatureBPMTapper/BPMAdjustment.swift`, `Tests/FeatureBPMTapperTests/*` |
| 02-02 | Registered BPM feature, focused tap UI, live readout, keyboard tap/reset. | `Sources/FeatureBPMTapper/BPMTapperFeature.swift`, `BPMTapperView.swift`, `BPMTapperViewModel.swift`, `Sources/OutsideCubaseHub/AppComposition.swift` |
| 02-03 | History persistence, copy/save, half/double actions, clear history, confirmations. | `Sources/FeatureBPMTapper/BPMHistoryStore.swift`, `UserDefaultsBPMHistoryStore.swift`, view model/view updates, action tests |

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| SwiftUI keyboard shortcuts become global or fire in the wrong tool. | User taps tempo accidentally outside the BPM surface. | Scope space and escape handling to the focused tap surface only; test view model behavior separately and manually smoke the running app. |
| Estimator feels jumpy. | BPM tool is less useful than the website it replaces. | Average recent intervals, ignore obvious outliers, show first estimate after two taps, stabilize after enough intervals. |
| History becomes a pseudo-output workflow. | Output inbox semantics become muddled. | Keep BPM history feature-local and do not mark BPM as `producesFiles`. |
| Clipboard output is too rich. | Pasting into Cubase/notes becomes annoying. | Copy only a rounded/displayed plain number. |
| Feature logic leaks into app shell. | Phase 1 architecture is not validated. | Keep BPM in `FeatureBPMTapper`; only `AppComposition` imports/registers it. |

## Validation Architecture

| Dimension | Strategy |
|-----------|----------|
| Domain tests | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FeatureBPMTapperTests` should cover estimator, adjustment, history store, and view model actions. |
| Full regression | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` should keep AppCore and feature tests green. |
| Source scans | `rg -n "URLSession|Network|yt-dlp|FFmpeg|CoreAudio|ScreenCaptureKit" Sources/FeatureBPMTapper` should return no matches for this offline tool. |
| Registry check | `Sources/OutsideCubaseHub/AppComposition.swift` should contain `BPMTapperFeature()` and the sidebar should render it through the existing registry path. |
| Manual smoke | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run OutsideCubaseHub` should launch, show `BPM Tapper`, accept mouse/space taps, reset with Escape, and keep Output Inbox secondary. |

## Research Complete

Phase 2 is ready to plan as three sequential executable plans: estimator/domain, UI registration, and history/actions polish.
