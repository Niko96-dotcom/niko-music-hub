# Source Inventory — Niko Music Hub

Last verified: 2026-05-31

## Repo State

| Item | Value |
|------|-------|
| Local path | `/Users/niko/Documents/Niko-Music-Hub` |
| SwiftPM package name | `NikoMusicHub` |
| macOS platform | 14.2+ |
| CI gate | `./script/ci.sh` |
| E2E gate | `./script/e2e_user_smoke.sh` |
| Fixtures | `Fixtures/CubaseArchive/` |
| App bundle | `dist/NikoMusicHub.app` |

## SwiftPM Targets

| Target | Kind | Role |
|--------|------|------|
| `AppCore` | library | Shared settings, jobs, output inbox, helper process APIs, WAV verification, common UI |
| `NikoMusicCore` | library | Archive scanning, search, browse projections, preview/CPR ranking, persistence contracts, read-only safety |
| `FeatureArchiveBrowser` | library | SwiftUI archive browser and debug-only archive smoke harness |
| `FeatureBPMTapper` | library | Tap tempo, history, clipboard |
| `FeatureAudioConverter` | library | Native/FFmpeg WAV conversion |
| `FeatureAudioRecorder` | library | System-audio capture and recorder UI |
| `FeatureDownloader` | library | yt-dlp health, format selection, download jobs |
| `NikoMusicHub` | executable | App composition, shell, settings, Output Inbox |
| `NikoMusicCoreSelfTest` | executable | Fixture/real-root archive self-test |

## Local Gates

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
./script/build_and_run.sh --verify
```

`ci.sh` runs `swift build`, `swift test` with documented CoreAudio host-only skips, and `swift run NikoMusicCoreSelfTest`.

`e2e_user_smoke.sh` now delegates archive scenario assertions to the Swift smoke validator and keeps shell checks focused on orchestration plus public first-run UI text.

## Registered Tool Features

| ID | Module | Display name |
|----|--------|--------------|
| `archive-browser` | `FeatureArchiveBrowser` | Archive Browser |
| `bpm-tapper` | `FeatureBPMTapper` | BPM Tapper |
| `wav-converter` | `FeatureAudioConverter` | WAV Converter |
| `audio-recorder` | `FeatureAudioRecorder` | Audio Recorder |
| `downloader` | `FeatureDownloader` | Downloader |
| `settings` | `NikoMusicHub/Settings` | Settings |
| `dev-tool` | `NikoMusicHub/DevTool` | Developer Tool, hidden unless explicitly enabled |

## Safety Boundaries

- Archive roots are read-only by default. The archive browser must not rename, move, delete, or rewrite files under user music roots.
- New song drafts are app-output-folder drafts, not archive-root writes.
- App-owned metadata lives under Application Support or test temp directories.
- The product is native Swift/SwiftUI; Electron, React, TypeScript, Python runtimes, and npm build chains stay reference-only.

## Reference Inputs

| Path | Purpose |
|------|---------|
| `docs/reference/cubase-file-orga/` | Cubase archive behavior/spec reference only |
| `docs/product-scope.md` | v0.1 product contract and non-goals |
| `docs/user-e2e.md` | E2E smoke details |
| `AGENTS.md` | Repository agent rules |
