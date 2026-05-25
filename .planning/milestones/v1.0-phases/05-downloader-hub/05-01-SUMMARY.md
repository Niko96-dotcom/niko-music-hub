---
phase: "05-downloader-hub"
plan: "05-01"
status: "complete"
wave: "1"
completed: "2026-05-11"
---

## Summary

Created yt-dlp health checker and safe command adapter following the FFmpegHealthChecker pattern exactly.

### What was built

**YtDlpHealthChecker.swift**
- `YtDlpAvailability` enum with `.missing`, `.available(version:)`, `.outdated(current:minimumExpected:)`, `.unusable(message:)`
- Follows FFmpegHealthChecker pattern: injectable `runner: any ExternalProcessRunning` and `fileExists` closure
- `availability(settings: HelperToolSettings) async -> YtDlpAvailability`
- Uses `executableURL` + `[String]` argument array, never shell string interpolation
- Returns typed availability states instead of crashing on missing tool

**YtDlpDownloader.swift**
- `DownloadRequest` struct with `ytDlpURL`, `sourceURL`, `outputDirectory`, `outputTemplate`
- `DownloadResult` struct with `outputURLs`, `sourceURL`, `exitCode`, `standardError`
- `DownloadError` enum implementing `LocalizedError`
- `DownloadRunning` protocol for testability
- `YtDlpDownloader: DownloadRunning` using explicit `executableURL` + argument array
- URL passed as distinct argument element (NOT concatenated into command string)
- `--newline` for line-by-line stderr output
- `--progress-template` and `-o` for output path control

### Files created
- `Sources/FeatureDownloader/YtDlpHealthChecker.swift`
- `Sources/FeatureDownloader/YtDlpDownloader.swift`
- `Tests/FeatureDownloaderTests/YtDlpHealthCheckerTests.swift`
- `Tests/FeatureDownloaderTests/YtDlpDownloaderTests.swift`

### Security
- No `/bin/sh`, `sh -c`, or shell string interpolation in any downloader source file
- All shell safety tests pass
- Process launch uses Foundation's `Process.executableURL` + `arguments` array only

### Requirements addressed
- [DL-02] App detects yt-dlp version and reports missing/outdated helper state
- [DL-06] Downloader passes URLs and arguments safely without shell string interpolation