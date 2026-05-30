# Roadmap: Niko Music Hub

**Created:** 2026-05-04  
**Granularity:** Standard  
**Current milestone:** None — v1.2 shipped 2026-05-30; plan next via `/gsd-new-milestone`

## Milestones

- ✅ **v1.0 MVP** — Phases 1-6 (shipped 2026-05-11)
- ✅ **v1.1 Production-Ready Tools** — Phases 7-10 (shipped 2026-05-23)
- ✅ **v1.2 Cubase Archive Recall** — Phases 11-18 (shipped 2026-05-30)

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

Archive: `.planning/milestones/v1.1-phases/` (after cleanup), `.planning/milestones/v1.1-ROADMAP.md` *(create on next archive pass if missing)*

</details>

<details>
<summary>✅ v1.2 Cubase Archive Recall (Phases 11-18) — SHIPPED 2026-05-30</summary>

- [x] Phase 11: Archive Persistence (2/2 plans) — CP-01, CP-02
- [x] Phase 12: Metadata Core (2/2 plans) — CP-03–CP-06
- [x] Phase 13: Smart Shelves (1/1 plan) — CP-07
- [x] Phase 14: Waveform Player (1/1 plan) — CP-08
- [x] Phase 15: Browse & Collaborators (2/2 plans) — CP-09–CP-13
- [x] Phase 16: Filters, BPM & Polish (1/1 plan) — CP-14–CP-16
- [x] Phase 17: New Song Flow (1/1 plan) — CP-17
- [x] Phase 18: Read-Only Intelligence (1/1 plan) — CP-18

Archive: `.planning/milestones/v1.2-phases/`, `.planning/milestones/v1.2-ROADMAP.md`, audit `.planning/milestones/v1.2-MILESTONE-AUDIT.md`

Goal file: `docs/goals/niko-archive-recall-autonomous.goals.md` (CP-01–CP-18 complete)

</details>

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1–6 | v1.0 | 15/19 | Shipped | 2026-05-11 |
| 7–10 | v1.1 | 7/7 | Shipped | 2026-05-23 |
| 11–18 | v1.2 | 9/9 | Shipped | 2026-05-30 |

## Roadmap Notes

- v1.2 audit: `.planning/milestones/v1.2-MILESTONE-AUDIT.md` — passed; tech debt documented (FSEvents full rescan, optional template picker, CPR plugin summary deferred).
- v1.1 human UAT still pending for phases 7–10 VERIFICATION files (non-blocking for v1.2 ship).
- Downloader debug: `.planning/debug/downloader-yt-dlp-failure.md`.
- P3 backlog (CP-19+): multi-DAW, cloud sync, AI search — out of scope unless new milestone.

---
*Last updated: 2026-05-30 — v1.2 milestone closed*
