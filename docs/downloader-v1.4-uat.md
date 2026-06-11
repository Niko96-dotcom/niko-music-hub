# Downloader v1.4 UAT Evidence

**Milestone:** v1.4 Downloader Reliability  
**Date:** 2026-06-11  
**Scope:** Phases 26–29 — command truth, helper health, output contract, media handoff, and real-world UAT.

## Requirement traceability

| Requirement | Area | Deterministic evidence | Opt-in live evidence |
|-------------|------|------------------------|----------------------|
| CMD-01 | Progress markers | `DownloadProgressParsingTests`, `YtDlpDownloaderTests`, `DownloaderUATCoverageTests` | `script/downloader_live_smoke.sh` greps `NIKO_PROGRESS:` |
| CMD-02 | No fixed 90s kill | `YtDlpDownloaderTests.testDownloadAppliesBoundedNetworkRetries` | Live download runs without total timeout |
| CMD-03 | Stall detection | `DownloadStallMonitorTests`, stall integration in `YtDlpDownloaderTests` | — |
| CMD-04 | Format-aware simulate | `DownloaderUseCaseTests`, `YtDlpDownloadCommandBuilder` | Live smoke uses audio-only format |
| CMD-05 | UTF-8 output collection | `YtDlpOutputCollectorTests` | — |
| HLTH-01–04 | Helper health | `YtDlpHealthCheckerTests`, `YtDlpVersionPolicyTests`, `DownloaderUATCoverageTests` | Live smoke uses stripped `PATH` |
| OUT-01–03 | Structured output | `DownloaderUseCaseTests.testCompletedDownloadSetsStructuredOutputURLs` | Live smoke output file on disk |
| HAND-01–05 | Media handoff | `OutputHandoffTests`, `DownloaderUATCoverageTests` | — |
| UAT-01 | Deterministic matrix | `DownloaderUATCoverageTests`, `DownloaderHelperToolResolverTests` | — |
| UAT-02 | Beyond 18s live path | `DownloaderLiveIntegrationTests` (skipped in CI) | `script/downloader_live_smoke.sh` duration > 18s |
| UAT-03 | Stripped helper path | `DownloaderHelperToolResolverTests` | Live smoke `PATH=/usr/bin:/bin` + `--ffmpeg-location` |
| UAT-04 | Documented evidence | This file | Operator log from live smoke when run |

## Local gates (deterministic)

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```

Both must be green before milestone close. Live downloader checks are **not** part of the default gate.

## Opt-in live verification

Set the environment variable and run either the shell smoke or Swift integration tests:

```bash
export NIKO_MUSIC_HUB_LIVE_DOWNLOADER=1
./script/downloader_live_smoke.sh
# or
NIKO_MUSIC_HUB_LIVE_DOWNLOADER=1 swift test --filter DownloaderLiveIntegrationTests
```

**Success URL:** `https://www.youtube.com/watch?v=BaW_jenozKc` (classic yt-dlp test clip, ~30s — beyond the prior 18-second “Me at the zoo” happy path).  
**Format:** audio-only M4A to keep downloads small.  
**Failure URL:** invalid YouTube id — expects non-zero exit and stderr.

**Helper-path proof:** live smoke runs `yt-dlp` with `PATH=/usr/bin:/bin` and explicit `--ffmpeg-location` pointing at the Homebrew ffmpeg directory.

## Flows covered

| Flow | Deterministic | Live (opt-in) |
|------|---------------|---------------|
| Progress updates | ✅ parser + fake runner tests | ✅ `NIKO_PROGRESS:` in log |
| Stall failure | ✅ injectable clock tests | — |
| Stale helper guidance | ✅ outdated version tests | — |
| Structured output URLs | ✅ use case + downloader tests | ✅ output file exists |
| Media handoff allowlist | ✅ `OutputHandoffTests` | — |
| Download failure | ✅ simulate failure tests | ✅ invalid URL non-zero exit |
| Longer-than-18s download | — | ✅ ffprobe duration check |

## Prior UAT reference

v1.0 public-release UAT (`docs/public-release-real-uat-2026-05-26.md`) used “Me at the zoo” (~19s). v1.4 adds deterministic coverage for reliability fixes and an explicit longer live clip for regression confidence.
