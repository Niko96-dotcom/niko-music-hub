# Roadmap: Niko Music Hub

**Created:** 2026-05-04  
**Granularity:** Standard  
**Current milestone:** v1.3 Full UI Redesign (Phases 19–25)

## Milestones

- ✅ **v1.0 MVP** — Phases 1-6 (shipped 2026-05-11)
- ✅ **v1.1 Production-Ready Tools** — Phases 7-10 (shipped 2026-05-23)
- ✅ **v1.2 Cubase Archive Recall** — Phases 11-18 (shipped 2026-05-30)
- 🚧 **v1.3 Full UI Redesign** — Phases 19-25 (in progress)

**Spec:** `docs/UI-REDESIGN-PLAN.md`  
**Requirements:** `.planning/REQUIREMENTS.md`  
**Milestone context:** `.planning/MILESTONE-CONTEXT.md`

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-6) — SHIPPED 2026-05-11</summary>

- [x] Phase 1: App Foundation and Tool Architecture (3/3 plans) — completed 2026-05-04
- [x] Phase 2: BPM Tapper (3/3 plans) — completed 2026-05-04
- [x] Phase 3: Cubase-Ready WAV Conversion (5/5 plans) — completed 2026-05-05
- [x] Phase 4: Internal Audio Recorder (4/4 plans) — completed 2026-05-11
- [x] Phase 5: Downloader Hub (4/4 plans) — completed 2026-05-11
- [x] Phase 6: Integration Polish and Extensibility Check (4/4 plans) — completed 2026-05-11

Archive: `.planning/milestones/v1.0-phases/`, `.planning/milestones/v1.0-ROADMAP.md`

</details>

<details>
<summary>✅ v1.1 Production-Ready Tools (Phases 7-10) — SHIPPED 2026-05-23</summary>

- [x] Phase 7: Downloader Reliability & Error Surfacing (3/3 plans)
- [x] Phase 8: Real Core Audio Capture & Recorder UAT (2/2 plans, human UAT pending)
- [x] Phase 9: Converter & Output Inbox Handoff UAT (1/1 plan, human UAT pending)
- [x] Phase 10: Hub Polish, Helper Health & Verification Discipline (1/1 plan, human UAT pending)

Archive: `.planning/milestones/v1.1-phases/`

</details>

<details>
<summary>✅ v1.2 Cubase Archive Recall (Phases 11-18) — SHIPPED 2026-05-30</summary>

- [x] Phase 11: Archive Persistence (2/2 plans)
- [x] Phase 12: Metadata Core (2/2 plans)
- [x] Phase 13: Smart Shelves (1/1 plan)
- [x] Phase 14: Waveform Player (1/1 plan)
- [x] Phase 15: Browse & Collaborators (2/2 plans)
- [x] Phase 16: Filters, BPM & Polish (1/1 plan)
- [x] Phase 17: New Song Flow (1/1 plan)
- [x] Phase 18: Read-Only Intelligence (1/1 plan)

Archive: `.planning/milestones/v1.2-phases/`, `.planning/milestones/v1.2-ROADMAP.md`

</details>

### 🚧 v1.3 Full UI Redesign

- [x] **Phase 19: Design System Foundation** — Tokens, glass chrome, `HubLabeledButton`, `HubSectionDivider`, shared control updates (Wave 1) (completed 2026-05-31)
- [ ] **Phase 20: Shell & Navigation** — App shell, sidebar, output inbox, delete `ArchiveDesignTokens` (Wave 2)
- [ ] **Phase 21: Tool UI — BPM, Recorder, Converter** — Centered/spacious tool layouts, labeled actions (Wave 3a)
- [ ] **Phase 22: Tool UI — Downloader & Settings** — Glass URL field, chips, settings hierarchy (Wave 3b)
- [ ] **Phase 23: Archive Browse & Sidebar** — Toolbar, shelf chips, song cards, token migration (Wave 4a)
- [ ] **Phase 24: Archive Detail & Panels** — Grouped detail, waveform hero, first-run, sheets, panels (Wave 4b)
- [ ] **Phase 25: UI Polish & Visual Regression** — Error card, headers, window default, full-page visual pass (Wave 5)

## Phase Details (v1.3)

### Phase 19: Design System Foundation

**Goal:** Land shared design tokens and components so later phases only compose UI — no ad-hoc colors or mystery icon buttons.

**Depends on:** v1.2 complete

**Requirements:** DS-01, DS-02, DS-03, DS-04, DS-05, DS-06, DS-07, DS-08

**Success criteria:**
1. `HubDesignSystem` matches spec §3.1 (radius, spacing, colors, typography).
2. `HubGlassChrome` gradient/shadow/card highlight per spec §3.2.
3. `HubLabeledButton` and `HubSectionDivider` compile and are usable from AppCore.
4. `HubIconButton`, `StatusDot`, `HubToolLayout`, `HubCompactChipColors` updated; archive chip extension merged.
5. `./script/ci.sh` green (no consumer view changes required yet).

**Key files:** `HubDesignSystem.swift`, `HubGlassChrome.swift`, `HubLabeledButton.swift` (new), `HubSectionDivider.swift` (new), `HubIconButton.swift`, `StatusDot.swift`, `HubToolLayout.swift`, `HubCompactChipColors.swift`

**Plans:** 4/4 plans complete

Plans:
- [x] 19-01-PLAN.md — HubDesignSystem §3.1 tokens + unit tests (DS-01)
- [x] 19-02-PLAN.md — HubGlassChrome gradients, shadow, highlights (DS-02)
- [x] 19-03-PLAN.md — HubLabeledButton + HubSectionDivider + tests (DS-03, DS-04)
- [x] 19-04-PLAN.md — Icon button, StatusDot, ToolLayout, chip merge (DS-05–DS-08)

---

### Phase 20: Shell & Navigation

**Goal:** App chrome feels like one cohesive glass surface; archive token file removed.

**Depends on:** Phase 19

**Requirements:** SH-01, SH-02, SH-03, SH-04

**Success criteria:**
1. Three-column shell spacing 10px; tool content centered in column; window default 1280×820.
2. Sidebar rows show icon + label; health strip uses new tokens.
3. Output inbox header/cards/empty state per spec §6.
4. `ArchiveDesignTokens.swift` deleted; project builds with `HubDesignSystem.Colors` only.
5. `./script/ci.sh` green.

**Key files:** `AppShellView.swift`, `ToolSidebarView.swift`, `OutputInboxInspectorView.swift`, delete `ArchiveDesignTokens.swift` + 16 reference updates

**Plans:** TBD (`/gsd-plan-phase 20`)

---

### Phase 21: Tool UI — BPM, Recorder, Converter

**Goal:** Production tools match page-specific density — hero readouts, labeled actions, refined drop/meter UX.

**Depends on:** Phase 20

**Requirements:** TOOL-01, TOOL-02, TOOL-03

**Success criteria:**
1. BPM Tapper centered layout, 56pt display, labeled Copy/Save/Reset, larger tap pad.
2. Recorder hero timer, gradient meter, prominent Record/Stop, save toast.
3. Converter dashed drop zone, preset strip, labeled Add/Convert/Stop, batch badges.
4. `./script/ci.sh` green.

**Key files:** `BPMTapperView.swift`, `AudioRecorderView.swift`, `AudioConverterView.swift`

**Plans:** TBD (`/gsd-plan-phase 21`)

---

### Phase 22: Tool UI — Downloader & Settings

**Goal:** Downloader and Settings match glass aesthetic and labeled-action rules.

**Depends on:** Phase 21

**Requirements:** TOOL-04, TOOL-05

**Success criteria:**
1. Downloader glass URL row with inline Download; format chips; trust card layout.
2. Settings section hierarchy and labeled helper/archive actions.
3. `./script/ci.sh` green.

**Key files:** `DownloaderView.swift`, `SettingsView.swift`, `SettingsSection` updates

**Plans:** TBD (`/gsd-plan-phase 22`)

---

### Phase 23: Archive Browse & Sidebar

**Goal:** Archive list/browse surfaces are scannable — chips, cards, toolbar — with full token migration.

**Depends on:** Phase 22

**Requirements:** ARCH-01, ARCH-02, ARCH-03

**Success criteria:**
1. Sidebar toolbar, horizontal shelf chips, sort chip menu, search field per spec §7.1.
2. Song cards tighter with warning icon and compact player.
3. `ArchiveBrowserView` and secondary panels use shared accent tokens (no archive-only token file).
4. Delete `HubCompactChipColors+Archive.swift` when merge complete.
5. `./script/ci.sh` green.

**Key files:** `ArchiveSidebarView.swift`, `SongCardView.swift`, `ArchiveBrowserView.swift`, panel views in File Manifest §15

**Plans:** TBD (`/gsd-plan-phase 23`)

---

### Phase 24: Archive Detail & Panels

**Goal:** Song detail reads in grouped sections; onboarding and waveform controls match spec.

**Depends on:** Phase 23

**Requirements:** ARCH-04, ARCH-05, ARCH-06

**Success criteria:**
1. `SongDetailView` sectioned layout with collapsible Details and labeled primary actions.
2. Waveform hero SF Symbol seek buttons; centered first-run modal.
3. Mini player, new song sheet, collaborator/intelligence/diagnostics views token-aligned.
4. `./script/ci.sh` and `./script/e2e_user_smoke.sh` green.

**Key files:** `SongDetailView.swift`, `ArchiveWaveformHeroView.swift`, `ArchiveFirstRunView.swift`, `ArchiveMiniPlayerView.swift`, `NewSongSheet.swift`, related archive panels

**Plans:** TBD (`/gsd-plan-phase 24`)

---

### Phase 25: UI Polish & Visual Regression

**Goal:** Close remaining shared components and verify every page at default and wide window sizes.

**Depends on:** Phase 24

**Requirements:** POL-01, POL-02, QA-03

**Success criteria:**
1. `StandardErrorCard` and `ToolHeaderBlock` use new components/tokens.
2. `NikoMusicHubApp` default window size updated.
3. Manual visual checklist: shell, all five tools, archive browse + detail, settings — light/dark if applicable.
4. Accessibility spot-check: primary actions have visible labels; existing a11y identifiers preserved.
5. `./script/ci.sh` and `./script/e2e_user_smoke.sh` green.

**Key files:** `StandardErrorCard.swift`, `ToolHeaderBlock.swift`, `NikoMusicHubApp.swift`, `HubDragAffordance.swift` (hover-only grip)

**Plans:** TBD (`/gsd-plan-phase 25`)

---

## Requirement Coverage (v1.3)

| Phase | Requirements | Count |
|-------|--------------|-------|
| Phase 19 | DS-01–DS-08 | 8 |
| Phase 20 | SH-01–SH-04 | 4 |
| Phase 21 | TOOL-01–TOOL-03 | 3 |
| Phase 22 | TOOL-04–TOOL-05 | 2 |
| Phase 23 | ARCH-01–ARCH-03 | 3 |
| Phase 24 | ARCH-04–ARCH-06 | 3 |
| Phase 25 | POL-01, POL-02, QA-03 | 3 |

**Coverage check:** 26 / 26 v1.3 requirements mapped.

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1–6 | v1.0 | 15/19 | Shipped | 2026-05-11 |
| 7–10 | v1.1 | 7/7 | Shipped | 2026-05-23 |
| 11–18 | v1.2 | 9/9 | Shipped | 2026-05-30 |
| 19–25 | v1.3 | 4/4 | Phase 19 complete | 2026-05-31 |

## Roadmap Notes

- v1.3 is **visual-only** — follow `docs/UI-REDESIGN-PLAN.md` implementation order; phases map to Waves 1–5.
- Autonomous: `/gsd-autonomous` runs discuss → plan → execute for phases 19–25.
- Frontend phases: autonomous mode may generate `*-UI-SPEC.md` and run UI review audits.

---
*Last updated: 2026-05-31 — v1.3 milestone opened*
