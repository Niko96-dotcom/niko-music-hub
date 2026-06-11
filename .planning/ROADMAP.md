# Roadmap: Niko Music Hub

**Created:** 2026-05-04
**Updated:** 2026-06-11
**Granularity:** Standard
**Current milestone:** v1.4 Downloader Reliability (Phases 26–29)

## Milestones

- ✅ **v1.0 MVP** — Phases 1-6 (shipped 2026-05-11)
- ✅ **v1.1 Production-Ready Tools** — Phases 7-10 (shipped 2026-05-23)
- ✅ **v1.2 Cubase Archive Recall** — Phases 11-18 (shipped 2026-05-30)
- ✅ **v1.3 Full UI Redesign** — Phases 19-25 (shipped 2026-05-31)
- 🚧 **v1.4 Downloader Reliability** — Phases 26-29

**Requirements:** `.planning/REQUIREMENTS.md`
**Research:** `.planning/research/SUMMARY.md`
**Source audit:** 2026-06-11 downloader audit

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-6) — SHIPPED 2026-05-11</summary>

- [x] Phase 1: App Foundation and Tool Architecture
- [x] Phase 2: BPM Tapper
- [x] Phase 3: Cubase-Ready WAV Conversion
- [x] Phase 4: Internal Audio Recorder
- [x] Phase 5: Downloader Hub
- [x] Phase 6: Integration Polish and Extensibility Check

Archive: `.planning/milestones/v1.0-phases/`, `.planning/milestones/v1.0-ROADMAP.md`

</details>

<details>
<summary>✅ v1.1 Production-Ready Tools (Phases 7-10) — SHIPPED 2026-05-23</summary>

- [x] Phase 7: Downloader Reliability & Error Surfacing
- [x] Phase 8: Real Core Audio Capture & Recorder UAT
- [x] Phase 9: Converter & Output Inbox Handoff UAT
- [x] Phase 10: Hub Polish, Helper Health & Verification Discipline

Archive: `.planning/milestones/v1.1-phases/`

</details>

<details>
<summary>✅ v1.2 Cubase Archive Recall (Phases 11-18) — SHIPPED 2026-05-30</summary>

- [x] Phase 11: Archive Persistence
- [x] Phase 12: Metadata Core
- [x] Phase 13: Smart Shelves
- [x] Phase 14: Waveform Player
- [x] Phase 15: Browse & Collaborators
- [x] Phase 16: Filters, BPM & Polish
- [x] Phase 17: New Song Flow
- [x] Phase 18: Read-Only Intelligence

Archive: `.planning/milestones/v1.2-phases/`, `.planning/milestones/v1.2-ROADMAP.md`

</details>

<details>
<summary>✅ v1.3 Full UI Redesign (Phases 19-25) — SHIPPED 2026-05-31</summary>

- [x] Phase 19: Design System Foundation
- [x] Phase 20: Shell & Navigation
- [x] Phase 21: Tool UI — BPM, Recorder, Converter
- [x] Phase 22: Tool UI — Downloader & Settings
- [x] Phase 23: Archive Browse & Sidebar
- [x] Phase 24: Archive Detail & Panels
- [x] Phase 25: UI Polish & Visual Regression

Phase working docs currently remain under `.planning/phases/`.

</details>

### 🚧 v1.4 Downloader Reliability

- [x] **Phase 26: Downloader Command Truth** — Real progress markers, format-aware simulate, no fixed total download timeout, stall handling, UTF-8-safe output collection.
- [x] **Phase 27: Helper Health and Output Contract** — Outdated helper detection, update guidance, retry/title fixes, structured output URL handoff.
- [x] **Phase 28: Media Handoff and Downloader UX Finish** — Safe reveal/open/drag for downloader media and inbox media affordance polish.
- [ ] **Phase 29: Real-World Downloader UAT** — Deterministic coverage plus opt-in/live downloader evidence for progress, helper paths, success, failure, and media handoff.

## Phase Details (v1.4)

### Phase 26: Downloader Command Truth

**Goal:** The downloader command path tells the truth: real progress appears, selected formats are preflighted, long valid downloads are not killed by a stopwatch, and output collection is resilient.

**Depends on:** v1.4 requirements/research

**Requirements:** CMD-01, CMD-02, CMD-03, CMD-04, CMD-05

**Success criteria:**
1. `YtDlpDownloader` emits explicit parseable progress markers from the real command, and `DownloaderUseCase` updates job progress from those markers.
2. Actual downloads no longer set the fixed 90-second total process timeout.
3. A deterministic stall detector fails silent/stuck downloads with a clear message.
4. Simulate/preflight uses the selected format arguments and `--no-playlist`.
5. Streaming output collection handles split UTF-8 and/or reparses final stdout/stderr so final file markers are not lost.

**Key files:** `YtDlpDownloader.swift`, `DownloaderUseCase.swift`, `ExternalProcessRunning.swift`, `DownloadFormatSelection.swift`, `Tests/FeatureDownloaderTests/*`, `Tests/AppCoreTests/*`

**Research flags:** Pick exact stall window during planning and keep it testable without sleeping in real time.

**Plans:** 3 plans

Plans:
- [ ] 26-01-PLAN.md — NIKO_PROGRESS template + parser alignment; remove 90s download timeout (CMD-01, CMD-02)
- [ ] 26-02-PLAN.md — Stall detection with injectable 120s clock (CMD-03)
- [ ] 26-03-PLAN.md — Format-aware simulate + UTF-8 output collection + CMD test matrix (CMD-04, CMD-05)

---

### Phase 27: Helper Health and Output Contract

**Goal:** The app classifies downloader helper health accurately and moves completed file URLs through a structured contract instead of diagnostic logs.

**Depends on:** Phase 26

**Requirements:** HLTH-01, HLTH-02, HLTH-03, HLTH-04, OUT-01, OUT-02, OUT-03

**Success criteria:**
1. `YtDlpHealthChecker` can return missing, unusable, available, and outdated states, including date-like version tests.
2. User-facing copy points stale helpers to the existing helper update flow.
3. Retry classification covers real transient messages including `timed out`, socket/read timeouts, connection resets, temporary failures, and HTTP 5xx errors.
4. Downloader jobs use meaningful titles based on metadata/preflight output instead of URL path fragments like `watch`.
5. Completed downloader output URLs are passed to inbox ingestion through typed data; removing synthetic `[download] Destination:` logs does not break inbox creation.
6. Diagnostic logs remain available for debugging and verification, but are not the source of truth.

**Key files:** `YtDlpHealthChecker.swift`, `DownloaderUseCase.swift`, `DownloaderJobFactory.swift`, `JobRunner.swift`, `OutputInboxStore.swift`, `DownloaderCopy.swift`, `Tests/FeatureDownloaderTests/*`, `Tests/AppCoreTests/*`

**Research flags:** Choose staleness policy during planning: 60 days, 90 days, or latest-known-release delta.

---

### Phase 28: Media Handoff and Downloader UX Finish

**Goal:** Completed downloader media is useful from the Output Inbox: reveal, open, drag, and scan at a glance without weakening WAV safety for converter/recorder outputs.

**Depends on:** Phase 27

**Requirements:** HAND-01, HAND-02, HAND-03, HAND-04, HAND-05

**Success criteria:**
1. Output handoff allows safe completed downloader media extensions such as MP3, M4A, MP4, and WEBM.
2. Converter/recorder WAV verification remains strict and does not regress.
3. Output Inbox context menu and tap/drag behavior work for allowed downloader media.
4. Output Inbox icons/status distinguish common audio and video media types.
5. Tests cover both allowed downloader media and disallowed/missing/pending files.

**Key files:** `OutputHandoff.swift`, `OutputInboxInspectorView.swift`, `OutputInboxItem.swift`, `FeatureDownloader` job integration, `Tests/AppCoreTests/OutputHandoffTests.swift`, app shell tests

**Research flags:** Decide whether WEBM is drag-ready or reveal/open only during planning.

---

### Phase 29: Real-World Downloader UAT

**Goal:** Close the mock-reality gap with documented proof that downloader reliability works in the app and in app-like environments.

**Depends on:** Phase 28

**Requirements:** UAT-01, UAT-02, UAT-03, UAT-04

**Success criteria:**
1. Deterministic automated tests cover progress markers, stall handling, helper health, structured output handoff, and media handoff.
2. Opt-in/live downloader verification exercises real `yt-dlp` behavior beyond the previous 18-second happy path.
3. Helper-path verification covers an app-like stripped environment and confirms `--ffmpeg-location` still fixes post-processing.
4. UAT evidence documents success, failure, progress, stale helper guidance, and media handoff flows.
5. `./script/ci.sh` and `./script/e2e_user_smoke.sh` are green before milestone close.

**Key files:** `script/ci.sh`, `script/e2e_user_smoke.sh`, new/updated downloader smoke script, `docs/` UAT evidence, `Tests/FeatureDownloaderTests/*`

**Research flags:** Pick stable legal live URLs and keep live network checks opt-in so local CI remains deterministic.

---

## Requirement Coverage (v1.4)

| Phase | Requirements | Count |
|-------|--------------|-------|
| Phase 26 | CMD-01–CMD-05 | 5 |
| Phase 27 | HLTH-01–HLTH-04, OUT-01–OUT-03 | 7 |
| Phase 28 | HAND-01–HAND-05 | 5 |
| Phase 29 | UAT-01–UAT-04 | 4 |

**Coverage check:** 21 / 21 v1.4 requirements mapped.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1–6 | v1.0 | 15/19 | Shipped | 2026-05-11 |
| 7–10 | v1.1 | 7/7 | Shipped | 2026-05-23 |
| 11–18 | v1.2 | 11/11 | Shipped | 2026-05-30 |
| 19–25 | v1.3 | 13/13 | Shipped | 2026-05-31 |
| 26. Downloader Command Truth | v1.4 | 3/3 | Complete | 2026-06-11 |
| 27. Helper Health and Output Contract | v1.4 | 1/1 | Complete | 2026-06-11 |
| 28. Media Handoff and Downloader UX Finish | v1.4 | 1/1 | Complete | 2026-06-11 |
| 29. Real-World Downloader UAT | v1.4 | 0/TBD | Pending | — |

## Next Up

**Phase 29: Real-World Downloader UAT** — deterministic coverage plus opt-in/live downloader evidence.

`$gsd-plan-phase 29`
