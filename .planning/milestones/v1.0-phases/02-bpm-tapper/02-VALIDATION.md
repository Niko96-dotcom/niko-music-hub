---
phase: 02
slug: bpm-tapper
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-04
---

# Phase 02 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest via Swift Package Manager |
| **Config file** | `Package.swift` |
| **Quick run command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FeatureBPMTapperTests` |
| **Full suite command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` |
| **Estimated runtime** | ~5-15 seconds |

## Sampling Rate

- **After every task commit:** Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FeatureBPMTapperTests` when the target exists.
- **After every plan wave:** Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- **Before `$gsd-verify-work`:** Full suite must be green.
- **Max feedback latency:** 15 seconds for focused tests, 30 seconds for full suite.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | BPM-02, BPM-05 | T-02-DOMAIN | Estimator has bounded intervals and no network dependency. | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TempoEstimatorTests` | W0 | pending |
| 02-01-02 | 01 | 1 | BPM-03 | T-02-DOMAIN | Adjustment math is deterministic and preserves raw BPM context. | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BPMAdjustmentTests` | W0 | pending |
| 02-02-01 | 02 | 2 | BPM-01, BPM-02, BPM-05 | T-02-FOCUS | Space and Escape are scoped to the focused BPM tool surface. | unit + manual | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BPMTapperViewModelTests` | W0 | pending |
| 02-02-02 | 02 | 2 | BPM-01, BPM-05 | T-02-REGISTRY | BPM appears only through ToolFeature/AppComposition registration. | unit + source scan | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FeatureRegistryTests` | W0 | pending |
| 02-03-01 | 03 | 3 | BPM-03, BPM-04, BPM-05 | T-02-LOCALDATA | History persists locally and clear-all is explicit. | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BPMHistoryStoreTests` | W0 | pending |
| 02-03-02 | 03 | 3 | BPM-03, BPM-04 | T-02-CLIPBOARD | Clipboard receives only displayed plain BPM number. | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BPMTapperActionsTests` | W0 | pending |

## Wave 0 Requirements

Existing infrastructure covers all phase requirements:

- `Package.swift` already defines SwiftPM targets.
- `AppCoreTests` already run through XCTest when `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` is set.
- No watch-mode or long-running test harness is needed.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Focused tap surface accepts mouse taps and Space only while active. | BPM-01 | SwiftUI focus behavior is best confirmed in the running macOS app. | Launch with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run OutsideCubaseHub`, select BPM Tapper, click the tap surface, press Space several times, switch focus away, and confirm Space no longer taps. |
| Escape resets the current run without clearing saved history. | BPM-03, BPM-04 | Requires integrated UI and history state. | Save one BPM, tap again, press Escape, and confirm current run resets while the saved row remains. |
| Output Inbox stays secondary and BPM history stays in the BPM main view. | BPM-04, BPM-05 | Layout behavior is visual. | Confirm recent BPM rows appear below the tap workflow and no BPM entries are added to Output Inbox. |

## Validation Sign-Off

- [x] All tasks have automated verify commands or manual smoke instructions.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all missing references.
- [x] No watch-mode flags.
- [x] Feedback latency under 30 seconds.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** draft 2026-05-04
