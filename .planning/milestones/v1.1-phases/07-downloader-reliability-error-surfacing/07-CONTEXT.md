# Phase 7: Downloader Reliability & Error Surfacing - Context

**Gathered:** 2026-05-23
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous mission brief)

<domain>
## Phase Boundary

Downloader is trustworthy for daily use — failures are actionable, simulate never enqueues broken jobs, and v1.0 downloader requirements (DL-01–DL-10) are verified with Phase 7 VERIFICATION.md.

</domain>

<decisions>
## Implementation Decisions

### Simulate gate (DL-08)
- `simulateAndEnqueue` runs `yt-dlp --simulate --print %(title)s` via `FoundationExternalProcessRunner` with `executableURL` + argument array only.
- Non-zero exit must throw before `jobRunner.enqueue`; no job for failed simulate.

### Error surfacing (DL-09)
- Prefer yt-dlp `stderr` over stdout when building user-visible failure text.
- Use `DownloadUseCaseError.downloadFailed` for yt-dlp process failures (simulate and download) so the UI body shows stderr, not a generic-only label.
- `StandardErrorCard` shows stderr in `body`; card `label` stays short ("Download Failed" / "URL Not Supported").

### Trust & scope (DL-07)
- Trust notice visible in `readyToDownload` and `downloading` states (source, destination, legal framing).
- Explicit Download button; no auto-start on paste.

### Land workspace (DL-10)
- Commit FeatureDownloader UI/VM/use case, AppCore `AppError` / `StandardErrorCard`, AppComposition registration.

### Claude's Discretion
- Retroactive DL-01–07 verification references v1.0 implementation + new tests; no reimplementation unless gaps found.
- URL debounce check may remain health-only; simulate at enqueue is the authoritative gate.

</decisions>

<code_context>
## Existing Code Insights

- Root cause documented: `.planning/debug/downloader-yt-dlp-failure.md`
- `DownloaderUseCase` already checks `result.exitCode` after simulate; needs stderr-first messaging and tests.
- v1.0 Phase 5 VERIFICATION exists under `.planning/milestones/v1.0-phases/05-downloader-hub/VERIFICATION.md` but was orphaned from milestone audit (no phase dir VERIFICATION at ship).
- 149 tests pass via `scripts/test.sh` (6 permission skips).

</code_context>

<specifics>
## Specific Ideas

- Invalid YouTube URL should surface text like `ERROR: [youtube] ... Video unavailable` in error card body.
- `openTerminal` recovery should launch Terminal.app (not System Settings).

</specifics>

<deferred>
## Deferred Ideas

- Bundled yt-dlp binary (DIST-01).
- Simulate during URL debounce (optional UX; enqueue gate is sufficient for DL-08).

</deferred>
