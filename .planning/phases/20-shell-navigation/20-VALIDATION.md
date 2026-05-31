---
phase: 20
slug: shell-navigation
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-31
---

# Phase 20 — Validation Strategy

> Shell chrome, sidebar, output inbox, archive token deletion. No per-tool page layouts (Phases 21–22).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift Package Manager) + source-contract tests |
| **Config file** | `Package.swift` — `AppCoreTests`, `FeatureArchiveBrowserTests` |
| **Quick run command** | `swift test --filter 'HubToolContentColumnTests|testOutputInboxInspectorSourceContainsRevealAndDragHandoff'` |
| **Full suite command** | `./script/ci.sh` |
| **UI smoke (post-phase)** | `./script/e2e_user_smoke.sh` when shell/inbox changes ship |
| **Estimated runtime** | ~60–120 seconds (full CI) |

---

## Sampling Rate

- **After every task commit:** Run task `<automated>` verify from PLAN.md
- **After wave 1:** `swift test --filter HubToolContentColumnTests` + `./script/ci.sh`
- **After wave 2:** Full `./script/ci.sh` (all four plans may land in parallel)
- **Before `/gsd-verify-work`:** `./script/ci.sh` green; optional e2e smoke
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 20-01-01 | 01 | 1 | SH-01 | unit | `swift test --filter HubToolContentColumnTests` | W0 | ⬜ pending |
| 20-01-02 | 01 | 1 | SH-01 | grep | `rg hubToolContentColumn Sources/NikoMusicHub/AppShell/AppShellView.swift` | — | ⬜ pending |
| 20-01-03 | 01 | 1 | SH-01 | integration | `./script/ci.sh` | — | ⬜ pending |
| 20-02-01 | 02 | 2 | SH-02 | grep | `rg CFBundleShortVersionString Sources/NikoMusicHub/AppShell/ToolSidebarView.swift` | — | ⬜ pending |
| 20-02-02 | 02 | 2 | SH-02 | grep | `rg 'frame\(width: 18, height: 18\)' Sources/NikoMusicHub/AppShell/ToolSidebarView.swift` | — | ⬜ pending |
| 20-02-03 | 02 | 2 | SH-02 | integration | `./script/ci.sh` | — | ⬜ pending |
| 20-03-01 | 03 | 2 | SH-03 | grep | `rg 'Text\("Output"\)' Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift` | — | ⬜ pending |
| 20-03-02 | 03 | 2 | SH-03 | grep | `rg 'No outputs yet' Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift` | — | ⬜ pending |
| 20-03-03 | 03 | 2 | SH-03 | unit+integration | `swift test --filter testOutputInboxInspectorSourceContainsRevealAndDragHandoff && ./script/ci.sh` | — | ⬜ pending |
| 20-04-01 | 04 | 2 | SH-04 | grep | `! rg ArchiveDesignTokens Sources/FeatureArchiveBrowser/{ArchiveBrowserView,RootSelectionView,SongCardView,ArchiveCollaboratorAddressBookView,ArchiveFirstRunView,ArchiveSidebarView,ArchiveIntelligencePanelView,ArchiveMiniPlayerView}.swift` | — | ⬜ pending |
| 20-04-02 | 04 | 2 | SH-04 | grep | `! rg ArchiveDesignTokens Sources/FeatureArchiveBrowser/{ArchiveDiagnosticsPanelView,NewSongSheet,ArchiveSidebarMorePanel,ArchiveHealthReportView,ArchiveWaveformHeroView,ArchiveWaveformView,SongDetailView}.swift` | — | ⬜ pending |
| 20-04-03 | 04 | 2 | SH-04 | integration | `test ! -f Sources/FeatureArchiveBrowser/ArchiveDesignTokens.swift && ! rg ArchiveDesignTokens Sources/ && ./script/ci.sh` | — | ⬜ pending |

---

## Wave 0 Requirements

- [ ] `Tests/AppCoreTests/HubToolContentColumnTests.swift` — created in plan 20-01 Task 1

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Glass shell visual cohesion | SH-01, D-01 | Visual depth / motion | Launch app; toggle sidebars; confirm 10px seams and centered tool column |
| Sidebar selection + version | SH-02 | Typography/color | Select each tool; confirm accent row + bundle version string |
| Inbox hover grip + reveal | SH-03 | Hover UX | Hover card for grip; single-click reveal; context menu Open/Reveal |
| Archive colors unchanged layout | SH-04, S-15 | Layout out of scope | Spot-check archive browser light/dark after token swap |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers new test file reference
- [x] No watch-mode flags
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-05-31 (plan-phase)
