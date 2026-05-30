---
phase: "10"
name: "hub-polish-helper-health-verification-discipline"
status: human_needed
completed: "2026-05-23"
requirements: ["UX-03", "UX-04", "UX-05", "UX-06", "QA-01", "QA-02"]
---

## Phase 10 Verification

### Automated

| Requirement | Evidence |
|-------------|----------|
| QA-01 | `scripts/test.sh` — 0 failures (permission skips documented) |
| QA-02 | VERIFICATION.md present for phases 7, 8, 9, 10 |
| UX-05 | `HelperToolsHealthStrip` + `FFmpegHealthChecker.detectFfmpeg()` |
| UX-06 | Recorder/Downloader/Converter use `StandardErrorCard` / `AppErrorCard` |

### Spot-check (code)

| Requirement | Evidence |
|-------------|----------|
| UX-03 | `StandardErrorCard` in BPM tapper, converter, downloader, recorder |
| UX-04 | Space: BPM tapper + recorder; Escape: converter + downloader |
| Extensibility | `AppComposition` registers `ToolFeature` modules (bpm, converter, recorder, downloader, dev) |

### Human

- [ ] Sidebar helper lines match installed yt-dlp/FFmpeg (or show install guidance).
- [ ] Keyboard shortcuts work in running app.

---

## Permission skips

Recorder integration tests: 6 skips when system audio permission not granted (documented in Phase 8 VERIFICATION).
