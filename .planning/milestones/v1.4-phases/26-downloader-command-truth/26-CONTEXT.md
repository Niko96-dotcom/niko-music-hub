# Phase 26: Downloader Command Truth - Context

**Gathered:** 2026-06-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the real `yt-dlp` command path trustworthy: parseable progress from the actual command, no fixed 90-second total download kill, stall detection for silent hangs, format-aware simulate with `--no-playlist`, and resilient output collection across split UTF-8 chunks.

</domain>

<decisions>
## Implementation Decisions

### Progress Markers
- Emit machine-readable progress via `--progress` and `--progress-template` with prefix `NIKO_PROGRESS:` (e.g. `NIKO_PROGRESS:%(progress)s`).
- Parse `NIKO_PROGRESS:` lines in `DownloaderUseCase` and keep legacy `[download] X%` parsing as fallback during transition.
- Update job progress on every parsed marker; no extra throttle beyond yt-dlp output rate.
- Unit tests must assert the real template output shape, not only legacy `[download]` lines.

### Timeout & Stall Policy
- Remove the fixed 90-second total download timeout (`timeoutSeconds: nil` for actual downloads).
- Stall window: **120 seconds** without progress marker or collector activity.
- Implement stall detection in the downloader layer with injectable clock/time source for deterministic tests (no real sleeps in CI).
- User-facing stall message: `Download stalled — no progress for 2 minutes`.

### Simulate / Preflight
- Simulate uses the same format selector and extra arguments as the real download.
- Add `--no-playlist` to both simulate and download invocations.
- Keep 30-second timeout on simulate (metadata-only preflight).
- Validate non-zero simulate exit codes and surface stderr via existing `ytDlpFailureMessage`.

### Output Collection
- Keep UTF-8 pending-line buffer in `YtDlpOutputCollector` for split chunks.
- Accumulate full stdout/stderr text and reparse on `finish()` as fallback when streaming misses final markers.
- Primary file path source remains `NIKO_MUSIC_HUB_FILE:` `--print after_move` markers.
- Tests cover split UTF-8 across chunk boundaries and finish-time reparse recovery.

### Claude's Discretion
- Exact stall monitor polling interval and internal helper naming.
- Whether to centralize yt-dlp argument building in one builder used by simulate + download.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `YtDlpDownloader` — command args, `YtDlpOutputCollector`, progress/file marker parsers.
- `DownloaderUseCase` — simulate gate, retry, `parseProgress`, job enqueue.
- `YtDlpFormatArgumentBuilder` — format selector for real downloads.
- `FoundationExternalProcessRunner` — streaming runner; `timeoutSeconds: nil` already means no total timeout.
- `DownloadProgressParsingTests`, `YtDlpDownloaderTests`, `DownloaderUseCaseTests`.

### Established Patterns
- Fixture-first unit tests with injected `ExternalProcessRunning` fakes.
- Progress logged via `JobProgress.log` and `progress.update`.
- Output paths collected via print markers plus regex fallbacks on log lines.

### Integration Points
- `ExternalProcessRequest.timeoutSeconds` — remove for downloads, keep for simulate.
- `DownloaderUseCase.parseProgress` must align with `YtDlpDownloader` progress template (current mismatch: template emits `download:%progress`, parser expects `[download] X%`).

</code_context>

<specifics>
## Specific Ideas

Follow `.planning/research/SUMMARY.md` and v1.4 CMD-01–CMD-05. Fix the progress template/parser mismatch as the highest-impact bug.

</specifics>

<deferred>
## Deferred Ideas

- Structured output URL handoff without synthetic log lines → Phase 27.
- Helper outdated detection and job title improvements → Phase 27.
- Output inbox media handoff → Phase 28.

</deferred>
