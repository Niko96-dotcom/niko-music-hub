# Niko Music Hub

[![Platform](https://img.shields.io/badge/platform-macOS%2014.2+-111111?logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6.x-f05138?logo=swift&logoColor=white)](Package.swift)
[![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-147efb)](docs/architecture.md)
[![Local First](https://img.shields.io/badge/archive%20policy-read--only-2e7d32)](#safety-model)
[![Release](https://img.shields.io/badge/release-v0.1.0-6f42c1)](CHANGELOG.md)

Native macOS music-production utility for browsing Cubase archives, previewing mixdowns, opening the latest `.cpr`, tapping tempos, converting audio, recording system audio, downloading media, and collecting generated files in one output inbox.

**Website:** [niko96-dotcom.github.io/niko-music-hub](https://niko96-dotcom.github.io/niko-music-hub/)

![Niko Music Hub first-run screen](docs/assets/niko-music-hub-first-run.png)

## Why It Exists

Large Cubase archives are usually organized as folders, not memories. Niko Music Hub turns those folders into a fast recall surface: pick one or more archive roots, scan read-only, search by song/project/preview names, hear the strongest preview candidate, then open the newest Cubase project file without digging through Finder.

The app is intentionally local-first. It does not upload archives, index cloud accounts, rename projects, move audio, delete sessions, or rewrite music files.

## Product Surface

| Area | What it does | Safety boundary |
| --- | --- | --- |
| Archive Browser | Scans selected Cubase archive roots into song cards, ranked previews, CPR versions, diagnostics, and search results. | Reads metadata and audio headers only; no writes under archive roots. |
| Preview Ranking | Picks the strongest mixdown using role, folder, filename, version, extension, duration, and recency signals. | Ranking is derived from files already present on disk. |
| Open Latest CPR | Opens or reveals the most recently modified `.cpr` for a song. | Dry-run mode is available for tests and automation. |
| BPM Tapper | Tap or press Space to estimate tempo, adjust half/double time, save recent values, and copy results. | Stores app-owned history only. |
| WAV Converter | Converts dragged or selected audio into Cubase-ready WAV presets. | Writes only to the selected output folder. |
| Recorder | Captures system audio on supported macOS builds and saves WAV files to the output folder. | Requires local macOS privacy permission. |
| Downloader | Uses `yt-dlp` for supported URLs and hands completed files to the inbox. | User-controlled URLs and app-owned output folder only. |
| Output Inbox | Shows generated files from converter, recorder, and downloader with reveal/open actions. | Does not mutate source archives. |

## Requirements

| Requirement | Notes |
| --- | --- |
| macOS | 14.2 or newer. System-audio recording depends on CoreAudio process tap support and local privacy permission. |
| Xcode | Swift 6.x toolchain. Full Xcode is recommended for XCTest. |
| Optional helpers | `ffmpeg` for broader conversion fallback and `yt-dlp` for downloads. |
| Cubase | Optional. The archive browser can scan fixtures and real folders without Cubase installed; opening `.cpr` files needs the normal macOS file association. |

## Build And Run

```bash
./script/build_and_run.sh
```

The script builds `dist/NikoMusicHub.app` and launches the native app. On first launch, add the folder that contains your Cubase song/project folders, choose an output folder if needed, then scan.

For a dry-run archive open that logs the target path without launching Cubase:

```bash
NIKO_MUSIC_HUB_DRY_RUN_OPEN=1 ./script/build_and_run.sh
```

## Local Verification

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
./script/build_and_run.sh --verify
```

`script/ci.sh` runs `swift build`, the deterministic test suite, and `NikoMusicCoreSelfTest`. It skips host-only CoreAudio recorder tests that need a usable local system-audio capture device.

`script/e2e_user_smoke.sh` regenerates fixtures, builds the app bundle, runs the archive user flow through the real app binary, verifies dry-run CPR open, proves the fixture archive is unchanged, and checks the public first-run UI.

## Fixture Archive

```bash
./script/fixtures/generate_cubase_archive_fixtures.sh
swift run NikoMusicCoreSelfTest
```

Fixtures live under `Fixtures/CubaseArchive/`. They contain placeholder `.cpr` files and generated test audio only. No real Cubase projects or private music files are required.

## Architecture

| Module | Role |
| --- | --- |
| `NikoMusicCore` | Pure Swift scanning, preview ranking, search, diagnostics, path safety, and open policy. |
| `AppCore` | Tool registry, shared settings, jobs, output inbox, diagnostics, and UI primitives. |
| `FeatureArchiveBrowser` | SwiftUI archive browse/search/detail/preview feature registered through `ToolFeature`. |
| `FeatureBPMTapper` | Tempo estimation, adjustments, history, and clipboard output. |
| `FeatureAudioConverter` | Native/FFmpeg conversion pipeline and WAV verification. |
| `FeatureAudioRecorder` | CoreAudio process tap adapter, recorder view model, and WAV writer. |
| `FeatureDownloader` | `yt-dlp` health checks, progress parsing, and inbox handoff. |
| `NikoMusicHub` | Native macOS app target and feature composition. |

More detail: [architecture](docs/architecture.md), [archive model](docs/archive-model.md), [user E2E](docs/user-e2e.md), [release validation](docs/release-validation.md).

## Safety Model

- Archive roots are opt-in and read-only.
- The scanner enumerates folders, reads metadata, and reads audio headers for duration.
- CPR open/reveal checks paths against selected roots before handoff.
- Generated files go to the selected output folder, not into music archives.
- App metadata is stored under `~/Library/Application Support/Niko Music Hub/`.
- No Electron, React, TypeScript, Python runtime, or cloud service is embedded in the shipped app.

## Repository Map

| Path | Purpose |
| --- | --- |
| `Sources/` | Swift package targets and macOS app code. |
| `Tests/` | Fixture-first unit and integration tests. |
| `Fixtures/` | Deterministic public test archive generated by script. |
| `script/` | Build, CI, E2E, and fixture generation scripts. |
| `docs/` | Public product, architecture, validation, and landing-page docs. |

## Status

Niko Music Hub is at `v0.1.0`: a working local-first native macOS app with public fixtures and local gates. GitHub Actions are intentionally not configured; local verification is the release gate.

## License

MIT. See [LICENSE](LICENSE).
