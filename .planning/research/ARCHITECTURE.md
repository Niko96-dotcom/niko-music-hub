# Architecture Research

**Domain:** Reliable external-helper download pipeline in a native macOS app
**Researched:** 2026-06-11
**Confidence:** HIGH

## Standard Architecture

### System Overview

```text
SwiftUI DownloaderView / OutputInboxInspectorView
        |
DownloaderViewModel
        |
DownloaderUseCase
        |--------------------------|
        |                          |
YtDlpHealthChecker          JobRunner / JobProgress
        |                          |
YtDlpDownloader             structured completion result
        |                          |
FoundationExternalProcessRunner    |
        |                          |
yt-dlp + FFmpeg/ffprobe      OutputInboxStore
                                   |
                              OutputHandoff
```

### Component Responsibilities

| Component | Responsibility | Current State | v1.4 Direction |
|-----------|----------------|---------------|----------------|
| `DownloaderView` / `DownloaderViewModel` | User input, format selection, status display | Good UI shell, but progress is only as truthful as backend | Keep UI mostly stable; make progress/helper states real. |
| `DownloaderUseCase` | Simulate, enqueue, retry, progress parse, output handoff | Simulate omits format args; retry matching is brittle; output URLs are logged back into text | Split command result data from logs; match transient errors precisely. |
| `YtDlpDownloader` | Build yt-dlp command, run process, collect output paths/progress | Uses argument arrays, but has 90-second timeout and invalid progress template | Use explicit progress markers, no total download timeout, full-output fallback. |
| `FoundationExternalProcessRunner` | Run helper tools and stream stdout/stderr | Total timeout support; chunk-level UTF-8 decoding can drop split multibyte sequences | Add UTF-8-safe streaming decoder or fallback parser contract. |
| `YtDlpHealthChecker` | Missing/unusable helper detection | `outdated` enum exists but never emitted | Implement date/version policy and upgrade message. |
| `OutputHandoff` | Decide reveal/drag readiness | WAV-only policy | Keep WAV verification for converter/recorder; add tool/media-aware downloader policy. |

## Recommended Project Structure

```text
Sources/
├── FeatureDownloader/
│   ├── YtDlpDownloader.swift          # command construction, progress markers, output collection
│   ├── DownloaderUseCase.swift        # simulate, retry, job handoff
│   ├── YtDlpHealthChecker.swift       # version/staleness guidance
│   ├── DownloadFormatSelection.swift  # format selectors and extra args
│   └── DownloaderJobFactory.swift     # candidate for structured output result wiring
├── AppCore/
│   ├── Services/ExternalProcessRunning.swift
│   ├── Jobs/JobRunner.swift
│   └── OutputInbox/OutputHandoff.swift
└── NikoMusicHub/AppShell/
    └── OutputInboxInspectorView.swift
```

### Structure Rationale

- Keep command-specific logic in `FeatureDownloader`; AppCore should know only generic process/job/output concepts.
- Extend AppCore handoff policy through explicit media/tool semantics rather than adding downloader UI special cases.
- Keep helper process execution generic, but make streaming decoding safe enough for all features.

## Architectural Patterns

### Pattern 1: Explicit Machine-Readable Helper Output

**What:** Configure yt-dlp to emit stable marker lines such as `NIKO_PROGRESS:` and `NIKO_MUSIC_HUB_FILE:`.

**When to use:** Any UI state or data transfer that depends on helper output.

**Trade-offs:** Slightly more command construction complexity, much less parser fragility.

### Pattern 2: Job Result Data Plane Separate From Logs

**What:** A job can log human-readable lines, but output file URLs should travel through typed completion metadata or a downloader-specific completion callback.

**When to use:** Output inbox ingestion, reveal/open/drag state, future automation.

**Trade-offs:** Requires a small AppCore or downloader boundary change. Removes regex round-tripping.

### Pattern 3: Timeout By Stall, Not By Duration

**What:** Health/simulate commands can have fixed timeouts; downloads should fail only when no output/progress occurs for a configured stall window.

**When to use:** Long-running external downloads with legitimate slow/large cases.

**Trade-offs:** More state to track in the runner/use case, but aligns with real user expectations.

## Data Flow

### Download Flow

```text
User enters URL + format
    -> simulate selected format with --simulate --no-playlist
    -> enqueue job
    -> run yt-dlp with explicit progress/file markers
    -> stream progress to JobProgress
    -> collect output URLs as structured data
    -> write OutputInboxItem(s)
    -> OutputHandoff exposes safe reveal/open/drag actions
```

### Helper Health Flow

```text
Settings/helper resolver
    -> locate yt-dlp
    -> run --version
    -> parse date/version
    -> compare with app staleness policy and latest-known/update guidance
    -> display missing/unusable/outdated/available state
```

## Integration Points

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Swift app -> yt-dlp | `Process` executable URL + argument array | Preserve no-shell guarantee. |
| yt-dlp -> Swift app | stdout/stderr streaming and final result | Use explicit markers and UTF-8-safe buffering. |
| Downloader -> OutputInbox | Structured output URLs | Avoid logs as data. |
| OutputInbox -> Finder/Cubase | `NSWorkspace`, `NSItemProvider` | Allow media types intentionally; verify files exist and are available. |
| App -> Homebrew/user updates | `./script/dev.sh helpers` and Settings copy | App can suggest commands, not silently mutate helper tools unless a future update manager is built. |

## Anti-Patterns

### Anti-Pattern 1: Quiet Helper With Fake Progress Expectations

**What people do:** Use `--print`/quiet behavior and still test parser against normal `[download]` progress.

**Why it is wrong:** Tests and UI disagree with the real command.

**Do this instead:** Force progress output and parse an app-owned marker.

### Anti-Pattern 2: One Handoff Rule For All Tools

**What people do:** Require WAV verification for every output.

**Why it is wrong:** Correct for converter/recorder, wrong for downloader media.

**Do this instead:** Make handoff policy aware of output type/source tool while keeping conservative file-exists checks.

### Anti-Pattern 3: Delete Evidence During Milestone Setup

**What people do:** Clear tracked phase dirs that are not archived.

**Why it is wrong:** Loses planning history.

**Do this instead:** Leave v1.3 phase dirs until the proper milestone archive path exists.

## Sources

- Official yt-dlp README embedding guidance: https://github.com/yt-dlp/yt-dlp#embedding-yt-dlp.
- Local code: `YtDlpDownloader.swift`, `DownloaderUseCase.swift`, `ExternalProcessRunning.swift`, `OutputHandoff.swift`.
- Local docs: `.planning/PROJECT.md`, `docs/public-release-real-uat-2026-05-26.md`.

---
*Architecture research for: v1.4 Downloader Reliability*
*Researched: 2026-06-11*
