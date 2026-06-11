# Project Research Summary

**Project:** Niko Music Hub
**Domain:** Native macOS downloader reliability for producer workflows
**Researched:** 2026-06-11
**Confidence:** HIGH

## Executive Summary

v1.4 should keep the existing native Swift architecture and yt-dlp adapter, but make the downloader data path real. The main finding is not that Niko Music Hub needs a new stack; it needs the command, progress parser, timeout policy, helper health, output inbox handoff, and UAT to agree with real yt-dlp behavior.

Official yt-dlp guidance supports the audit's direction: embedding callers should avoid parsing normal stdout and should use options like `--print` and `--progress-template` for reproducible output. Local code currently uses safe argument-array execution, which is good, but the progress template and tests are mismatched with the real command. The local installed yt-dlp is `2026.03.17`; GitHub's latest checked release is `2026.06.09`, so stale helper guidance belongs in this milestone.

The roadmap should start with the command/progress/timeout foundation because downstream features depend on truthful progress. Then it should fix helper health, simulation, structured output result handoff, and media output actions. The final phase should be UAT-heavy and should explicitly prove behavior beyond the previous 18-second happy path.

## Key Findings

### Recommended Stack

Keep:
- Swift/SwiftUI/AppKit interop for the native app and handoff UI.
- yt-dlp CLI adapter behind `YtDlpDownloader`.
- FFmpeg/ffprobe through existing helper resolution and `--ffmpeg-location`.
- AppCore jobs and output inbox as the shared product surface.

Change:
- Emit `NIKO_PROGRESS:` style progress markers with `--progress --progress-template`.
- Replace the fixed total download timeout with stall-aware handling.
- Parse date-like yt-dlp versions and surface stale/update guidance.
- Pass output URLs as structured data, not synthetic log lines.

### Expected Features

**Must have:**
- Real progress from the actual yt-dlp command.
- Long downloads are not killed merely for being long.
- Format-aware preflight with `--no-playlist`.
- Helper health catches missing/unusable/outdated yt-dlp.
- Downloader media types can be revealed/opened/dragged when safe.
- UAT proves real-world downloader behavior.

**Should have:**
- Better job titles from metadata instead of URL path components.
- Clearer file icons/status for audio and video outputs.
- Full-output fallback parsing for final file markers.

**Defer:**
- Playlist/channel workflows.
- Bundled helper updater.
- Auth/cookie flows.

### Architecture Approach

Use a three-part architecture shift: make helper output machine-readable, separate typed job results from diagnostic logs, and make output handoff policy explicit by tool/media type. The existing module boundaries are good and should remain intact.

**Major components:**
1. `YtDlpDownloader` - command args, progress/file markers, output collection.
2. `DownloaderUseCase` - simulate, retry, stall policy, structured job result.
3. `YtDlpHealthChecker` - version and upgrade guidance.
4. `OutputHandoff` / `OutputInboxInspectorView` - safe media actions.
5. `ExternalProcessRunning` - UTF-8-safe streaming and process lifecycle.

### Critical Pitfalls

1. **Progress that cannot appear** - fix with explicit progress markers and matching tests.
2. **Total timeout kills valid work** - fix with stall timeout, not duration timeout.
3. **Logs as data plane** - fix with typed output URLs.
4. **Helper health dead code** - implement the existing `.outdated` state.
5. **Simulation mismatch** - simulate the same selected format and no-playlist behavior.

## Implications for Roadmap

### Phase 26: Downloader Command Truth

**Rationale:** Progress, timeout, and simulation are the root of the "sometimes fails" behavior.
**Delivers:** Real progress markers, no fixed total download timeout, stall-aware protection, UTF-8/full-output fallback, format-aware simulate.
**Addresses:** Progress, timeout, simulate, UTF-8 pitfalls.

### Phase 27: Helper Health and Output Contract

**Rationale:** Once downloads complete truthfully, the app needs to classify helper state and pass output files through typed data.
**Delivers:** Outdated yt-dlp detection/update copy, retry wording fixes, structured output URL handoff, better job titles.
**Addresses:** Helper health, retry mismatch, logs-as-data pitfall.

### Phase 28: Media Handoff and Downloader UX Finish

**Rationale:** Completed downloads must become useful in the producer workflow, not just "Ready" rows.
**Delivers:** Downloader-safe media allowlist, reveal/open/drag for MP3/M4A/MP4/WEBM, icons/status polish, UI copy for helper/update states.
**Addresses:** Output inbox dead-end issue.

### Phase 29: Real-World Downloader UAT

**Rationale:** The audit's central critique is mock-reality drift, so the milestone must close with evidence.
**Delivers:** Opt-in/live downloader smoke, deterministic parser/runner tests, long/slow/stall evidence, helper-path verification, updated UAT doc.
**Addresses:** Test/UAT coverage gap.

### Phase Ordering Rationale

- Command truth comes before handoff because handoff depends on successful, truthful downloads.
- Structured output comes before UI actions because the UI needs a reliable file URL source.
- UAT comes last so it validates the full end-to-end path, not a partial fix.

### Research Flags

- **Phase 26:** Confirm exact stall-window threshold during planning.
- **Phase 27:** Decide app stale-version policy: 60 days, 90 days, or "latest known release is newer by N days."
- **Phase 28:** Decide exact media extension allowlist and whether WEBM should be open/reveal only or drag-ready.
- **Phase 29:** Decide which live URLs are acceptable for repeatable UAT without relying on copyrighted/fragile material.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Existing stack is validated; official yt-dlp docs support marker-based parsing. |
| Features | HIGH | Features derive from a concrete audit plus local code inspection. |
| Architecture | HIGH | Boundaries are visible in the repo and match the needed changes. |
| Pitfalls | HIGH | Pitfalls are reproduced by code/test mismatch and official guidance. |

**Overall confidence:** HIGH

### Gaps to Address

- Stall policy threshold: choose during phase planning and test deterministically.
- Live UAT URL set: choose stable, legal, short/medium/long cases.
- Output handoff policy: decide whether media verification needs ffprobe or file-exists plus extension allowlist for v1.4.

## Sources

### Primary

- Official yt-dlp README: https://github.com/yt-dlp/yt-dlp.
- Official yt-dlp latest release: https://github.com/yt-dlp/yt-dlp/releases/tag/2026.06.09.
- Local command output: `yt-dlp --help`, `yt-dlp --version`, `ffmpeg -version`.
- Local source: `Sources/FeatureDownloader/*`, `Sources/AppCore/Services/ExternalProcessRunning.swift`, `Sources/AppCore/OutputInbox/OutputHandoff.swift`.

### Secondary

- 2026-06-11 downloader audit attached in this thread.
- `docs/public-release-real-uat-2026-05-26.md`.

---
*Research completed: 2026-06-11*
*Ready for roadmap: yes*
