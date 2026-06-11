# Niko Music Hub

## What This Is

Niko Music Hub is a local macOS app for production chores outside Cubase — BPM tap, internal audio capture, downloads, conversion — and a **Cubase archive browser** for recall: persisted scan index, app-owned metadata, smart shelves, waveform preview, collaborators, filters, new-song flow, and read-only intelligence. Built for one producer first, with a registry-driven tool hub so new utilities register without rewriting the shell.

## Core Value

Repeated production chores outside Cubase should become fast, local, reliable, and drag-and-drop ready for a Cubase project.

## Current Milestone: v1.4 Downloader Reliability

**Goal:** Make the downloader trustworthy for real daily use by replacing brittle timeout/progress behavior with reality-tested downloads, clearer helper health, correct media handoff, and user-style verification.

**Target features:**
- Real `yt-dlp` progress reporting from parseable progress markers instead of mocked `[download]` lines.
- Long-download handling that removes the 90-second total kill timer and uses stall-aware protection where needed.
- `yt-dlp`/FFmpeg health that detects outdated tools, gives upgrade guidance, validates selected formats, and retries the failures it claims are retryable.
- Downloader output handoff for producer-useful media types such as MP3, M4A, MP4, and WEBM through reveal/open/drag flows.
- Structured download result handoff from jobs to the output inbox instead of regex-parsing log text back into file URLs.
- Real invocation/UAT coverage for long or slow downloads, helper-path scenarios, progress parsing, and media handoff.

**Last shipped (v1.3):** Design system + glass shell, tool page redesign (BPM, recorder, converter, downloader, settings), archive browse/detail UI, shared error-card polish (`docs/UI-REDESIGN-PLAN.md`).

**Prior (v1.2):** Archive persistence, metadata core, smart shelves, waveform player, browse/collaborators, filters/BPM polish, new song flow, read-only intelligence (CP-01–CP-18).

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

### Validated (v1.1)

- ✓ Downloader reliability and stderr surfacing — v1.1 Phase 7
- ✓ Real Core Audio process tap recorder — v1.1 Phase 8
- ✓ Output inbox live refresh — v1.1 Phase 9
- ✓ Hub helper health and verification discipline — v1.1 Phase 10

### Validated (v1.2)

- ✓ Archive SQLite index + FSEvents refresh — v1.2 Phase 11
- ✓ Virtual title, notes, manual preview, first-run roots — v1.2 Phase 12
- ✓ Smart shelves (recent bounce / CPR) — v1.2 Phase 13
- ✓ Waveform hero + seek — v1.2 Phase 14
- ✓ Browse home, collaborators, CPR override, shortcuts, search — v1.2 Phase 15
- ✓ Sort, filters, health report, mixdown BPM — v1.2 Phase 16
- ✓ New song folder flow — v1.2 Phase 17
- ✓ Read-only intelligence + JSON export — v1.2 Phase 18

### Validated (v1.3)

- ✓ Design system foundation (DS-01–DS-08) — Phase 19
- ✓ Shell & navigation (SH-01–SH-04) — Phase 20
- ✓ Tool UI: BPM, recorder, converter (TOOL-01–TOOL-03) — Phase 21
- ✓ Tool UI: downloader, settings (TOOL-04–TOOL-05) — Phase 22
- ✓ Archive browse & sidebar (ARCH-01–ARCH-03) — Phase 23
- ✓ Archive detail & panels (ARCH-04–ARCH-06) — Phase 24
- ✓ UI polish & visual regression (POL-01, POL-02; QA-03 visual UAT deferred) — Phase 25

### Active

- [ ] Downloader reports real `yt-dlp` progress from the app's actual command invocation.
- [ ] Downloads are not killed solely because they take longer than 90 seconds.
- [ ] Helper health surfaces stale `yt-dlp` and gives clear upgrade/install guidance.
- [ ] Download simulation validates the selected format path and avoids playlist surprises.
- [ ] Completed downloader media can be revealed, opened, and dragged from the output inbox when safe.
- [ ] Downloader jobs pass structured output file URLs to the inbox without log regex round-tripping.
- [ ] Downloader UAT covers real-world behavior beyond the 18-second happy path.

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

**Current State (after v1.3):**

v1.0–v1.3 shipped on `main`. UI follows `docs/UI-REDESIGN-PLAN.md`. Archive browser and tool hub remain modular via `ToolFeature`. `./script/ci.sh` and `./script/e2e_user_smoke.sh` are the local gates.

**v1.4 source audit:**

The 2026-06-11 downloader audit found that the app architecture is sound, but the downloader shipped with mock-reality drift. The failure cluster is concentrated around a 90-second total timeout, no parseable real progress output, stale helper detection that never reports outdated `yt-dlp`, WAV-only output handoff that leaves downloaded media as dead-end inbox rows, and structured output data flattened into logs then parsed back with regex.

**Known follow-ups:**
- v1.1 phases 7–10: human UAT items still in VERIFICATION.md (`human_needed`)
- v1.2 tech debt: FSEvents full rescan (CP-02), optional new-song template UI, CPR plugin summary deferred — see `.planning/milestones/v1.2-MILESTONE-AUDIT.md`
- v1.4 downloader audit: UTF-8 streaming chunk loss, retry text mismatch, video format selector fallback, no busy timeout in SQLite stores, and FSEvents watcher locking are known follow-ups to triage while scoping requirements.
- P3 (CP-19+): multi-DAW, cloud sync, AI search — out of scope until new milestone

## Constraints

- **Platform**: Native macOS app - the target workflow is local production on a Mac, not a web app.
- **Audio capture**: Prefer Apple's Core Audio taps for audio-only internal capture on macOS 14.2+ - this matches the need better than recording the screen just to get sound.
- **Permissions**: The app must explain and request system audio/screen audio permissions clearly - silent failure is unacceptable for recording.
- **File output**: WAV exports must be Cubase-friendly, with explicit sample rate, channel count, and bit depth choices.
- **Downloader**: yt-dlp integration must be isolated behind a service boundary and avoid shell string interpolation - URLs and arguments must be passed safely, progress must come from real `yt-dlp` output, and long downloads must not fail only because they are long.
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
| v1.1 phases require VERIFICATION.md before close | Phases 5–6 shipped without verification; gaps must not repeat | ✓ Applied Phases 7–10 |
| Native Swift archive recall in NikoMusicCore + FeatureArchiveBrowser | Port MacBook reference behaviors; read-only toward music roots | ✓ v1.2 |
| Treat downloader reliability as v1.4 milestone scope | The audit found interacting real-world failures that green tests missed; fixing them coherently is safer than another narrow patch. | — Pending |
| Use real helper output as the downloader source of truth | Mocked `[download]` lines hid that the app's actual `yt-dlp` invocation emits no progress; requirements and tests must cover the real command shape. | — Pending |
| Keep downloader media handoff explicit and safe | WAV-only handoff is correct for converter/recorder outputs but breaks downloaded MP3/M4A/MP4 workflows. | — Pending |

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
*Last updated: 2026-06-11 — milestone v1.4 Downloader Reliability started*
