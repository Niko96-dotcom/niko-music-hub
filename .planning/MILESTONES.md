# Milestones

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

---

## v1.1 Production-Ready Tools — 2026-05-23

**Status:** 🚧 IN PROGRESS (planning complete)
**Phases:** 7–10
**Requirements:** 25 (see `.planning/REQUIREMENTS.md`)

### Goal
Close the gap between v1.0 "implemented" and reliable daily Cubase prep on the target Mac.

### Phase outline
1. **Phase 7:** Downloader reliability & error surfacing (DL-01–DL-10)
2. **Phase 8:** Real Core Audio capture & recorder UAT (REC-01–REC-06)
3. **Phase 9:** Converter & output inbox handoff UAT (CONV-06/07, HUB-01)
4. **Phase 10:** Hub polish, helper health, verification discipline (UX-03–06, QA-01–02)

### Inputs
- v1.0 milestone audit: `.planning/v1.0-v1.0-MILESTONE-AUDIT.md`
- Downloader debug: `.planning/debug/downloader-yt-dlp-failure.md`
- Test baseline: quick task 260523-2ec (`scripts/test.sh`, 149 tests)

---