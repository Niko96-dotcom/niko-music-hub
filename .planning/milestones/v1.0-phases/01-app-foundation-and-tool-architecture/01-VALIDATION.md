---
phase: 01
slug: app-foundation-and-tool-architecture
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-04
---

# Phase 01 - Validation Strategy

Per-phase validation contract for feedback sampling during execution.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest through Swift Package Manager |
| **Config file** | `Package.swift` |
| **Quick run command** | `swift test --filter AppCoreTests` |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~15 seconds after scaffold |

## Sampling Rate

- **After every task commit:** Run `swift test --filter AppCoreTests` once the test target exists.
- **After every plan wave:** Run `swift test`.
- **Before `$gsd-verify-work`:** Full suite must be green and app launch must be manually checked once.
- **Max feedback latency:** 30 seconds for AppCore tests.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01-01 | 1 | FND-01 | T-01-UI | App opens only registered tools; no hidden future placeholders | build/manual | `swift test` | W0 creates `Package.swift` | pending |
| 01-02-01 | 01-02 | 1 | FND-02 | T-01-REG | Duplicate tool IDs are rejected deterministically | unit | `swift test --filter FeatureRegistryTests` | W0 creates `Tests/AppCoreTests/FeatureRegistryTests.swift` | pending |
| 01-03-01 | 01-03 | 2 | FND-03 | T-01-FILE | Output folder is user-selected/persisted through a URL-shaped abstraction | unit | `swift test --filter SettingsStoreTests` | W0 creates `Tests/AppCoreTests/SettingsStoreTests.swift` | pending |
| 01-03-02 | 01-03 | 2 | FND-04 | T-01-JOB | Jobs transition only through queued/running/completed/failed/canceled states | unit | `swift test --filter JobRunnerTests` | W0 creates `Tests/AppCoreTests/JobRunnerTests.swift` | pending |
| 01-03-03 | 01-03 | 2 | FND-05 | T-01-SETTINGS | Audio preset defaults and helper tool paths persist in isolated test storage | unit | `swift test --filter SettingsStoreTests` | W0 creates `Tests/AppCoreTests/SettingsStoreTests.swift` | pending |

## Wave 0 Requirements

- [ ] `Package.swift` - executable app target plus `AppCore` library and `AppCoreTests` test target.
- [ ] `Tests/AppCoreTests/FeatureRegistryTests.swift` - registry ordering, lookup, capability flags, duplicate-id rejection, and second-feature registration.
- [ ] `Tests/AppCoreTests/SettingsStoreTests.swift` - output folder, audio preset defaults, and helper path persistence with isolated storage.
- [ ] `Tests/AppCoreTests/OutputInboxStoreTests.swift` - add/list/update persistence with temp directories and missing-file state.
- [ ] `Tests/AppCoreTests/JobRunnerTests.swift` - queued, running, completed, failed, canceled, progress, message, and cancellation behavior.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Native shell launches into the first registered tool | FND-01 | SwiftUI window launch and navigation selection are better verified in the running app for Phase 1 | Run the app locally and confirm the first visible tool is the registered dummy/dev tool. |
| Sidebar/tool-list navigation and reachable output inbox | FND-01, FND-03 | Visual hierarchy depends on the UI design contract | Run the app locally and confirm navigation is tool-list based and the output inbox is reachable but not dominant. |
| No disabled roadmap placeholders are shown | FND-02 | This is a product/UI assertion | Run the app locally and confirm BPM, conversion, recorder, and downloader placeholders are absent in Phase 1. |

## Validation Sign-Off

- [ ] All PLAN tasks have `<automated>` verification or explicit manual verification.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verification.
- [ ] Wave 0 creates XCTest infrastructure before AppCore behavior work depends on it.
- [ ] No watch-mode flags in validation commands.
- [ ] Feedback latency stays under 30 seconds for AppCore tests.
- [ ] `nyquist_compliant: true` remains set in frontmatter.

**Approval:** pending
