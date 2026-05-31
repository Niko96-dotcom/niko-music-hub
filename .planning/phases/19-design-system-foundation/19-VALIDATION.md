---
phase: 19
slug: design-system-foundation
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-31
---

# Phase 19 — Validation Strategy

> AppCore design tokens and shared components; no feature view changes.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift Package Manager) |
| **Config file** | `Package.swift` — target `AppCoreTests` |
| **Quick run command** | `swift test --filter 'HubDesignSystemTokenTests|HubDesignComponentsTests|HubSharedControlsTests'` |
| **Full suite command** | `./script/ci.sh` |
| **Estimated runtime** | ~60–120 seconds (full CI) |

---

## Sampling Rate

- **After every task commit:** Run task `<automated>` verify from PLAN.md
- **After every plan wave:** Run `swift test --filter AppCoreTests` then `./script/ci.sh`
- **Before `/gsd-verify-work`:** `./script/ci.sh` green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 19-01-01 | 01 | 1 | DS-01 | unit | `swift test --filter HubDesignSystemTokenTests` | W0 | ⬜ pending |
| 19-01-02 | 01 | 1 | DS-01 | unit | `swift test --filter HubDesignSystemTokenTests` | W0 | ⬜ pending |
| 19-01-03 | 01 | 1 | DS-01 | integration | `./script/ci.sh` | — | ⬜ pending |
| 19-02-01 | 02 | 2 | DS-02 | build | `swift build --target AppCore` | — | ⬜ pending |
| 19-02-02 | 02 | 2 | DS-02 | grep | `rg -c 'radius: 18' Sources/AppCore/Components/HubGlassChrome.swift` | — | ⬜ pending |
| 19-02-03 | 02 | 2 | DS-02 | integration | `./script/ci.sh` | — | ⬜ pending |
| 19-03-01 | 03 | 3 | DS-03/04 | unit | `swift test --filter HubDesignComponentsTests` | W0 | ⬜ pending |
| 19-03-02 | 03 | 3 | DS-03 | unit | `swift test --filter HubDesignComponentsTests` | — | ⬜ pending |
| 19-03-03 | 03 | 3 | DS-04 | unit | `swift test --filter HubDesignComponentsTests && ./script/ci.sh` | — | ⬜ pending |
| 19-04-01 | 04 | 4 | DS-05–08 | unit | `swift test --filter HubSharedControlsTests` | W0 | ⬜ pending |
| 19-04-02 | 04 | 4 | DS-05/06 | unit | `swift test --filter HubSharedControlsTests` | — | ⬜ pending |
| 19-04-03 | 04 | 4 | DS-07/08 | integration | `test ! -f Sources/FeatureArchiveBrowser/HubCompactChipColors+Archive.swift && ./script/ci.sh` | — | ⬜ pending |

---

## Wave 0 Requirements

- [ ] `Tests/AppCoreTests/HubDesignSystemTokenTests.swift` — created in plan 19-01 Task 1
- [ ] `Tests/AppCoreTests/HubDesignComponentsTests.swift` — created in plan 19-03 Task 1
- [ ] `Tests/AppCoreTests/HubSharedControlsTests.swift` — created in plan 19-04 Task 1

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Light/dark glass parity | DS-02, D-05 | Visual depth | SwiftUI previews or run app after phase 20 shell — optional spot-check in Phase 25 |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all new test file references
- [x] No watch-mode flags
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-05-31
