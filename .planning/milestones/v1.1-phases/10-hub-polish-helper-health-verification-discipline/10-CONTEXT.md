# Phase 10: Hub Polish, Helper Health & Verification Discipline - Context

**Gathered:** 2026-05-23
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous)

<domain>
## Phase Boundary

Surface yt-dlp/FFmpeg health in the hub shell, keep QA green, and ensure Phases 7–10 have VERIFICATION.md before milestone close.

</domain>

<decisions>
## Implementation Decisions

- `HelperToolsHealthStrip` in sidebar shows version/path or install guidance.
- `FFmpegHealthChecker.detectFfmpeg()` mirrors yt-dlp auto-detect paths.
- Phases 7–10 each have VERIFICATION.md; extensibility spot-check via existing `ToolFeature` registration in `AppComposition`.

</decisions>

<code_context>
## Existing Code Insights

- Per-tool health already in downloader/converter VMs; hub strip centralizes UX-05.
- UX-03/04: `StandardErrorCard` + Space/Escape shortcuts in tool views (spot-check in verification).

</code_context>

<specifics>
## Specific Ideas

None.

</specifics>

<deferred>
## Deferred Ideas

Bundled helpers (DIST-01) remain post-v1.1.

</deferred>
