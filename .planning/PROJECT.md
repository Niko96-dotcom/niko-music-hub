# Outside Cubase Hub

## What This Is

Outside Cubase Hub is a local macOS app for the music production chores that keep pulling you out of Cubase: tapping BPM, recording internal computer audio to WAV, downloading source material, and converting files into Cubase-ready formats. It is built for one producer first, with a clean tool-hub architecture so new "outside Cubase" utilities can be added as soon as better ideas show up.

## Core Value

Repeated production chores outside Cubase should become fast, local, reliable, and drag-and-drop ready for a Cubase project.

## Current Milestone: v1.1 Production-Ready Tools

**Goal:** Close the gap between v1.0 "implemented" and trustworthy daily use on the target Mac for real Cubase prep work.

**Target outcomes:**
- Downloader: actionable errors, simulate blocks bad enqueue, DL-01–07 verified
- Recorder: real Core Audio process tap capture to Cubase-ready WAV (REC-01–06 verified)
- Converter & handoff: human UAT for conversion flow, Finder/Cubase drag, live inbox refresh
- Hub: helper health accurate, shared error UX, output inbox stays current
- Quality: green test suite; every v1.1 phase ships with VERIFICATION.md

## Requirements

### Validated (v1.0)

- [x] Native SwiftUI macOS app shell with registry-driven tool navigation — v1.0 Phase 1
- [x] Feature boundary: new tools register through `ToolFeature` and `ToolRegistry` without editing existing feature internals — v1.0 Phase 1
- [x] Shared local settings for output folder, audio preset defaults, and helper tool paths — v1.0 Phase 1
- [x] Durable output inbox metadata model and shared job states for queued, running, completed, failed, and canceled work — v1.0 Phase 1
- [x] BPM tapper with keyboard/mouse input, live estimate averaging, half/double adjustments, local history, and full offline operation — v1.0 Phase 2
- [x] Native AVFAudio conversion first with FFmpeg fallback, batch conversion with per-file progress — v1.0 Phase 3
- [x] WAV metadata verification reusable across conversion and recording outputs — v1.0 Phase 3
- [x] Drag-out/reveal handoff through OutputHandoff safety policy (only accepts .available existing .wav files) — v1.0 Phase 3
- [x] Reveal in Finder and drag to Cubase/Finder-compatible targets — v1.0 Phase 3

### Active (v1.1)

See `.planning/REQUIREMENTS.md` for full v1.1 scope. Summary:

- **Downloader:** Verify DL-01–07; fix simulate/enqueue and stderr surfacing; land in-progress FeatureDownloader + AppCore error UI
- **Recorder:** Replace synthetic tap with real capture; verify REC-01–06 on macOS 14.2+
- **Converter & hub:** Human UAT for conversion + drag; live output inbox refresh
- **Polish:** Verify UX-03–04; helper health UX; verification discipline (QA-02)

### Out of Scope

- Direct Cubase plugin/VST integration — useful later, but the first product is a companion app outside Cubase.
- Cloud sync, accounts, and collaboration — this is a local personal workflow tool.
- Full DAW editing, arranging, or mixing — Cubase remains the production environment.
- Circumventing paywalls, DRM, or site restrictions — downloads must be for material the user is allowed to access and save.
- Mac App Store distribution in v1.1 — downloader and FFmpeg helper packaging/licensing may be researched but not shipped.
- Advanced AI/stem separation/key detection — good future ideas, but not needed to validate the hub.
- BPM/key/loudness analysis — deferred for future release.
- Sample prep (trim/fade/naming chains) — deferred for future release.
- New tools beyond stabilizing BPM, converter, recorder, and downloader.

## Context

The spark is a real repeated workflow: leaving Cubase for tiny utilities like an online BPM tapper, separate screen/system audio recording workarounds, command-line website downloads, and file conversion. The app should feel more like a focused production bench than a generic file utility: quick, calm, local, and immediately useful while making music.

Current local environment checks found Swift 6.3, FFmpeg 8.1 at `/opt/homebrew/bin/ffmpeg`, and yt-dlp 2026.03.17 at `/opt/homebrew/bin/yt-dlp`. Those installed tools are useful for development, but the app design should not assume every future machine has them installed without a visible health check or install path.

**Current State (after v1.0, entering v1.1):**

v1.0 shipped the tool hub (Phases 1–6). Milestone audit (`v1.0-v1.0-MILESTONE-AUDIT.md`) scored 20/32 requirements satisfied: REC-01–06 partial (synthetic audio), DL-01–07 and UX-03–04 orphaned (no Phase 5/6 VERIFICATION.md). Engineering baseline restored 2026-05-22 (149 tests, 0 failures, 6 permission skips via `scripts/test.sh`).

**Known v1.1 drivers:**
- Downloader bug: `simulateAndEnqueue()` ignores non-zero yt-dlp exit — jobs enqueue after failed dry-run; stderr not surfaced (`.planning/debug/downloader-yt-dlp-failure.md`)
- Uncommitted workspace: FeatureDownloader UI/use case/view model, AppCore `StandardErrorCard` / shared components — land in Phase 7
- Output inbox: `OutputInboxInspectorView` refreshes on `onAppear` only — new outputs may not appear until view recreated

## Constraints

- **Platform**: Native macOS app - the target workflow is local production on a Mac, not a web app.
- **Audio capture**: Prefer Apple's Core Audio taps for audio-only internal capture on macOS 14.2+ - this matches the need better than recording the screen just to get sound.
- **Permissions**: The app must explain and request system audio/screen audio permissions clearly - silent failure is unacceptable for recording.
- **File output**: WAV exports must be Cubase-friendly, with explicit sample rate, channel count, and bit depth choices.
- **Downloader**: yt-dlp integration must be isolated behind a service boundary and avoid shell string interpolation - URLs and arguments must be passed safely.
- **Conversion**: Use native AVFoundation/AVFAudio when it covers the format, and FFmpeg as an adapter for broader format support.
- **Architecture**: New tools must register through a feature boundary rather than being hard-coded into one large view model.
- **Distribution**: If bundling yt-dlp or FFmpeg later, licensing and update behavior must be reviewed before release packaging.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Build native with Swift/SwiftUI | Best fit for macOS permissions, drag/drop, local files, and audio APIs. | Validated in Phase 1 |
| Treat each utility as a feature module | The user explicitly wants to add future ideas easily. | Validated in Phase 1 |
| Put internal audio capture risk early in the roadmap | Recording system audio is the least certain and most permission-sensitive feature. | v1.1 Phase 8 closes real verification |
| Wrap yt-dlp/FFmpeg as adapters instead of embedding command strings in UI code | Keeps external tools replaceable and testable. | v1.1 Phase 7 hardens downloader trust |
| Start as a local non-App-Store app | Helper tools and media downloading create packaging/licensing questions that should not block v1. | Still valid for v1.1 |
| Default conversion preset 44.1 kHz, 24-bit, preserve mono/stereo | Matches Cubase-ready WAV defaults and preserves mono sources. | Validated in Phase 3 |
| Native conversion writes .tmp.wav then moves after WAVOutputVerifier passes | Prevents partial or unverified files from becoming Cubase-ready outputs. | Validated in Phase 3 |
| External helper execution via Process.executableURL and argument arrays | Avoids command-string construction and shell interpolation. | Validated in Phase 3 and 5 |
| OutputHandoff gates drag/reveal — only .available existing .wav files | Keeps shared output inbox and future recorder outputs on one handoff safety policy. | Validated in Phase 3 |
| v1.1 phases require VERIFICATION.md before close | Phases 5–6 shipped without verification; gaps must not repeat | Active for Phases 7–10 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-23 — milestone v1.1 Production-Ready Tools started*
