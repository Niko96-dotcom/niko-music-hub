# Stack Research

**Domain:** Native macOS downloader reliability for a local music-production hub
**Researched:** 2026-06-11
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift / SwiftUI / AppKit interop | Swift 6.3 local toolchain | Native macOS app and output handoff UI | Already validated in Niko Music Hub; best fit for local files, drag/drop, permissions, and helper process control. |
| yt-dlp | Local: 2026.03.17; latest checked: 2026.06.09 | Site extraction, media download, format selection, post-processing hooks | The app already integrates yt-dlp safely through argument arrays. v1.4 should harden the real command path, not replace it. |
| FFmpeg / ffprobe | Local: FFmpeg 8.1 | Merge separate audio/video streams and extract audio containers | yt-dlp strongly recommends ffmpeg/ffprobe for merging and post-processing; Niko Music Hub already resolves helper paths. |
| AppCore job/output infrastructure | Existing repo modules | Job progress, output inbox, reveal/open/drag handoff | Reuse existing `JobRunner`, `OutputInboxStore`, `OutputHandoff`, and `FileActions` rather than adding another downloader-specific queue. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation `Process` | macOS system API | Launch yt-dlp/ffmpeg without shell interpolation | Keep the current `Process.executableURL` + argument-array pattern. |
| Foundation `Pipe` / streaming callbacks | macOS system API | Capture progress, stderr, final output paths | Needs UTF-8-safe incremental decoding and full-result fallback parsing. |
| SQLite | Existing archive stores | Persist archive metadata | Not central to downloader, but research flags busy-timeout as shared reliability debt if v1.4 touches stores. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `yt-dlp --help` | Verify installed option support | Local help confirms `--progress`, `--progress-template`, `--print`, `--no-playlist`, `--ffmpeg-location`, and `--socket-timeout`. |
| `yt-dlp --version` | Health check and stale version detection | Version strings are date-like release tags. Compare against an app policy threshold and surface update guidance. |
| `./script/ci.sh` | Local truth gate | Must stay green after each phase. |
| `./script/e2e_user_smoke.sh` | User-style smoke | Extend or complement with downloader-specific real invocation/UAT where network is intentionally enabled. |
| `./script/dev.sh helpers` | Install/update helper tools | Existing user-facing command already routes to Homebrew helper updates. |

## Installation / Update Guidance

```bash
# User-facing existing path
./script/dev.sh helpers

# Manual equivalent on this machine
brew upgrade yt-dlp ffmpeg

# Inspect current helpers
yt-dlp --version
ffmpeg -version
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Keep yt-dlp CLI adapter | Embed yt-dlp Python API | Only if CLI output becomes insufficient. It would add Python/runtime packaging complexity that violates the product boundary. |
| Parse explicit `--progress-template` markers | Parse normal yt-dlp stdout | Avoid. Official docs say embedding callers should not parse normal stdout because it can change. |
| Structured download result model | Re-parse job log lines | Avoid. Logs are human/audit output, not the data plane. |
| App policy stale check | Rely only on yt-dlp's own warning | Use both if possible. The app should surface stale helper state before obscure extractor failures reach the user. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `/bin/sh -c` downloader invocation | Shell interpolation risk with arbitrary URLs and output templates | `Process.executableURL` plus explicit argument arrays. |
| Total-duration kill timer for downloads | Long valid downloads fail solely because they are long | Stall-aware timeout based on lack of output/progress, while preserving bounded simulate/health calls. |
| Mock-only progress tests | They can pass while the real command emits no parseable progress | Tests that assert actual command args plus parser fixtures matching `NIKO_PROGRESS:` lines. |
| WAV-only handoff for all inbox items | Downloader outputs are often MP3/M4A/MP4/WEBM and become dead-end rows | Tool-aware media handoff policy with explicit safe extension allowlists. |

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| yt-dlp CLI | FFmpeg / ffprobe | Required for best video+audio merging and audio extraction. `--ffmpeg-location` may be a binary or containing directory. |
| yt-dlp progress output | Swift streaming pipes | Use `--progress --progress-template "download:NIKO_PROGRESS:%(progress._percent_str)s"` or equivalent explicit marker. |
| yt-dlp format selection | FFmpeg merge | Modern 720p video often requires separate video+audio formats; prefer `bv*+ba/b` style selectors or `-S res:720` patterns over premerged-only selectors. |

## Sources

- Official yt-dlp README: https://github.com/yt-dlp/yt-dlp - update channels, helper dependencies, format selection, embedding guidance.
- Official yt-dlp latest release: https://github.com/yt-dlp/yt-dlp/releases/tag/2026.06.09 - latest checked release on 2026-06-11.
- Local `yt-dlp --help` and `yt-dlp --version` - installed option/version verification.
- Local code: `Sources/FeatureDownloader/YtDlpDownloader.swift`, `DownloaderUseCase.swift`, `YtDlpHealthChecker.swift`, `DownloadFormatSelection.swift`.

---
*Stack research for: v1.4 Downloader Reliability*
*Researched: 2026-06-11*
