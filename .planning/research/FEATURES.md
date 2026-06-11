# Feature Research

**Domain:** Downloader reliability inside Niko Music Hub
**Researched:** 2026-06-11
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Real progress during downloads | A producer needs to know a download is alive, especially for long mixes/sets | MEDIUM | Use explicit `NIKO_PROGRESS:` markers from `--progress-template`; update the progress parser and tests. |
| Long valid downloads complete | A 5-minute video, long mix, or slow network should not fail because a stopwatch hit 90 seconds | MEDIUM | Keep health/simulate bounded, but replace download total timeout with stall protection. |
| Concrete helper health | yt-dlp extractors drift quickly as sites change | MEDIUM | Detect missing, unusable, and stale versions; show upgrade guidance. |
| Format-aware simulation | Preflight must validate the same format path the real download will use | LOW | Simulate should include selected format args and `--no-playlist`. |
| Useful media handoff | Downloaded MP3/M4A/MP4/WEBM should be revealable/openable/draggable where safe | MEDIUM | Extend `OutputHandoff` without weakening WAV verification for converter/recorder outputs. |
| Structured output file handoff | Job logs are not a reliable data structure | MEDIUM | Return output URLs through job completion metadata or an explicit downloader result handoff. |
| Real downloader UAT | Green tests should represent actual command behavior | HIGH | Include opt-in network/live tests plus deterministic fixture runners. |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Producer-first output inbox | Files are immediately useful for Cubase/Finder handoff | MEDIUM | Distinguish audio/video/document icons and actions. |
| Trustworthy progress and diagnostics | User can tell "still downloading" from "broken" without opening Terminal | MEDIUM | Progress, last output time, retries, and helper health should be visible in the existing UI language. |
| Helper-path resilience | App-launched environment behaves like Terminal-launched environment | MEDIUM | Preserve recent resolver work for stripped `PATH` and `--ffmpeg-location`. |
| Safe local-only downloader policy | Clear boundary around allowed content and no shell interpolation | LOW | Keep product copy and architecture aligned with existing out-of-scope policy. |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Force all downloads to WAV | Cubase-friendly audio sounds appealing | Can be slow/lossy/unwanted for videos and ignores user-selected MP3/M4A/MP4 | Keep explicit media choices; only verify WAV where a WAV was requested. |
| Always use highest quality | Sounds like "best" | Can explode size/time and require merging on every video | Offer bounded choices and clear "best" option. |
| Hide helper complexity | Cleaner UI | Leaves the user stuck when yt-dlp is stale or FFmpeg is missing | Quiet default with visible health details when needed. |
| Retrying every failure | Seems robust | Permanent extractor/availability errors waste time | Retry only network/stall/transient failures with matching messages. |

## Feature Dependencies

```text
Progress marker command args
    -> Progress parser
        -> Stall detector
            -> Long-download reliability

Format-aware simulate
    -> Better error surfacing
        -> User trust/UAT

Structured DownloadResult
    -> Output inbox ingestion
        -> Media handoff policy
            -> Reveal/open/drag UI

Helper health stale detection
    -> Update guidance
        -> Better support flow
```

### Dependency Notes

- Progress markers must land before stall detection; otherwise the app cannot distinguish silence from legitimate long downloads.
- Format-aware simulate should land before broad UAT; otherwise UAT can pass a path that the selected format never uses.
- Structured result handoff should land before media handoff UI; otherwise the UI is still fed by regex-parsed logs.
- Helper health can be phased independently but should precede final UAT so stale-version guidance is visible during real use.

## MVP Definition

### Launch With (v1.4)

- [ ] Real progress marker command and parser.
- [ ] No total 90-second download kill timer.
- [ ] Stall-aware failure for truly stuck downloads.
- [ ] Stale/missing/unusable yt-dlp health states with update guidance.
- [ ] Format-aware simulate with `--no-playlist`.
- [ ] Structured output URLs into the inbox.
- [ ] Media handoff allowlist for downloader outputs.
- [ ] Downloader UAT proving long/slow/progress/helper-path behavior.

### Add After Validation

- [ ] Richer per-site diagnostics and suggested remedies.
- [ ] Optional nightly-channel yt-dlp guidance for extractor-breakage cases.
- [ ] Playlist/channel workflows, only after single-URL reliability is boring.

### Future Consideration

- [ ] Bundled helper tooling and update manager.
- [ ] Download archive/history.
- [ ] Auth/cookies/browser-profile flows for supported legal downloads.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Real progress markers | HIGH | MEDIUM | P1 |
| Remove total timeout / add stall timeout | HIGH | MEDIUM | P1 |
| Format-aware simulate | HIGH | LOW | P1 |
| Stale helper health | HIGH | MEDIUM | P1 |
| Structured output handoff | HIGH | MEDIUM | P1 |
| Media handoff allowlist | HIGH | MEDIUM | P1 |
| Live downloader UAT | HIGH | HIGH | P1 |
| Playlist workflows | MEDIUM | HIGH | P3 |
| Bundled helper updater | MEDIUM | HIGH | P3 |

## Sources

- 2026-06-11 downloader audit pasted into this thread.
- Official yt-dlp README: https://github.com/yt-dlp/yt-dlp.
- Local UAT: `docs/public-release-real-uat-2026-05-26.md`.
- Local code/tests: `Sources/FeatureDownloader/*`, `Sources/AppCore/OutputInbox/*`, `Tests/FeatureDownloaderTests/*`.

---
*Feature research for: v1.4 Downloader Reliability*
*Researched: 2026-06-11*
