# Phase 29: Real-World Downloader UAT - Context

**Gathered:** 2026-06-11
**Status:** Ready for planning
**Mode:** Auto-generated (smart discuss — autonomous auto-accept)

<domain>
## Phase Boundary

Close the mock-reality gap for v1.4 downloader reliability: deterministic automated coverage for progress, stall, helper health, structured output handoff, and media handoff; opt-in live `yt-dlp` verification beyond the prior 18-second happy path; stripped helper-path proof; and documented UAT evidence before milestone close.

</domain>

<decisions>
## Implementation Decisions

### Deterministic Coverage Matrix (UAT-01)
- Add `DownloaderUATCoverageTests` as a traceability matrix that asserts each v1.4 downloader requirement maps to at least one existing or new XCTest — do not duplicate full behavioral tests already in phases 26–28.
- Add `DownloaderHelperToolResolverTests` for stripped-PATH environment augmentation and `--ffmpeg-location` parent resolution (unit-level, no network).
- Keep `./script/ci.sh` unchanged for default gate — live tests stay opt-in.

### Opt-in Live Verification (UAT-02)
- Gate live checks behind `NIKO_MUSIC_HUB_LIVE_DOWNLOADER=1` (shell script and Swift `XCTSkipUnless`).
- Primary live success URL: `https://www.youtube.com/watch?v=BaW_jenozKc` (classic yt-dlp test clip, ~30s — beyond prior 18s happy path).
- Use audio-only format selection (`DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .m4a)`) to keep downloads small.
- Assert `NIKO_PROGRESS:` markers appear during download and output file exists with `ffprobe` duration > 18s.
- Failure path: simulate/download against a clearly invalid URL and assert non-zero exit with actionable stderr.

### Helper Path Verification (UAT-03)
- `script/downloader_live_smoke.sh` runs yt-dlp with `PATH=/usr/bin:/bin` and explicit `--ffmpeg-location` pointing at Homebrew ffmpeg parent directory.
- Swift unit tests cover `DownloaderHelperToolResolver.processEnvironment` prepending helper directories without requiring network.

### UAT Evidence Documentation (UAT-04)
- Create `docs/downloader-v1.4-uat.md` with requirement traceability table (UAT-01–04, CMD/HLTH/OUT/HAND cross-refs), deterministic test inventory, and opt-in live smoke instructions.
- Document stale-helper guidance flow by referencing `YtDlpHealthCheckerTests` and `DownloaderCopy` strings — no new UI work.

### Claude's Discretion
- Exact ffprobe parsing in shell script vs simple duration threshold check.
- Whether to add a second live URL (Internet Archive) if YouTube is flaky — optional, not required for pass.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phases 26–28 tests: `DownloadProgressParsingTests`, `DownloadStallMonitorTests`, `YtDlpHealthCheckerTests`, `DownloaderUseCaseTests`, `YtDlpDownloaderTests`, `OutputHandoffTests`.
- `DownloaderHelperToolResolver` — PATH augmentation for app-like stripped environments.
- `YtDlpDownloadCommandBuilder` — shared args for simulate/download including `--ffmpeg-location`.
- `script/ci.sh`, `script/e2e_user_smoke.sh`, `script/dev.sh` — local gate patterns.

### Established Patterns
- `XCTSkipUnless` for host-only / opt-in tests (`ExternalProcessRunningTests`, recorder integration).
- Env-gated smoke scripts (`NIKO_MUSIC_HUB_E2E_SMOKE` in e2e_user_smoke.sh).
- Evidence docs under `docs/` (e.g. `docs/public-release-real-uat-2026-05-26.md`).

### Integration Points
- `Package.swift` `FeatureDownloaderTests` target for new downloader UAT tests.
- `script/dev.sh` optional `live-downloader` command for discoverability.
- Milestone close requires green `./script/ci.sh` and `./script/e2e_user_smoke.sh`.

</code_context>

<specifics>
## Specific Ideas

Follow `.planning/research/SUMMARY.md` Phase 29 guidance: prove behavior beyond the May 2026 18-second "Me at the zoo" happy path. Keep CI deterministic; live network is operator opt-in.

</specifics>

<deferred>
## Deferred Ideas

- Full interactive UI downloader UAT with screenshots — defer to manual milestone sign-off; this phase focuses on automated/scripted proof.
- Bundled helper updater — out of v1.4 scope.

</deferred>
