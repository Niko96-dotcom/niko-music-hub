---
phase: "07"
name: "downloader-reliability-error-surfacing"
status: human_needed
completed: "2026-05-23"
requirements: ["DL-01", "DL-02", "DL-03", "DL-04", "DL-05", "DL-06", "DL-07", "DL-08", "DL-09", "DL-10"]
---

## Phase 7 Verification: Downloader Reliability & Error Surfacing

### Summary

Simulate gate blocks job enqueue on non-zero yt-dlp exit. Failures prefer stderr in `DownloadUseCaseError.downloadFailed` and `StandardErrorCard` body. FeatureDownloader + AppCore error components landed with automated tests (153 pass, 6 permission skips).

---

## Automated Evidence

| Requirement | Evidence |
|-------------|----------|
| DL-08 | `DownloaderUseCaseTests.testSimulateFailureDoesNotEnqueueJob` — enqueueCount 0 on exit 1 |
| DL-09 | `testYtDlpFailureMessagePrefersStderr`; simulate throws `downloadFailed` with stderr text |
| DL-06 | Existing `YtDlpDownloaderTests` — executableURL + args, no shell |
| DL-02 | `YtDlpHealthCheckerTests` — missing/available/unusable |
| DL-07 | `DownloaderTrustAndErrorTests` — trustNotice, labels |
| DL-10 | FeatureDownloader + AppCore/Errors committed; `AppComposition` registers `DownloaderFeature` |

### Retroactive DL-01–DL-05 (v1.0 implementation + Phase 7)

| Requirement | Status | Notes |
|-------------|--------|-------|
| DL-01 | verified (code) | URL field + debounce; simulate at download |
| DL-02 | verified (code) | Health checker in VM + use case |
| DL-03 | verified (code) | Explicit Download + output folder in trust strip |
| DL-04 | verified (code) | Progress, logs, error card |
| DL-05 | verified (code) | `addToInbox` with dlSourceURL metadata |
| DL-06 | verified (tests) | Shell-safety tests pass |
| DL-07 | verified (tests) | Trust notice in ready/downloading states |

---

## Test Suite

```
scripts/test.sh — 153 executed, 0 failures, 6 skipped (permission)
```

New: `DownloaderUseCaseTests` (4 tests).

---

## Human Verification (required on target Mac)

- [ ] Paste invalid YouTube URL → error card body shows yt-dlp stderr (e.g. "Video unavailable"), not generic-only.
- [ ] Paste valid URL → Download completes OR shows actionable stderr on failure.
- [ ] Trust notice visible before pressing Download (ready state).
- [ ] Retry on error card returns to ready state.

---

## Security

- Simulate and download use `Process.executableURL` + `[String]` arguments only (no shell interpolation).

---

## Phase Status

**Automated:** passed  
**Human UAT:** pending (YouTube/network on producer Mac)
