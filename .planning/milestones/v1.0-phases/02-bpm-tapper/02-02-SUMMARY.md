---
phase: 02-bpm-tapper
plan: "02"
subsystem: ui
tags: [swiftui, toolfeature, bpm, focus, xctest]
requires:
  - phase: 02-bpm-tapper
    provides: FeatureBPMTapper target, TempoEstimator, and BPMAdjustment
provides:
  - BPMTapperFeature registration through AppComposition
  - Focused SwiftUI tap surface with mouse tap, Space tap, and Escape reset
  - BPMTapperViewModel state bridge over TempoEstimator
  - View model tests for tap, reset, pause, and outlier behavior
affects: [bpm-history, bpm-actions, app-composition]
tech-stack:
  added: [SwiftUI focused tap surface, ObservableObject view model]
  patterns: [feature registration through ToolFeature, view model over pure estimator, scoped keyboard handling]
key-files:
  created:
    - Sources/FeatureBPMTapper/BPMTapperFeature.swift
    - Sources/FeatureBPMTapper/BPMTapperView.swift
    - Sources/FeatureBPMTapper/BPMTapperViewModel.swift
    - Tests/FeatureBPMTapperTests/BPMTapperViewModelTests.swift
  modified:
    - Package.swift
    - Sources/OutsideCubaseHub/AppComposition.swift
key-decisions:
  - "BPM Tapper is registered only through ToolFeature/AppComposition; the app shell remains generic."
  - "Space and Escape are handled on the focused tap surface rather than through global monitors."
  - "The UI shows no fake BPM after one tap and enables deterministic state tests through BPMTapperViewModel."
patterns-established:
  - "Feature views are created by feature factories and can own their own StateObject view model."
  - "SwiftUI key handling stays attached to the focused tool control."
requirements-completed: ["BPM-01", "BPM-02", "BPM-03", "BPM-05"]
duration: 4 min
completed: 2026-05-04
---

# Phase 02 Plan 02: BPM Tapper UI Summary

**Registered BPM Tapper tool with a focused native SwiftUI tap surface and tested live tempo state**

## Performance

- **Duration:** 4 min
- **Started:** 2026-05-04T14:03:42Z
- **Completed:** 2026-05-04T14:07:57Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- Wired `FeatureBPMTapper` into the executable target and registered `BPMTapperFeature()` after the developer tool.
- Built a compact top-leading BPM surface with a 40px readout, stable 320x180 minimum tap pad, `Tap Tempo`, and visible `Reset Taps`.
- Scoped Space and Escape key handling to the focusable tap surface.
- Added deterministic view model tests covering initial state, first estimate, reset, long pause, and outlier behavior.

## Task Commits

Each task was committed atomically:

1. **Task 1: Register BPMTapperFeature through Package and AppComposition** - `5cd78a4` (feat)
2. **Task 2: Build BPMTapperViewModel and focused tap surface** - `19d13ae` (feat)
3. **Task 3: Cover view model tap, reset, and pause behavior** - `992e389` (test)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `Package.swift` - Adds `FeatureBPMTapper` as an executable dependency.
- `Sources/OutsideCubaseHub/AppComposition.swift` - Imports and registers `BPMTapperFeature()`.
- `Sources/FeatureBPMTapper/BPMTapperFeature.swift` - Provides ToolFeature metadata and view factory.
- `Sources/FeatureBPMTapper/BPMTapperView.swift` - Renders BPM readout, tap surface, focus handling, and reset.
- `Sources/FeatureBPMTapper/BPMTapperViewModel.swift` - Maps tap estimates into user-facing UI state.
- `Tests/FeatureBPMTapperTests/BPMTapperViewModelTests.swift` - Covers view model tap lifecycle and edge states.

## Decisions Made

- Kept `AppShellView` and `ToolSidebarView` unchanged so the feature registry remains the only integration point.
- Used `@FocusState`, `.focusable()`, and `.onKeyPress` on the tap surface to keep keyboard tapping local to the BPM tool.
- Left copy, save, adjustment picker, and history UI for Plan 02-03 so this plan stays focused on live tapping.

## Deviations from Plan

None - plan executed exactly as written.

---

**Total deviations:** 0 auto-fixed.
**Impact on plan:** No scope change.

## Issues Encountered

- Task 1 needed a compile-ready `BPMTapperView` type before the full view task. A minimal placeholder was added and then replaced by the real view in Task 2.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BPMTapperViewModelTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FeatureRegistryTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed.
- `rg -n "bpm-tapper|BPMTapper" Sources/OutsideCubaseHub/AppShell` returned no matches.
- `Sources/OutsideCubaseHub/AppComposition.swift` registers `BPMTapperFeature()`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 02-03. The tool now has live tap state and a focused native surface ready for adjustment, copy/save, and recent history actions.

---
*Phase: 02-bpm-tapper*
*Completed: 2026-05-04*
