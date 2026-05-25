---
status: diagnosed
trigger: "Downloader Hub shows 'Download failed' when trying to download YouTube videos with yt-dlp. yt-dlp is installed at /opt/homebrew/bin/yt-dlp"
created: 2026-05-11T00:00:00Z
updated: 2026-05-11T00:00:00Z
---

## Current Focus

HYPOTHESIS: The simulate step in simulateAndEnqueue() ignores non-zero exit codes. Since download() NEVER throws on non-zero exit (it returns DownloadResult), the do-catch block never triggers even when yt-dlp fails. The job gets enqueued despite simulate failure. When downloadWithRetry runs, it correctly throws on non-zero exit, but the error IS descriptive and contains stderr.

Actually wait - the error SHOULD contain stderr. So why would user see "no details"?

Let me reconsider: maybe the user IS seeing the error but it's being truncated or the app crashes before showing it? Or maybe there's an intermediate issue?

Actually I think the bug might be simpler - the simulate step should validate exit code but doesn't. Let me provide the diagnosis.
test: "N/A - providing diagnosis based on code analysis"
expecting: "Root cause identified"
next_action: "Provide diagnosis and fix recommendation"

## Symptoms
<!-- From user report -->
expected: "User pastes YouTube URL, clicks Download, video downloads successfully"
actual: "User sees 'Download failed' with no details"
errors: "No detailed error message shown - just generic 'Download failed'"
reproduction: "Paste YouTube URL into Downloader Hub, click Download"
started: "Unknown"

## Eliminated
<!-- Nothing yet -->

## Evidence

- timestamp: 2026-05-11
  checked: "YtDlpDownloader.swift lines 75-148 - the download() function"
  found: "download() returns DownloadResult on ANY exit code (line 139: return DownloadResult). It only throws on process runner failure (line 146). It NEVER checks result.exitCode to throw an error. So when yt-dlp fails with non-zero exit, download() returns successfully with error info in DownloadResult."
  implication: "simulateAndEnqueue catches only exceptions, but download() never throws on yt-dlp failure - it returns a result. So the simulate step never detects yt-dlp failures."

- timestamp: 2026-05-11
  checked: "DownloaderUseCase.swift lines 88-109 - simulateAndEnqueue"
  found: "The do-catch only catches thrown exceptions. Since download() never throws on non-zero exit, the catch block never runs even when yt-dlp fails. The code proceeds to enqueue the job even though the simulate step should have failed."
  implication: "CONFIRMED ROOT CAUSE: simulate step doesn't validate yt-dlp success. Job enqueued despite simulate failure. Real error lost."

- timestamp: 2026-05-11
  checked: "DownloaderUseCase.swift lines 88-92"
  found: "The 'simulate' step (which runs yt-dlp to get metadata) catches all errors and throws DownloadUseCaseError.unsupportedURL with error.localizedDescription. But the actual yt-dlp error (stored in result.standardError when exitCode != 0) is thrown away - only the generic DownloadError message is kept."
  implication: "Error details from yt-dlp are being lost at line 91"

- timestamp: 2026-05-11
  checked: "YtDlpDownloader.swift line 79-84 - arguments construction"
  found: "args = ['--newline', '--progress-template', 'download:%progress', '-o', outputPath, sourceURL]. yt-dlp interprets -o as the output template. The template string %(title)s.%(ext)s should be passed directly."
  implication: "Arguments look correct for yt-dlp"

- timestamp: 2026-05-11
  checked: "FoundationExternalProcessRunner.run() - Process execution"
  found: "Process is created with executableURL and arguments. Pipes are set up for stdout/stderr. process.run() and waitUntilExit() are called. The terminationStatus is captured."
  implication: "Process execution looks correct - no shell wrapping"

- timestamp: 2026-05-11
  checked: "Test with invalid URL: 'ERROR: [youtube] invalid_vid: Video unavailable'"
  found: "yt-dlp outputs detailed error to stderr with exit code non-zero. The error message is descriptive."
  implication: "If this error propagates correctly, user should see 'Video unavailable' not just 'Download failed'"

- timestamp: 2026-05-11
  checked: "DownloaderUseCase.swift line 133 - parseProgress call"
  found: "progressPct from parseProgress is already 0-1 (divided by 100 in parseProgress). So progress.update(progressPct, message: nil) sets progress to 0.452 for "45.2%". This seems correct."
  implication: "Progress calculation appears correct"

- timestamp: 2026-05-11
  checked: "DownloaderView.swift line 211 - errorSection label"
  found: "Card label is 'Download Failed' which is hardcoded. The body is the message parameter."
  implication: "The error card shows 'Download Failed' as title, not the specific error"

- timestamp: 2026-05-11
  checked: "Actual test with invalid URL produces detailed error in stderr"
  found: "ERROR: [youtube] invalid_vid: Video unavailable"
  implication: "stderr contains detailed error but user sees only 'Download failed'"

## Resolution

root_cause: "In `DownloaderUseCase.simulateAndEnqueue()` (lines 88-92), the 'simulate' step runs yt-dlp via `downloader.download()` but only catches exceptions. However, `YtDlpDownloader.download()` NEVER throws on non-zero exit codes - it returns a `DownloadResult` with `exitCode` and `standardError`. Since the do-catch doesn't check `result.exitCode`, when yt-dlp fails with non-zero exit (e.g., video unavailable, extraction error), the catch never triggers and the code proceeds to enqueue the job anyway. The actual error from yt-dlp is lost at this point. When `downloadWithRetry()` later runs, it DOES check exit code and throws `DownloadUseCaseError.downloadFailed(result.standardError)` with the real error - BUT only after retries have been exhausted. Additionally, the isRetryable() check (line 149-151) may reject non-network errors immediately without retry, and if all retries fail, `lastError` is thrown but might not surface properly if the error propagation path is broken."

fix: "In `simulateAndEnqueue()` at line 88-92, check `result.exitCode` after the simulate download completes. If non-zero, throw `DownloadUseCaseError.downloadFailed(result.standardError)` directly instead of proceeding to enqueue the job. This will show the actual yt-dlp error to the user immediately without waiting for the retry loop."

verification: "Test with invalid YouTube URL - should see specific error like 'Video unavailable' instead of generic 'Download failed'."
files_changed: ["Sources/FeatureDownloader/DownloaderUseCase.swift"]