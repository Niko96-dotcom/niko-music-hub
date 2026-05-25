# Phase 5: Downloader Hub - Discussion Log

**Phase:** 05-downloader-hub
**Mode:** discuss (auto)
**Date:** 2026-05-11

## Session Summary

Discussed Phase 5 (Downloader Hub) via `--auto` mode with all gray areas auto-selected and pre-answered using established project patterns and prior phase decisions.

## Gray Areas Presented

1. **Start trigger** — How download begins (explicit button vs auto on paste)
2. **Progress display** — Live updates vs polling
3. **Output naming** — Preserve original filename, auto-rename duplicates
4. **Error recovery** — Retry logic, partial downloads
5. **Trust framing** — How UI communicates user-authorized-only

## Decisions Applied

All five areas were auto-selected and decided based on:

- Phase 3 established patterns: `ExternalProcessRunning` protocol, explicit `executableURL` + argument arrays, no shell interpolation
- Phase 4 established patterns: job runner reuse, permission guidance clarity, output inbox contract
- Project-level decisions: yt-dlp behind adapter, output goes to inbox with metadata, explicit user gesture required
- ROADMAP.md DL-01 through DL-07 requirements

## Key Decisions

- Start: explicit Download button after URL paste + yt-dlp `--simulate` pre-check
- Progress: stderr parsing with `--newline`, feed into JobProgress interface
- Naming: yt-dlp defaults + numbered-suffix for duplicates; playlists tracked per-file
- Error recovery: 3 retries with exponential backoff, partial file cleanup on final failure
- Trust framing: "Downloader" label, URL + destination visible before run, explicit user gesture required

## Deferred Ideas

None — all decisions stayed within Phase 5 scope.