# Roadmap: Outside Cubase Hub

**Created:** 2026-05-04
**Granularity:** Standard
**Current milestone:** v1.2 Cubase Archive Recall (Phases 11–18)

## Milestones

- ✅ **v1.0 MVP** — Phases 1-6 (shipped 2026-05-11)
- ✅ **v1.1 Production-Ready Tools** — Phases 7-10 (shipped 2026-05-23)
- 🚧 **v1.2 Cubase Archive Recall** — Phases 11-18 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-6) — SHIPPED 2026-05-11</summary>

- [x] Phase 1: App Foundation and Tool Architecture (3/3 plans) — completed 2026-05-04
- [x] Phase 2: BPM Tapper (3/3 plans) — completed 2026-05-04
- [x] Phase 3: Cubase-Ready WAV Conversion (5/5 plans) — completed 2026-05-05
- [x] Phase 4: Internal Audio Recorder (4/4 plans) — completed 2026-05-11
- [x] Phase 5: Downloader Hub (4/4 plans) — completed 2026-05-11 *(no VERIFICATION.md)*
- [x] Phase 6: Integration Polish and Extensibility Check (4/4 plans) — completed 2026-05-11 *(no VERIFICATION.md)*

Archive: `.planning/milestones/v1.0-phases/`, `.planning/milestones/v1.0-ROADMAP.md`

</details>

### 🚧 v1.1 Production-Ready Tools

- [x] **Phase 7: Downloader Reliability & Error Surfacing** — Fix simulate/enqueue, surface yt-dlp stderr, verify DL-01–10, land uncommitted downloader work *(3/3 plans — 2026-05-23)*
- [x] **Phase 8: Real Core Audio Capture & Recorder UAT** — Real Core Audio process tap, recorder start/stop UX, REC verification *(2/2 plans — 2026-05-23, human UAT pending)*
- [x] **Phase 9: Converter & Output Inbox Handoff UAT** — Inbox live refresh; CONV handoff human UAT *(1/1 plan — 2026-05-23, human UAT pending)*
- [x] **Phase 10: Hub Polish, Helper Health & Verification Discipline** — Helper health strip, QA gate *(1/1 plan — 2026-05-23, human UAT pending)*

## Phase Details (v1.1)

### Phase 7: Downloader Reliability & Error Surfacing

**Goal:** Downloader is trustworthy for daily use — failures are actionable, simulate never enqueues broken jobs, and v1.0 downloader requirements are verified.

**Depends on:** v1.0 Phase 5 (implementation baseline)

**Requirements:** DL-01, DL-02, DL-03, DL-04, DL-05, DL-06, DL-07, DL-08, DL-09, DL-10

**Success criteria:**
1. Pasting a supported URL completes download OR shows yt-dlp stderr in the error UI (not generic-only).
2. Simulate/metadata step with non-zero yt-dlp exit does not enqueue a job.
3. Trust/scope notice is visible before download starts.
4. yt-dlp health check reflects installed/missing state with guidance.
5. Phase 7 `VERIFICATION.md` documents automated + human checks for all DL requirements.

**Key work themes:**
- Fix `DownloaderUseCase.simulateAndEnqueue()` exit-code handling (see `.planning/debug/downloader-yt-dlp-failure.md`)
- Commit and wire FeatureDownloader + AppCore error components from workspace
- Retroactive verification for orphaned DL-01–07

**Plans:** TBD (via `/gsd-plan-phase 7`)

---

### Phase 8: Real Core Audio Capture & Recorder UAT

**Goal:** Recorder captures real system/process audio to Cubase-ready WAV on macOS 14.2+ with explicit permission and failure UX.

**Depends on:** Phase 7 (can run in parallel after plan; sequential default for focus)

**Requirements:** REC-01, REC-02, REC-03, REC-04, REC-05, REC-06

**Success criteria:**
1. Recorded WAV contains real audio (not synthetic noise) at configured preset sample rate/bit depth/channels.
2. Permission denied and incompatible macOS versions show explicit, recoverable UI (no silent failure).
3. Start/stop (UI + Spacebar) works during real capture with elapsed time feedback.
4. Completed recording appears in output inbox with reveal/drag handoff to Cubase/Finder.
5. Phase 8 `VERIFICATION.md` includes target-hardware proof; integration tests document permission skip policy.

**Key work themes:**
- Replace `CoreAudioTapAdapter` synthetic path with real Core Audio process tap on macOS 14.2+
- Execute deferred Phase 4 manual verification items on producer hardware

**Plans:** TBD (via `/gsd-plan-phase 8`)

---

### Phase 9: Converter & Output Inbox Handoff UAT

**Goal:** Conversion and handoff workflows are proven end-to-end in the running app, and the output inbox stays current as jobs finish.

**Depends on:** Phase 8 (recorder outputs should use same inbox refresh pattern)

**Requirements:** CONV-06, CONV-07, HUB-01

**Success criteria:**
1. User converts real source files in-app; verified WAV lands in configured output folder.
2. User drags converted WAV from app or inbox into Cubase or Finder (human-verified).
3. New outputs from converter, recorder, or downloader appear in inbox without navigating away and back.
4. Phase 9 `VERIFICATION.md` records human UAT scenarios previously deferred in Phase 3.

**Key work themes:**
- Fix `OutputInboxInspectorView` refresh (beyond `onAppear` only)
- Close Phase 3 human_needed items from `03-VERIFICATION.md`

**Plans:** TBD (via `/gsd-plan-phase 9`)

---

### Phase 10: Hub Polish, Helper Health & Verification Discipline

**Goal:** Hub UX matches production expectations — helper health visible, errors consistent, tests green, and verification process enforced for every v1.1 phase.

**Depends on:** Phase 9

**Requirements:** UX-03, UX-04, UX-05, UX-06, QA-01, QA-02

**Success criteria:**
1. yt-dlp and FFmpeg health states are accurate (path, version, missing guidance).
2. Helper, permission, and unsupported-file errors use shared recoverable messaging across tools.
3. Keyboard shortcuts for tap, reset, and record start/stop work as documented.
4. `scripts/test.sh` passes with 0 failures; permission skips documented in VERIFICATION.md.
5. Phases 7–10 each have `VERIFICATION.md` before milestone close; extensibility spot-check confirms new tools still register via `ToolFeature`.

**Key work themes:**
- Verify orphaned UX-03/04 from v1.0 Phase 6
- Hub-level helper health surfacing
- Milestone-level QA gate and audit prep

**Plans:** TBD (via `/gsd-plan-phase 10`)

---

## Requirement Coverage (v1.1)

| Phase | Requirements | Count |
|-------|--------------|-------|
| Phase 7 | DL-01–DL-10 | 10 |
| Phase 8 | REC-01–REC-06 | 6 |
| Phase 9 | CONV-06, CONV-07, HUB-01 | 3 |
| Phase 10 | UX-03–UX-06, QA-01, QA-02 | 6 |

**Coverage check:** 25 / 25 v1.1 requirements mapped.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1–6 | v1.0 | 15/19 | Shipped | 2026-05-11 |
| 7. Downloader Reliability | v1.1 | 3/3 | Complete (human UAT pending) | 2026-05-23 |
| 8. Real Core Audio Capture | v1.1 | 2/2 | Complete (human UAT pending) | 2026-05-23 |
| 9. Converter & Inbox UAT | v1.1 | 1/1 | Complete (human UAT pending) | 2026-05-23 |
| 10. Hub Polish & QA | v1.1 | 1/1 | Complete (human UAT pending) | 2026-05-23 |
| 11. Archive Persistence | v1.2 | 2/2 | Complete | 2026-05-30 |
| 12. Metadata Core | v1.2 | 2/2 | Complete | 2026-05-30 |
| 13. Smart Shelves | v1.2 | 1/1 | Complete | 2026-05-30 |
| 14. Waveform Player | v1.2 | 1/1 | Complete | 2026-05-30 |
| 15. Browse & Collaborators | v1.2 | 0/? | Pending | — |
| 16. Filters, BPM & Polish | v1.2 | 0/? | Pending | — |
| 17. New Song Flow | v1.2 | 0/? | Pending | — |
| 18. Read-Only Intelligence | v1.2 | 0/? | Pending | — |

### 🚧 v1.2 Cubase Archive Recall

- [x] **Phase 11: Archive Persistence** — SQLite index + FSEvents debounced rescan *(CP-01, CP-02 — 2026-05-30)*
- [x] **Phase 12: Metadata Core** — First-run roots, virtual title, editable notes, manual main preview *(CP-03–CP-06 — 2026-05-30)*
- [x] **Phase 13: Smart Shelves** — Recently Bounced, Recent CPR Activity *(CP-07 — 2026-05-30)*
- [x] **Phase 14: Waveform Player** — Waveform hero + seek on song detail *(CP-08 — 2026-05-30)*
- [ ] **Phase 15: Browse & Collaborators** — Home shelves UI, collaborators, CPR override, shortcuts, search *(CP-09–CP-13)*
- [ ] **Phase 16: Filters, BPM & Polish** — Sort/filter chips, health report, mixdown BPM, CPR list polish *(CP-14–CP-16)*
- [ ] **Phase 17: New Song Flow** — Create folder, template, register, open Cubase *(CP-17)*
- [ ] **Phase 18: Read-Only Intelligence** — Collaborator suggestions, CPR plugin summary, duplicates/missing reports, index export *(CP-18)*

Autonomous: `/gsd-autonomous --from 12 --to 18` (phase 11 done). Goal file: `docs/goals/niko-archive-recall-autonomous.goals.md`.

## Phase Details (v1.2)

### Phase 11: Archive Persistence

**Goal:** Persist archive scan results and refresh on filesystem changes without full manual rescan every launch.

**Depends on:** v1.1 complete

**Success criteria:**
1. Relaunch with unchanged roots shows cached songs before Scan.
2. SQLite store under Application Support; read-only toward music roots.
3. FSEvents debounced rescan when files change under roots.
4. `./script/ci.sh` green.

**Plans:** `11-01-PLAN.md`, `11-02-PLAN.md` (complete)

---

### Phase 12: Metadata Core

**Goal:** App-owned metadata layer — virtual titles, editable notes, manual preview selection, first-run root UX.

**Depends on:** Phase 11

**Success criteria:**
1. Virtual rename changes display title only (disk folder unchanged).
2. Song notes persist in app DB and appear in search.
3. User can pick main preview and revert to auto.
4. First-run / empty roots guided flow.
5. `./script/ci.sh` green.

**Checkpoints:** CP-03, CP-04, CP-05, CP-06

---

### Phase 13: Smart Shelves

**Goal:** Browse by recency — Recently Bounced and Recent CPR Activity shelves per SPEC §10.

**Depends on:** Phase 12

**Success criteria:**
1. Shelves filter songs by mixdown/CPR recency signals.
2. Fixture tests document shelf rules.
3. `./script/ci.sh` green.

**Checkpoint:** CP-07

---

### Phase 14: Waveform Player

**Goal:** Song detail waveform hero with seek controls (Fruity Server / DAW PM parity).

**Depends on:** Phase 13

**Success criteria:**
1. Waveform renders for main preview on detail.
2. Seek ±5s (and optional ±30s) updates playback.
3. `./script/ci.sh` and `./script/e2e_user_smoke.sh` pass.

**Checkpoint:** CP-08

---

### Phase 15: Browse & Collaborators

**Goal:** Editorial browse home, collaborators address book, CPR override, hide/ignore, keyboard shortcuts, extended search.

**Depends on:** Phase 14

**Success criteria:**
1. Home browse with curated shelves (not flat list only); Has Stems shelf.
2. Collaborators assignable; By Collaborator shelf and search.
3. Main CPR override + hide song/candidate.
4. Shortcuts P/O/D/F pattern when archive focused.
5. `./script/ci.sh` green.

**Checkpoints:** CP-09–CP-13

---

### Phase 16: Filters, BPM & Polish

**Goal:** Sort modes, filter chips, archive health summary, BPM from mixdown, full CPR list UI.

**Depends on:** Phase 15

**Success criteria:**
1. Sort by recent bounce, recent CPR, title.
2. Health report counts (no preview, no CPR, warnings) — read-only.
3. BPM displayed on detail from main mixdown (optional SPM).
4. `./script/ci.sh` green.

**Checkpoints:** CP-14, CP-15, CP-16

---

### Phase 17: New Song Flow

**Goal:** Create new song folder from app, optional template, register in index, open Cubase.

**Depends on:** Phase 16

**Success criteria:**
1. Modal collects name, collaborators, template, note.
2. Creates `Mixdown` / `Stems` subfolders under chosen root (test uses temp dir).
3. `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1` for CI open path.
4. `./script/ci.sh` green.

**Checkpoint:** CP-17

---

### Phase 18: Read-Only Intelligence

**Goal:** Collaborator suggestions, read-only CPR/plugin insight, duplicate/missing audio reports, JSON export for agents.

**Depends on:** Phase 17

**Success criteria:**
1. No destructive cleanup actions in UI.
2. Suggestion review yes/no; export index JSON from fixture scan.
3. `./script/ci.sh` green.

**Checkpoint:** CP-18

**Out of scope (v1.2):** CP-19 — multi-DAW, cloud sync, AI search, delete-unused-audio.

---

## Requirement Coverage (v1.2)

| Phase | Checkpoints | Count |
|-------|-------------|-------|
| Phase 11 | CP-01, CP-02 | 2 |
| Phase 12 | CP-03–CP-06 | 4 |
| Phase 13 | CP-07 | 1 |
| Phase 14 | CP-08 | 1 |
| Phase 15 | CP-09–CP-13 | 5 |
| Phase 16 | CP-14–CP-16 | 3 |
| Phase 17 | CP-17 | 1 |
| Phase 18 | CP-18 | 1 |

---

## Roadmap Notes

- v1.0 audit: 20/32 requirements satisfied; 12 gaps drive v1.1 scope (see `.planning/v1.0-v1.0-MILESTONE-AUDIT.md`).
- v1.2 defined 2026-05-30 from competitive analysis; execute via goal file or `/gsd-autonomous --from 11`.
- Downloader root cause documented in `.planning/debug/downloader-yt-dlp-failure.md`.
- Uncommitted workspace (FeatureDownloader, AppCore errors) assigned to Phase 7 (DL-10).
- BPM tapper is production-ready from v1.0; no v1.1 phase unless regressions found during hub polish.

---
*Roadmap created: 2026-05-04*
*Last updated: 2026-05-30 — v1.2 phases 11–18 for GSD autonomous*
