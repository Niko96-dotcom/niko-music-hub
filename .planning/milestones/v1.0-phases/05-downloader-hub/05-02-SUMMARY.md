---
phase: "05-downloader-hub"
plan: "05-02"
status: "complete"
wave: "2"
completed: "2026-05-11"
depends_on: ["05-01"]
---

## Summary

Built the URL input surface, simulate pre-check, and download job flow for the Downloader Hub.

### What was built

**DownloaderJobFactory.swift**
- `DownloadJobOptions` struct with `sourceURL`, `outputDirectory`, `fileNameTemplate`, `retries: Int = 3`
- Factory method `makeJobOptions()` for creating job configurations

**DownloaderUseCase.swift**
- `DownloadUseCaseError` enum: `.ytDlpUnavailable`, `.unsupportedURL`, `.downloadFailed`, `.outputNotFound`
- `simulateAndEnqueue(url:options:) async throws -> Job`
  - Checks yt-dlp availability before proceeding
  - Runs simulate download to validate URL is supported
  - Enqueues actual download job through `JobRunner`
- Retry with exponential backoff (2s, 4s, 8s)
- Progress parsing from yt-dlp stderr lines
- Transient error detection (HTTP 5xx, connection reset, timeout)

**DownloaderViewModel.swift**
- `DownloadState` enum: `.idle`, `.checkingURL`, `.readyToDownload`, `.downloading`, `.completed`, `.failed(String)`
- `@MainActor` class with `@Published` properties for UI binding
- `urlTextDidChange()` with 500ms debounce for simulate check
- `startDownload()` transitions to `.downloading` state
- Job observation via `observeJob(id:)` polling `context.jobRunner.job(id:)`
- Output files added to inbox with `dlSourceURL` metadata

**DownloaderFeature.swift**
- `ToolMetadata` with `id: "downloader"`, `.producesFiles`, `.runsJobs`
- Creates `YtDlpDownloader`, `YtDlpHealthChecker`, `DownloaderUseCase`, `DownloaderViewModel` and wires them together

**DownloaderView.swift**
- URL text field with debounced `urlTextDidChange` binding
- Download button (enabled only in `.readyToDownload` state)
- Clear button to reset
- Trust info section showing Source URL, Output folder, and trust notice
- Progress bar during download
- Scrollable log area showing yt-dlp stderr lines
- Error section with actionable recovery buttons

### Requirements addressed
- [DL-01] User can paste or enter a supported website URL for download
- [DL-03] User can start a download job with output location and basic options
- [D-01] Explicit Download button after URL paste + --simulate pre-check
- [D-02] Before enqueueing, app runs --simulate to confirm yt-dlp can handle URL