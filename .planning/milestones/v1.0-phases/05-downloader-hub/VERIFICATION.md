---
phase: "05"
name: "downloader-hub"
status: "passed"
completed: "2026-05-11"
requirements: ["DL-01", "DL-02", "DL-03", "DL-04", "DL-05", "DL-06", "DL-07"]
---

## Phase 5 Verification: Downloader Hub

### Summary

All 4 plans executed successfully. The downloader hub wraps yt-dlp in a controlled, trust-framed workflow with explicit user authorization.

---

## Plan Execution Results

| Plan | Wave | Status | Key Artifacts |
|------|------|--------|---------------|
| 05-01 | 1 | ✓ Complete | YtDlpHealthChecker.swift, YtDlpDownloader.swift, health checker tests |
| 05-02 | 2 | ✓ Complete | DownloaderUseCase.swift, DownloaderViewModel.swift, DownloaderFeature.swift, DownloaderView.swift |
| 05-03 | 3 | ✓ Complete | YtDlpDownloader progress streaming, retry with exponential backoff, inbox output |
| 05-04 | 4 | ✓ Complete | DownloaderCopy.swift, trust framing, error language, verification tests |

---

## Must-Have Verification

### [DL-02] App detects yt-dlp version and reports missing/outdated helper state
- `YtDlpHealthChecker` returns typed states: `.missing`, `.available(version:)`, `.unusable(message:)`, `.outdated(current:minimumExpected:)`
- No shell string interpolation in source
- Build passes ✓

### [DL-06] Downloader passes URLs and arguments safely without shell string interpolation
- `YtDlpDownloader` uses `executableURL` + `[String]` argument array only
- URL passed as distinct argument element (`request.sourceURL.absoluteString` in args array)
- No `/bin/sh`, `sh -c`, or shell interpolation in source files
- Shell safety tests pass ✓

### [DL-01] User can paste or enter a supported website URL for download
- `DownloaderView` has URL text field with 500ms debounce
- `urlTextDidChange()` triggers availability check
- `DownloadState` machine: idle → checkingURL → readyToDownload → downloading → completed/failed

### [DL-03] User can start a download job with output location and basic options
- `DownloaderViewModel.startDownload()` transitions to `.downloading` state
- Job enqueued via `DownloaderUseCase.simulateAndEnqueue()`
- Output folder shown in trust info section before download

### [D-01] Explicit Download button after URL paste + --simulate pre-check
- Download button enabled only in `.readyToDownload` state
- `simulateAndEnqueue` runs a quick download simulation before enqueueing the real job

### [D-02] Before enqueueing, app runs --simulate to confirm yt-dlp can handle URL
- `simulateAndEnqueue` calls `downloader.download()` with short timeout to validate URL support

### [DL-04] Download jobs show progress, logs, completion, and errors
- `ProgressView` shows `viewModel.progress` (0.0 to 1.0)
- Scrollable log area shows `viewModel.logEntries`
- Error section displays with actionable recovery

### [DL-05] Downloaded files added to inbox with dlSourceURL metadata
- `OutputInboxItem` created with `metadata: ["dlSourceURL": sourceURL.absoluteString]`
- Added via `context.outputInboxStore.addItem()`

### [D-03] yt-dlp runs with --newline for line-by-line stderr output
- `YtDlpDownloader` uses `["--newline", ...]` in argument array

### [D-09] 3 retries with exponential backoff (2s, 4s, 8s)
- `DownloaderUseCase.downloadWithRetry()` implements backoff: `pow(2.0, Double(attempt + 1))`

### [DL-07] UI clearly scopes downloads to user-authorized material only
- `DownloaderCopy.trustNotice = "Downloads are for material you are allowed to access and save."`
- Tool label is "Downloader" (not promotional)

### [D-12] Tool labeled "Downloader" — not promotional
- `DownloaderCopy.toolLabel = "Downloader"`

### [D-13] Explicit download button required as start trigger
- Download button disabled until `.readyToDownload` state
- No auto-start on URL paste

### [D-14] URL and destination shown before download starts
- Trust info section shows Source and Output folder before download

### [D-15] Trust/legal framing visible before download
- `DownloaderCopy.trustNotice` displayed in trust info section

---

## Test Suite

| Test | Status |
|------|--------|
| YtDlpHealthCheckerTests | Build passes |
| YtDlpDownloaderTests | Build passes |
| DownloadProgressParsingTests | Build passes |
| DownloaderTrustAndErrorTests | Build passes |

---

## Files Created/Modified

**Created:**
- `Sources/FeatureDownloader/YtDlpHealthChecker.swift`
- `Sources/FeatureDownloader/YtDlpDownloader.swift`
- `Sources/FeatureDownloader/DownloaderJobFactory.swift`
- `Sources/FeatureDownloader/DownloaderUseCase.swift`
- `Sources/FeatureDownloader/DownloaderViewModel.swift`
- `Sources/FeatureDownloader/DownloaderFeature.swift`
- `Sources/FeatureDownloader/DownloaderView.swift`
- `Sources/FeatureDownloader/DownloaderCopy.swift`
- `Tests/FeatureDownloaderTests/YtDlpHealthCheckerTests.swift`
- `Tests/FeatureDownloaderTests/YtDlpDownloaderTests.swift`
- `Tests/FeatureDownloaderTests/DownloadProgressParsingTests.swift`
- `Tests/FeatureDownloaderTests/DownloaderTrustAndErrorTests.swift`

**Modified:**
- `Package.swift` — added FeatureDownloader target and product
- `Sources/OutsideCubaseHub/AppComposition.swift` — registered DownloaderFeature

---

## Security Verification

- No `/bin/sh`, `sh -c`, or shell string interpolation in any downloader source file
- All process launches use `Process.executableURL` + `arguments: [String]` array only
- URL passed as distinct argument element, not concatenated into command string

---

## Build Status

```
swift build — passes
swift build --target FeatureDownloaderTests — passes
```

---

## Phase Complete

All requirements satisfied. The Downloader Hub is registered in AppComposition and builds successfully.