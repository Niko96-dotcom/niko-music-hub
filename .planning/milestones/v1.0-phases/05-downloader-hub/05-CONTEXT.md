# Phase 5: Downloader Hub - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 5 delivers a controlled yt-dlp-backed download workflow that saves outputs into the same production inbox used by conversion and recording. It detects yt-dlp availability and version, accepts a URL, runs the download as an async job with live progress and log visibility, records successful outputs with source URL metadata, and clearly frames the tool as user-authorized material only. Downloaded audio/video files are not automatically converted to WAV — that is a separate workflow.

This phase does not implement auto-conversion of downloads, recursive playlist downloading, built-in browser or URL discovery, DRM/paywall circumvention, or helper bundling/packaging.
</domain>

<decisions>
## Implementation Decisions

### Start Trigger
- **D-01:** User pastes or types a supported URL into a text field and explicitly clicks a Download button to start the job. Auto-start on paste is too risky for accidental trigger.
- **D-02:** Before enqueueing, the app runs a lightweight `--simulate` or `--dump-json` check to confirm yt-dlp can handle the URL and to show the detected filename. This gives the user a confirmation moment before actual download begins.

### Progress Display
- **D-03:** yt-dlp outputs progress information to stderr in a parseable format. The adapter runs yt-dlp with `--newline` (line-by-line output) and parses stderr for progress percentage, speed, and ETA.
- **D-04:** Progress updates flow through the shared `JobProgress` interface — `update(progress:)` for percentage, `log()` for real-time stdout/stderr lines. No separate progress callback system needed.
- **D-05:** The download job logs raw yt-dlp output as it runs so the user can see what is happening. On completion, logs remain visible for post-mortem. Errors are logged clearly with actionable messages.

### Output Naming
- **D-06:** Output filename is determined by yt-dlp (via `--output` template) and reflects the original content name from the server. The app does not re-name files after download.
- **D-07:** If the target output file already exists, yt-dlp is configured with a numbered-suffix pattern (e.g., `file.mp3` → `file (1).mp3`) to avoid overwriting. The user sees the final filename in job completion.
- **D-08:** Multiple files from a playlist are handled as a single job. The adapter tracks each output file path and adds each to the inbox separately with shared source URL metadata.

### Error Recovery
- **D-09:** Transient failures (network interruption, timeout, server error) trigger up to 3 automatic retries with exponential backoff (2s, 4s, 8s) before reporting final failure. The retry count and backoff timing are configurable internals.
- **D-10:** On final failure, any partial download is cleaned up (deleted) so no orphan files remain in the output folder. The job is marked failed with an error message that distinguishes retryable vs permanent failures.
- **D-11:** Permanent failures (404, forbidden, unsupported site) are not retried. The error message tells the user what failed and why, with guidance on the specific failure type.

### Trust Framing
- **D-12:** The UI labels the tool "Downloader" — not "Media Downloader" or "Video Downloader" — to keep it generic and tool-like, not promotional.
- **D-13:** Every download explicitly requires a user gesture (click Download or press Enter in the URL field) as the start trigger. No silent or auto-triggered downloads.
- **D-14:** The download view displays the URL being fetched and the output destination folder, making it clear what and where before the job runs.
- **D-15:** Legal/trust framing: The tool is for material the user is allowed to access and save. No in-app messaging claims the app can access anything the user cannot already access with a browser. DL-07 is satisfied by showing the URL and requiring explicit start.

### Command Construction (Safety)
- **D-16:** yt-dlp is invoked via the existing `ExternalProcessRunning` adapter (same as FFmpeg adapter from Phase 3), using `executableURL` and `arguments` array — no shell string interpolation.
- **D-17:** The URL is passed as a single argument, not concatenated into a command string. Argument array is constructed with the URL as a distinct element.

### Output and Inbox
- **D-18:** On successful download, the output file path is resolved and the file is added to the shared output inbox with metadata: source URL (`dlSourceURL`), download tool ID (`downloader`), and job completion timestamp.
- **D-19:** The inbox item can be revealed in Finder or dragged out via `OutputHandoff`. The downloaded file is not automatically converted — conversion is a separate explicit action by the user.
- **D-20:** `WAVOutputVerifier` is not run on download outputs (they may not be WAV files). Only file existence is verified before adding to inbox.

### Claude's Discretion
- Exact progress parsing regex/heuristic for yt-ddl output is flexible if it reliably extracts percentage, speed, and ETA.
- Exact retry backoff timing and max retry count are implementation details (the values above are recommendations).
- Exact UI layout of the download tool surface is flexible if it stays compact, native, and production-bench-like — URL input field, file name display, progress bar, log area, action button.
- Exact in-app phrasing for "user-authorized" framing is flexible as long as DL-07 is clearly satisfied.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope And Requirements
- `.planning/ROADMAP.md` — Phase 5 goal, success criteria, planned slices (05-01 through 05-04), dependency on Phase 4, and phase boundary.
- `.planning/REQUIREMENTS.md` — DL-01 through DL-07 for URL input, helper health, job options, progress/errors, inbox output, safe command construction, and trust framing.
- `.planning/PROJECT.md` — Core value, downloader constraint (yt-dlp behind adapter, no shell interpolation), file output constraint, and current project state.
- `.planning/STATE.md` — Current project status and accumulated decisions affecting Phase 5.

### Prior Architecture Decisions
- `.planning/phases/01-app-foundation-and-tool-architecture/01-CONTEXT.md` — Locked feature registry, shared `ToolContext`, output inbox, settings, job runner, and compact production-bench shell.
- `.planning/phases/03-cubase-ready-wav-conversion/03-CONTEXT.md` — External tool adapter pattern, `ExternalProcessRunning` protocol with explicit `executableURL` and argument arrays, no-shell-interpolation rule, WAVOutputVerifier reusable for Phase 5 outputs.
- `.planning/phases/04-internal-audio-recorder/04-CONTEXT.md` — Confirms job runner reuse for live progress, permission guidance pattern, and output inbox contract.

### Research Guidance
- `.planning/research/STACK.md` — yt-dlp as externally installed CLI tool, macOS 10.15+ compatibility, FFmpeg recommended for post-processing, Process with explicit URL and argument array pattern.
- `.planning/research/PITFALLS.md` — Unsafe shell string construction, generic error messages, silent helper failure. Relevant here: yt-dlp command construction safety.

### Prior Key Decisions (from STATE.md)
- External helper execution is centralized behind `ExternalProcessRunning` using `Process.executableURL` and argument arrays — same pattern applies to yt-dlp.
- yt-dlp integration must be isolated behind a service boundary — same adapter pattern as FFmpeg.
- Helper tool packaging/licensing should be revisited before public distribution.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Sources/AppCore/Services/ExternalProcessRunning.swift` — Protocol and `FoundationExternalProcessRunner` that Phase 5 yt-dlp adapter will implement, same pattern as `FFmpegAudioConverter` in Phase 3.
- `Sources/AppCore/Jobs/JobRunner.swift` — Shared job runner that Phase 5 download jobs will use for progress (0-1), log messages, and cancellation.
- `Sources/AppCore/Jobs/Job.swift` — Job model with id, title, sourceToolID, state, progress, message, logEntries, startedAt, finishedAt.
- `Sources/AppCore/OutputInbox/OutputInboxItem.swift` — Output item model with metadata string field that can store source URL.
- `Sources/AppCore/OutputInbox/JSONOutputInboxStore.swift` — Persists output items; add method to append items with download metadata.
- `Sources/AppCore/OutputInbox/OutputHandoff.swift` — Gated reveal and drag-out; download outputs are files so same gate applies.
- `Sources/FeatureAudioConverter/FFmpegHealthChecker.swift` — Health check pattern for external helpers; same pattern for yt-dlp version check.
- `Sources/AppCore/Settings/HelperToolSettings.swift` — Already has optional `yt-dlp` path field; can be extended for version tracking.

### Established Patterns
- The app uses a feature module pattern (e.g., `FeatureDownloader`) registered in `AppComposition.swift` with metadata, view factory, and capability flags.
- External tools are wrapped behind a port (interface/abstract class) so the implementation is swappable — same pattern for yt-dlp adapter as FFmpeg adapter.
- Long-running work uses the shared job runner — download job will call `JobRunner.enqueue` with an async operation that reads stderr and updates progress.
- Generated files are tracked as output inbox items with metadata — download outputs use the same contract with source URL metadata.
- UI stays calm, compact, native, and action-oriented — download UI will be a URL input, progress display, and action button in one compact surface.

### Integration Points
- Add a downloader feature module, likely `FeatureDownloader`, and register it in `AppComposition`.
- Mark downloader metadata with `.producesFiles` and `.runsJobs`.
- Read current `AppSettings.outputFolder` for output location.
- Add yt-dlp health checker behind a port, with actual execution via `FoundationExternalProcessRunner`.
- Parse yt-dlp stderr for progress; feed percentage to `JobProgress.update` and lines to `JobProgress.log`.
- Add output inbox items only after download completes and file exists.
- Use `OutputHandoff` to gate reveal and drag-out.

</code_context>

<specifics>
## Specific Ideas

- The download UI should feel like the BPM tapper and converter — compact, focused, action-oriented.
- The URL input should be the primary interaction, with the detected filename shown before download starts.
- Progress should be visible as a percentage bar with real-time log lines below it.
- The tool name in the sidebar should be "Downloader" (not "Media Downloader" or anything promotional).
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 5 scope.

---

*Phase: 05-downloader-hub*
*Context gathered: 2026-05-11*