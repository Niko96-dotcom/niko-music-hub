---
phase: "05-downloader-hub"
plan: "05-03"
status: "complete"
wave: "3"
completed: "2026-05-11"
depends_on: ["05-02"]
---

## Summary

Implemented real-time progress parsing from yt-dlp stderr, retry with exponential backoff, and inbox output with dlSourceURL metadata.

### What was built

**YtDlpDownloader.swift enhancements**
- `progressHandler` now called for each stderr line in real-time
- Progress percentage parsing from `[download] X%` lines via `parseProgressPercentage()`
- Output URL tracking from `[download] Destination:` lines

**DownloaderUseCase.swift enhancements**
- Retry with exponential backoff: 2s, 4s, 8s between retries
- Transient error detection (HTTP 5xx, connection reset, timeout, temporary failure)
- Permanent errors (404, unsupported) fail immediately without retry
- Progress flows through `JobProgress.update()` and `JobProgress.log()`
- Output files collected and added to inbox with `dlSourceURL` metadata

**DownloaderViewModel.swift**
- Job observation via polling loop with 100ms intervals
- Log entries accumulated from `job.logEntries`
- Output URLs extracted from `[download] Destination:` log entries
- Items added to output inbox with metadata `["dlSourceURL": sourceURL]`

**DownloadProgressParsingTests.swift**
- Tests for progress percentage parsing (45.2%, 50%, 33.3%, etc.)
- Tests confirming non-progress lines return nil

### Requirements addressed
- [DL-04] Download jobs show progress, logs, completion, and errors
- [DL-05] Downloaded files added to inbox with dlSourceURL metadata
- [D-03] yt-dlp runs with --newline for line-by-line stderr output
- [D-04] Progress flows through JobProgress interface
- [D-05] Raw yt-dlp output logged, errors actionable
- [D-09] 3 retries with exponential backoff (2s, 4s, 8s)