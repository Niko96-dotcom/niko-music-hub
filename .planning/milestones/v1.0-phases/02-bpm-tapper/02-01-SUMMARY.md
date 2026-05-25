---
phase: 02-bpm-tapper
plan: "01"
subsystem: domain
tags: [swift, swiftpm, xctest, bpm, tempo-estimation]
requires:
  - phase: 01-app-foundation-and-tool-architecture
    provides: SwiftPM package structure and AppCore target boundary
provides:
  - FeatureBPMTapper SwiftPM library and test target
  - Pure Swift TempoEstimator with pause reset and outlier guardrails
  - BPMAdjustment modes for original, half-time, and double-time output
affects: [bpm-tapper-ui, bpm-history, feature-modules]
tech-stack:
  added: [FeatureBPMTapper SwiftPM target, FeatureBPMTapperTests XCTest target]
  patterns: [pure domain estimator, focused feature test target, offline source scan]
key-files:
  created:
    - Sources/FeatureBPMTapper/TempoEstimator.swift
    - Sources/FeatureBPMTapper/BPMAdjustment.swift
    - Tests/FeatureBPMTapperTests/TempoEstimatorTests.swift
    - Tests/FeatureBPMTapperTests/BPMAdjustmentTests.swift
  modified:
    - Package.swift
key-decisions:
  - "Tempo estimation remains pure Swift and Foundation-only so SwiftUI can consume deterministic state."
  - "The displayed BPM now averages a longer rolling window of accepted intervals and recovers after a rejected tap so user timing mistakes do not derail the run."
  - "Adjustment math is a small Codable/Sendable enum so history can preserve raw BPM plus adjustment context later."
patterns-established:
  - "Feature targets get their own XCTest target before UI registration."
  - "Domain code exposes structured statuses instead of forcing views to infer state from optional BPM values."
requirements-completed: ["BPM-02", "BPM-03", "BPM-05"]
duration: 10 min
completed: 2026-05-04
---

# Phase 02 Plan 01: BPM Tapper Domain Summary

**Pure Swift tempo estimation with recent-interval averaging, pause reset, outlier handling, and half/double BPM adjustment modes**

## Performance

- **Duration:** 10 min
- **Started:** 2026-05-04T13:53:25Z
- **Completed:** 2026-05-04T14:03:42Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Added `FeatureBPMTapper` and `FeatureBPMTapperTests` to SwiftPM without wiring the executable yet.
- Implemented `TempoEstimator` with first-estimate-after-two-taps behavior, rolling interval averaging, long-pause reset, and outlier preservation.
- Added `BPMAdjustment` for `Original`, `Half-Time`, and `Double-Time` values with focused tests.
- Verified the feature module contains no network, downloader, FFmpeg, Core Audio, or ScreenCaptureKit references.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add FeatureBPMTapper package and test targets** - `6d6865f` (feat)
2. **Task 2: Implement TempoEstimator with recent interval averaging** - `e14dd4b` (feat)
3. **Task 3: Implement BPMAdjustment and offline source scan** - `138754f` (feat)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `Package.swift` - Adds the BPM feature library and test target.
- `Sources/FeatureBPMTapper/TempoEstimator.swift` - Pure tap tempo estimator with explicit statuses and configuration.
- `Sources/FeatureBPMTapper/BPMAdjustment.swift` - Original, half-time, and double-time adjustment domain.
- `Tests/FeatureBPMTapperTests/TempoEstimatorTests.swift` - Estimator tests for first estimate, rolling averaging, long pause reset, outlier handling, and recovery after a rejected tap.
- `Tests/FeatureBPMTapperTests/BPMAdjustmentTests.swift` - Adjustment math and display name tests.

## Decisions Made

- Used a structured `TempoEstimate` return value so the UI can distinguish idle, first estimate, stable estimate, reset, and ignored-tap states.
- Kept the recent interval limit, pause threshold, min/max interval, and outlier tolerance explicit in `TempoEstimatorConfiguration`.
- Made adjustment values Codable and Sendable now because Plan 02-03 saves adjustment context in local history.

## Deviations from Plan

None - plan executed exactly as written.

---

**Total deviations:** 0 auto-fixed.
**Impact on plan:** No scope change.

## Issues Encountered

- Swift required constants used by public initializer default arguments to be public. The estimator defaults were moved into a public nested `Defaults` enum and reverified with `TempoEstimatorTests`.
- Human UAT found the last-four average felt too jumpy and rejected taps could make following taps feel like resets. The default rolling window was increased to 12 intervals while keeping the stable threshold at 4 intervals, and rejected taps now advance the reference timestamp so the next clean tap can recover.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TempoEstimatorTests` passed with 7 tests after the UAT smoothing fix.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BPMAdjustmentTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 45 tests after the UAT smoothing fix.
- `rg -n "URLSession|Network|yt-dlp|FFmpeg|CoreAudio|ScreenCaptureKit" Sources/FeatureBPMTapper` returned no matches.
- `Package.swift` defines `FeatureBPMTapper` and `FeatureBPMTapperTests`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 02-02. The app can now import a deterministic BPM domain module and build a focused SwiftUI tap surface on top of it.

---
*Phase: 02-bpm-tapper*
*Completed: 2026-05-04*
