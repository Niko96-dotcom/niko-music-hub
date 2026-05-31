# Requirements: Outside Cubase Hub

**Defined:** 2026-05-31
**Milestone:** v1.3 Full UI Redesign
**Core Value:** Repeated production chores outside Cubase should become fast, local, reliable, and drag-and-drop ready for a Cubase project.

**Source spec:** `docs/UI-REDESIGN-PLAN.md` (handoff-ready; implementation order Waves 1–5)

## v1.3 Requirements

### Design System & Shared Components

- [x] **DS-01**: `HubDesignSystem` exposes new radius, spacing, size, color, and typography tokens per spec §3.1
- [x] **DS-02**: `HubGlassChrome` uses refined shell gradients, panel shadow, card inner highlight, and sidebar row tokens per spec §3.2
- [x] **DS-03**: `HubLabeledButton` exists with primary/secondary/ghost styles for icon+label actions per spec §13.1
- [x] **DS-04**: `HubSectionDivider` replaces invisible `Divider().opacity(0.4)` for major section breaks per spec §13.6
- [x] **DS-05**: `HubIconButton` is 30×30 with hover accent tint; reserved for contextually obvious icon-only actions per spec §13.2
- [x] **DS-06**: `StatusDot` uses 7px size and `HubDesignSystem.Colors` semantic states per spec §13.3
- [x] **DS-07**: `HubToolLayout` spacing and `maxContentWidth` 680 match spec §13.5
- [x] **DS-08**: `HubCompactChipColors` includes merged `.archive` variant; `HubCompactChipColors+Archive.swift` removed per spec §3.3 / §7.6

### Shell & Navigation

- [x] **SH-01**: `AppShellView` uses shell gap 10, centered tool content columns, collapsed-rail hover, default window 1280×820 per spec §4
- [x] **SH-02**: `ToolSidebarView` shows icon+label rows, updated header (version not “Local tools”), health strip tokens per spec §5
- [x] **SH-03**: `OutputInboxInspectorView` header, empty state, horizontal output cards, context menu / hover drag grip per spec §6
- [x] **SH-04**: `ArchiveDesignTokens.swift` deleted; all references use `HubDesignSystem.Colors` per spec §3.3

### Tool Pages (BPM, Recorder, Converter)

- [ ] **TOOL-01**: BPM Tapper — centered layout, display typography, 240px tap target, labeled Copy/Save/Reset, history divider per spec §8
- [ ] **TOOL-02**: Audio Recorder — hero 56pt timer, gradient meter with glow, prominent Record/Stop, save toast banner per spec §10
- [ ] **TOOL-03**: WAV Converter — dashed drop zone, visible preset strip, labeled Add/Convert/Stop, batch row badges per spec §9

### Tool Pages (Downloader & Settings)

- [ ] **TOOL-04**: Downloader — glass URL field with inline Download/Clear, format chips, trust card with `LabeledContent` per spec §11
- [ ] **TOOL-05**: Settings — section hierarchy (critical/config/info), labeled archive/helper actions, centered max 640 per spec §12

### Archive Browser — Browse & Sidebar

- [ ] **ARCH-01**: Archive sidebar toolbar (count badge, scan/+), horizontal shelf chips, sort chip menu, search field per spec §7.1
- [ ] **ARCH-02**: `SongCardView` tighter hierarchy, warning icon, compact mini-player per spec §7.1
- [ ] **ARCH-03**: Archive feature views migrated off deleted design tokens (`ArchiveBrowserView`, panels, health, more, root selection) per File Manifest

### Archive Browser — Detail & Onboarding

- [ ] **ARCH-04**: `SongDetailView` grouped sections (hero, metadata card, preview, labeled actions, collapsible Details) per spec §7.2
- [ ] **ARCH-05**: `ArchiveWaveformHeroView` SF Symbol seek controls; `ArchiveFirstRunView` centered welcome modal per spec §7.2–7.3
- [ ] **ARCH-06**: `ArchiveMiniPlayerView`, `NewSongSheet`, collaborator/intelligence/diagnostics views use shared accent tokens per spec §7.4–7.5

### Polish & Verification

- [ ] **POL-01**: `StandardErrorCard` recovery actions use `HubLabeledButton`; `ToolHeaderBlock` uses typography tokens per spec §13.4
- [ ] **POL-02**: Accessibility preserved — every control keeps labels/help; no regression in VoiceOver labels from v1.2
- [ ] **QA-03**: `./script/ci.sh` and `./script/e2e_user_smoke.sh` green after each phase; milestone close includes visual pass of all tools + archive per spec §14 Wave 5

## Future Requirements

Deferred beyond v1.3.

- **VIS-01**: Custom empty-state illustrations (spec notes icon+text only for this milestone)
- **VIS-02**: Custom brand font beyond SF system + rounded variants
- **ANIM-01**: Tap-surface scale animation on BPM pad (spec §8.3 — optional polish if time)

## Out of Scope (v1.3)

| Feature | Reason |
|---------|--------|
| New product features / CP-19+ backlog | UI-only milestone; behavior unchanged unless required for layout |
| macOS App Store / distribution | Unchanged from prior milestones |
| Rewriting archive intelligence algorithms | Token/layout migration only |
| Web or iOS targets | macOS SwiftUI only |
| Changing audio/download/conversion logic | Visual and component layer only |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DS-01 | Phase 19 | Complete |
| DS-02 | Phase 19 | Complete |
| DS-03 | Phase 19 | Complete |
| DS-04 | Phase 19 | Complete |
| DS-05 | Phase 19 | Complete |
| DS-06 | Phase 19 | Complete |
| DS-07 | Phase 19 | Complete |
| DS-08 | Phase 19 | Complete |
| SH-01 | Phase 20 | Complete |
| SH-02 | Phase 20 | Complete |
| SH-03 | Phase 20 | Complete |
| SH-04 | Phase 20 | Complete |
| TOOL-01 | Phase 21 | Pending |
| TOOL-02 | Phase 21 | Pending |
| TOOL-03 | Phase 21 | Pending |
| TOOL-04 | Phase 22 | Pending |
| TOOL-05 | Phase 22 | Pending |
| ARCH-01 | Phase 23 | Pending |
| ARCH-02 | Phase 23 | Pending |
| ARCH-03 | Phase 23 | Pending |
| ARCH-04 | Phase 24 | Pending |
| ARCH-05 | Phase 24 | Pending |
| ARCH-06 | Phase 24 | Pending |
| POL-01 | Phase 25 | Pending |
| POL-02 | Phase 25 | Pending |
| QA-03 | Phase 25 | Pending |

**Coverage:**
- v1.3 requirements: 26 total
- Mapped to phases: 26
- Unmapped: 0 ✓

---
*Requirements defined: 2026-05-31 from `docs/UI-REDESIGN-PLAN.md`*
