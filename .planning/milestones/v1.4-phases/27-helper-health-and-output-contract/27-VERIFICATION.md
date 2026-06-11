---
status: passed
phase: 27
verified: 2026-06-11
---

# Phase 27 Verification

## Must-haves

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Helper health: missing/unusable/available/outdated | ✅ | `YtDlpHealthChecker`, `YtDlpVersionPolicy`, `YtDlpHealthCheckerTests` |
| Stale helper update copy | ✅ | `DownloaderCopy.outdatedYtDlp`, `HelperToolsHealthStrip` |
| Retry covers transient failures | ✅ | `DownloaderUseCase.isRetryable`, `DownloaderUseCaseTests` |
| Human-readable job titles | ✅ | `DownloaderUseCase` simulate title path, use case tests |
| Structured output URLs on Job | ✅ | `Job.outputFileURLs`, `JobProgress.setOutputFileURLs`, `DownloaderUseCaseTests.testCompletedDownloadSetsStructuredOutputURLs` |

## Gates

- `./script/ci.sh` — green (2026-06-11)
