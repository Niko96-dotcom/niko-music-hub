# Source Inventory — Niko Music Hub

Last verified: 2026-05-25

## Repo state

| Item | Value |
|------|-------|
| Local path | `/Users/nikolaymohr/src/niko-music-hub` |
| Git remote | `Niko96-dotcom/niko-music-hub` (private) |
| SwiftPM package name | `OutsideCubaseHub` (seed name; rename planned) |
| macOS platform | 14.2+ |
| Listed tests | 154 (`swift test --list-tests`) |
| CI gate | `./script/ci.sh` — skips 5 CoreAudio host-only recorder tests |
| E2E gate | `./script/e2e_user_smoke.sh` — **stub, exits 2** |
| Fixtures | **none yet** |
| `NikoMusicCore` | **not present** |
| `FeatureArchiveBrowser` | **not present** |

## Seed: OutsideCubaseHub (copied from MacBook)

Canonical MacBook source (read-only reference):

```text
/Users/niko/Documents/OutSideCubaseHub
```

Reported MacBook gate at copy time: 154 passed, 6 skipped (system-audio permission), 0 failures.

**MacBook rule (authoritative):** read-only reference and rsync/copy into this repo only. Do not modify MacBook projects in place or run ad-hoc test loops there during executor work.

### SwiftPM targets (current)

| Target | Kind | Role |
|--------|------|------|
| `AppCore` | library | `ToolFeature`, `ToolRegistry`, `ToolContext`, jobs, output inbox, settings, shared UI/error components |
| `FeatureBPMTapper` | library | Tap tempo, history, clipboard |
| `FeatureAudioConverter` | library | WAV conversion (FFmpeg + native path), batch jobs |
| `FeatureAudioRecorder` | library | System-audio capture (CoreAudio tap), WAV writer |
| `FeatureDownloader` | library | yt-dlp download jobs |
| `OutsideCubaseHub` | executable | App entry, composition root, AppKit shell |
| `*Tests` | test | Per-module XCTest suites |

### Registered tool features (`AppComposition.make`)

| ID | Module | Display name | Notes |
|----|--------|--------------|-------|
| `dev-tool` | `OutsideCubaseHub/DevTool` | Developer Tool | Internal/debug |
| `bpm-tapper` | `FeatureBPMTapper` | BPM Tapper | |
| `wav-converter` | `FeatureAudioConverter` | WAV Converter | Default selected tool in shell |
| `audio-recorder` | `FeatureAudioRecorder` | Audio Recorder | CoreAudio; host-gated tests |
| `downloader` | `FeatureDownloader` | Downloader | yt-dlp + health checks |

### App shell layout

`Sources/OutsideCubaseHub/AppShell/AppShellView.swift`:

- Left: `ToolSidebarView` (280pt) — tool picker
- Center: active `ToolFeature.makeView`
- Right: `OutputInboxInspectorView` (280pt)
- Min window: 1060×600

Application Support path (today): `~/Library/Application Support/Outside Cubase Hub/output-inbox.json`

### Scripts

| Script | Status |
|--------|--------|
| `script/ci.sh` | Build + test (+ optional `NikoMusicCoreSelfTest` when target exists) |
| `script/build_and_run.sh` | Builds `dist/OutsideCubaseHub.app`, bundle id `local.outside-cubase-hub.app` |
| `script/e2e_user_smoke.sh` | Stub only |
| `script/run_composer_sequence.sh` | Pi role runner |

### Test inventory (by module)

| Test target | Approx. focus |
|-------------|----------------|
| `AppCoreTests` | Registry, jobs, inbox, settings, handoff |
| `FeatureBPMTapperTests` | Tempo, history, view model |
| `FeatureAudioConverterTests` | Pipeline, FFmpeg, presets, handoff |
| `FeatureAudioRecorderTests` | WAV writer, permissions, CoreAudio (partially CI-skipped) |
| `FeatureDownloaderTests` | yt-dlp parsing, trust/errors, use case |

### Test antipattern (do not extend)

Several seed tests assert `String(contentsOf:)` on Swift source files (`source.contains(...)`). That is not behavior coverage. **New archive/core tests must use fixture I/O and domain assertions only.**

## Reference: Cubase File Orga (Electron v1.0)

Copied into `docs/reference/cubase-file-orga/` — **behavior/spec only**, not implementation.

| File | Contents |
|------|----------|
| `SPEC.md` | Product contract: one-folder-one-song, preview confidence, open latest CPR, search, collaborator model, scanner rules |
| `DESIGN_SYSTEM.md` | Dark editorial UI tokens (colors, type, SongCard, waveform hero) |
| `PROJECT.md` | Shipped v1.0 summary, constraints, non-goals |

MacBook canonical path (read-only):

```text
/Users/niko/Library/Mobile Documents/com~apple~CloudDocs/Documents/02_PROJECTS/01_ACTIVE_PROJECTS/CUBASE FILE ORGA
```

**Do not import:** Electron, React, TypeScript, `better-sqlite3`, Zustand, chokidar, Howler, npm build chain.

**Port into Swift:** scanner semantics, preview ranking policy, search fields, UI contract (browse → detail → play → open latest CPR), read-only safety.

## Reference: Automation Health (SwiftUI style)

Path: `/Users/nikolaymohr/src/automation-health`

| Pattern | Use for Niko Music Hub |
|---------|------------------------|
| `AutomationHealthCore` + `ActiveJobsCore` split | Mirror as `NikoMusicCore` (pure) + feature UI |
| `ActiveJobsCoreSelfTest` executable | Mirror as `NikoMusicCoreSelfTest` for fixture/real-root CLI |
| `AutomationHealthApp` + `WindowGroup` + `AppDelegate` activation | Same macOS app bootstrap pattern |
| `ContentView` + sidebar/detail | Archive browser can adopt editorial layout; outside tools keep existing 3-column tool shell |

## Gaps vs v0.1 target

| Gap | Executor slice |
|-----|----------------|
| No `Fixtures/CubaseArchive/` | Slice 1 |
| No `NikoMusicCore` | Slices 1–4 |
| No archive feature module | Slices 6–9 |
| Package still named `OutsideCubaseHub` | Slice 5 |
| No `.app` rename / bundle id | Slice 5 |
| E2E stub | Slice 10 |
| Real-archive smoke CLI | Slice 11 |
| No `docs/user-e2e.md` | Slice 12 |

## Isolation inventory (must not touch)

- `/Users/nikolaymohr/locus`
- `/Users/nikolaymohr/.hermes/worktrees/locus-*`
- `/Users/nikolaymohr/.hermes/workers/locus-*`
- MacBook projects in place (rsync/copy only)
- Real music/archive files (read-only scan only)
