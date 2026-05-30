# Milestones

## v1.2 Cubase Archive Recall — 2026-05-30

**Status:** ✅ SHIPPED  
**Phases:** 11–18 (8 phases, 9 plans)  
**Checkpoints:** CP-01–CP-18 (CP-19+ deferred)

### Key Accomplishments

1. SQLite archive index + FSEvents debounced rescan (Phase 11)
2. Virtual titles, notes, manual preview, first-run roots UX (Phase 12)
3. Recently Bounced and Recent CPR Activity smart shelves (Phase 13)
4. Waveform hero with seek on song detail (Phase 14)
5. Collaborators, shelves, CPR override, hide, shortcuts, extended search (Phase 15)
6. Sort/filter chips, archive health report, mixdown BPM on detail (Phase 16)
7. New song folder flow with dry-run Cubase open in CI (Phase 17)
8. Read-only intelligence panel and JSON index export for agents (Phase 18)

### Known deferred / tech debt

See `.planning/milestones/v1.2-MILESTONE-AUDIT.md`. Known deferred items at close: 6 (see STATE.md Deferred Items).

### Archives

- Roadmap: `.planning/milestones/v1.2-ROADMAP.md`
- Requirements: `.planning/milestones/v1.2-REQUIREMENTS.md`
- Phases: `.planning/milestones/v1.2-phases/`

---

## v1.1 Production-Ready Tools — 2026-05-23

**Status:** ✅ SHIPPED  
**Phases:** 7–10  
**Requirements:** 25 (archived with milestone)

### Goal

Close the gap between v1.0 "implemented" and reliable daily Cubase prep on the target Mac.

### Key accomplishments

1. Downloader stderr surfacing and simulate/enqueue fixes (Phase 7)
2. Real Core Audio process tap for recorder (Phase 8)
3. Output inbox live refresh (Phase 9)
4. Helper health strip and verification discipline (Phase 10)

---

## v1.0 MVP — 2026-05-11

**Status:** ✅ SHIPPED
**Phases:** 6 (Phase 1 through Phase 6)
**Plans:** 19 total, 15 completed
**Requirements:** 20/32 satisfied (12 gaps accepted as known)

### Stats

- Files modified: 172
- Lines of code: 6,353 Swift
- Timeline: 7 days (2026-05-04 → 2026-05-11)
- Commits: 111

### Key Accomplishments

1. Native SwiftUI macOS app with registry-driven tool navigation (Phase 1)
2. BPM tapper with keyboard/mouse input, live estimate, half/double adjustments, and local history (Phase 2)
3. Cubase-ready WAV conversion with native AVFAudio first and FFmpeg fallback (Phase 3)
4. CoreAudioTapAdapter with permission flow and WAV writer (Phase 4, synthetic audio)
5. Downloader hub with yt-dlp adapter and safe command execution (Phase 5)
6. Integration polish with error language, keyboard shortcuts, and extensibility verification (Phase 6)

### Known Gaps

- REC-01-06: Phase 4 uses synthetic audio — real Core Audio process tap verification pending
- DL-01-07: Phase 5 completed plans but no VERIFICATION.md produced
- UX-03-04: Phase 6 completed plans but no VERIFICATION.md produced

### Deferred Items

See STATE.md Deferred Items section (3 items)

