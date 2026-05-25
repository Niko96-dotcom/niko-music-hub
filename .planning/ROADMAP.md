# Roadmap: Outside Cubase Hub

**Created:** 2026-05-04
**Granularity:** Standard
**Current milestone:** v1.1 Production-Ready Tools (Phases 7–10)

## Milestones

- ✅ **v1.0 MVP** — Phases 1-6 (shipped 2026-05-11)
- 🚧 **v1.1 Production-Ready Tools** — Phases 7-10 (in progress)

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

## Roadmap Notes

- v1.0 audit: 20/32 requirements satisfied; 12 gaps drive v1.1 scope (see `.planning/v1.0-v1.0-MILESTONE-AUDIT.md`).
- Downloader root cause documented in `.planning/debug/downloader-yt-dlp-failure.md`.
- Uncommitted workspace (FeatureDownloader, AppCore errors) assigned to Phase 7 (DL-10).
- BPM tapper is production-ready from v1.0; no v1.1 phase unless regressions found during hub polish.

---
*Roadmap created: 2026-05-04*
*Last updated: 2026-05-23 — v1.1 milestone Phases 7–10 defined*
