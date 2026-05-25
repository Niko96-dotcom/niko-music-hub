---
phase: 02-bpm-tapper
plan: "03"
subsystem: ui-actions
tags: [swiftui, appkit, userdefaults, clipboard, bpm-history, xctest]
requires:
  - phase: 02-bpm-tapper
    provides: BPMTapperFeature, BPMTapperView, BPMTapperViewModel, TempoEstimator, and BPMAdjustment
provides:
  - Feature-local BPMHistoryStore and UserDefaults persistence
  - Plain-number BPMClipboardWriting port with NSPasteboard adapter
  - Adjustment-aware copy, save, row copy, and clear-history actions
  - Recent Tempos UI with clear-all confirmation
affects: [bpm-tapper, local-history, clipboard, appkit-interop]
tech-stack:
  added: [UserDefaults BPM history persistence, NSPasteboard clipboard adapter]
  patterns: [feature-local persistence port, clipboard port, action fakes for tests]
key-files:
  created:
    - Sources/FeatureBPMTapper/BPMHistoryStore.swift
    - Sources/FeatureBPMTapper/UserDefaultsBPMHistoryStore.swift
    - Sources/FeatureBPMTapper/BPMClipboardWriter.swift
    - Tests/FeatureBPMTapperTests/BPMHistoryStoreTests.swift
    - Tests/FeatureBPMTapperTests/BPMTapperActionsTests.swift
  modified:
    - Sources/FeatureBPMTapper/BPMTapperFeature.swift
    - Sources/FeatureBPMTapper/BPMTapperView.swift
    - Sources/FeatureBPMTapper/BPMTapperViewModel.swift
key-decisions:
  - "BPM history is feature-local UserDefaults data and does not touch OutputInboxStore."
  - "Clipboard writes use a port and copy only the formatted displayed BPM number."
  - "Clear History removes saved rows without resetting the current tap run."
patterns-established:
  - "Feature actions depend on small ports with fake implementations in XCTest."
  - "Saved local history entries preserve displayed BPM, raw tapped BPM, adjustment, and timestamp."
requirements-completed: ["BPM-03", "BPM-04", "BPM-05"]
duration: 7 min
completed: 2026-05-04
---

# Phase 02 Plan 03: BPM Tapper Actions Summary

**Adjustment-aware BPM copy/save actions, local recent tempo history, row copy, and clear-all history UI**

## Performance

- **Duration:** 7 min
- **Started:** 2026-05-04T14:07:57Z
- **Completed:** 2026-05-04T14:14:48Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments

- Added typed local BPM history with UserDefaults persistence and newest-first listing.
- Added `BPMClipboardWriting` plus an AppKit pasteboard adapter that writes plain numbers only.
- Extended the view model with adjustment, copy, save, row-copy, load-history, and clear-history actions.
- Rendered the segmented adjustment picker, `Copy BPM`, `Save BPM`, `Reset Taps`, `Recent Tempos`, row-level `Copy Saved BPM`, and `Clear History` confirmation.
- Verified BPM history does not use the output inbox and the feature remains offline-only.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add local BPM history model and UserDefaults store** - `5717adc` (feat)
2. **Task 2: Add adjustment, copy, save, row-copy, and clear actions to view model** - `9bce5da` (feat)
3. **Task 3: Render segmented adjustment, action row, history list, and clear-all confirmation** - `6e41aad` (feat)
4. **UI contract polish: Show row copy confirmation inline** - `09b8527` (fix)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `Sources/FeatureBPMTapper/BPMHistoryStore.swift` - BPM history entry model and store protocol.
- `Sources/FeatureBPMTapper/UserDefaultsBPMHistoryStore.swift` - UserDefaults-backed local history adapter.
- `Sources/FeatureBPMTapper/BPMClipboardWriter.swift` - Clipboard protocol, pasteboard adapter, and no-op test/default adapter.
- `Sources/FeatureBPMTapper/BPMTapperFeature.swift` - Injects production history and clipboard adapters.
- `Sources/FeatureBPMTapper/BPMTapperViewModel.swift` - Implements adjustment, copy/save/history actions, confirmations, and formatting.
- `Sources/FeatureBPMTapper/BPMTapperView.swift` - Renders adjustment, actions, history rows, and clear-all confirmation.
- `Tests/FeatureBPMTapperTests/BPMHistoryStoreTests.swift` - Covers local persistence behavior.
- `Tests/FeatureBPMTapperTests/BPMTapperActionsTests.swift` - Covers adjustment, copy, save, row copy, and clear-history behavior.

## Decisions Made

- Used UserDefaults for durable feature-local BPM history because the data is small, local, and not file-output-oriented.
- Kept clipboard and history behind protocols so AppKit/UserDefaults do not leak into view model action tests.
- Used a single clear-all history action with confirmation and no row deletion, matching the Phase 2 scope.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical UX Detail] Row copy confirmation appeared away from the row action**
- **Found during:** Phase-level UI contract spot-check after Task 3
- **Issue:** `copySavedBPM(_:)` set the normal copy confirmation, but the visible message appeared under the main action row instead of next to the row-level `Copy Saved BPM` trigger.
- **Fix:** Track the copied history entry ID in `BPMTapperView` and render `BPM copied` next to the copied row.
- **Files modified:** `Sources/FeatureBPMTapper/BPMTapperView.swift`
- **Verification:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed.
- **Committed in:** `09b8527`

---

**Total deviations:** 1 auto-fixed (1 missing critical UX detail).
**Impact on plan:** This tightened an explicitly planned inline-confirmation behavior without changing scope.

## Issues Encountered

- SwiftUI conditional button styles do not type-infer across `.bordered` and `.borderedProminent`; `Save BPM` now uses a stable prominent style and relies on disabled state when no BPM exists.
- The view now includes literal segmented-control labels so `Original`, `Half-Time`, and `Double-Time` are mechanically visible in the UI contract scan.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BPMHistoryStoreTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BPMTapperActionsTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 43 tests.
- `rg -n "OutputInboxStore|addItem" Sources/FeatureBPMTapper` returned no matches.
- `rg -n "URLSession|Network|yt-dlp|FFmpeg|CoreAudio|ScreenCaptureKit" Sources/FeatureBPMTapper` returned no matches.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run OutsideCubaseHub` built and launched without immediate startup failure; the process was then stopped.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 2 is ready for phase-level review and verification. BPM Tapper is now usable as a local tool with tapping, adjustment, copy/save, recent history, row copy, and clear-all behavior.

---
*Phase: 02-bpm-tapper*
*Completed: 2026-05-04*
