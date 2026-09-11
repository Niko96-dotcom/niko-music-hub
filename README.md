<p align="center">
  <img src="Resources/Brand/AppLogo-96.png" width="88" alt="Niko Music Hub icon">
</p>

<h1 align="center">Niko Music Hub</h1>

<p align="center">
  The production desk beside your DAW.<br>
  Recall any song in your Cubase or Ableton archive, audition it instantly, and handle the chores around it — in one native macOS app.
</p>

<p align="center">
  <a href="https://github.com/Niko96-dotcom/niko-music-hub/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Niko96-dotcom/niko-music-hub?display_name=tag&color=1f6feb"></a>
  <img alt="macOS 14.2+" src="https://img.shields.io/badge/macOS-14.2%2B-000000?logo=apple&logoColor=white">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-arm64-333333">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-0A84FF">
  <img alt="License" src="https://img.shields.io/badge/license-proprietary%2C%20source--available-6f42c1">
</p>

<p align="center">
  <img src="docs/assets/board.png" width="920" alt="The archive board: songs as cards in workflow stages, with the persistent preview player docked at the bottom">
</p>

## Why

Producers accumulate hundreds of song folders, each with a handful of project versions and a pile of bounces. Finding the right one, hearing it, and opening the latest project should take seconds — without ever risking the files themselves. Niko Music Hub is built around that: **everything it does to your archive is read-only**, and everything it *creates* lands in one place.

## What it does

**Archive Browser** — scans your song folders once, then keeps a fast local index. Browse as a board (songs as cards moving through Songstarter → Song → Session → Prod → Feedback → Done) or as a searchable list. Search is diacritic- and typo-tolerant across titles, aliases, notes and collaborators.

**Persistent preview player** — press play on any card or row and the mixdown keeps playing while you switch tools, songs or views. **Compare** swaps between bounces of the same song at the same elapsed moment, so you hear the difference, not the restart.

**Song detail** — the main project with one-click *Open in Cubase* / *Open in Ableton*, every project version, every preview candidate (with automatic main-preview ranking you can override), song info, notes, and the plugins the main project uses.

**Project Vault** — optional, off by default: safely archive finished projects to a second location and restore them on demand, with verified copies, recovery records and a read-only view of what lives where.

**Production tools** — a **WAV Converter** with DAW-ready presets, a **system-audio Recorder**, a **Downloader** (via `yt-dlp`), local **Stem Separation** (via `demucs-mlx`), and a **BPM Tapper**. Everything they produce appears in the **Output Inbox**, ready to reveal or drag into a session.

**Always at hand** — a menu-bar quick-access menu routes to every tool, and the app keeps itself current with **in-app updates** from a signed release feed.

<table>
  <tr>
    <td><img src="docs/assets/song-detail.png" alt="Song detail: main project, versions, and the details rail"></td>
    <td><img src="docs/assets/previews.png" alt="Preview candidates with Compare and main-preview selection"></td>
  </tr>
  <tr>
    <td align="center"><sub>Song detail — versions, previews, song info, plugins</sub></td>
    <td align="center"><sub>Preview candidates — compare bounces at the same moment</sub></td>
  </tr>
  <tr>
    <td><img src="docs/assets/converter.png" alt="WAV Converter"></td>
    <td><img src="docs/assets/recorder.png" alt="Audio Recorder"></td>
  </tr>
  <tr>
    <td align="center"><sub>WAV Converter — drop files, pick a preset, hand off to the inbox</sub></td>
    <td align="center"><sub>Audio Recorder — capture system audio, previews pause automatically</sub></td>
  </tr>
</table>

## Install

Requires **macOS 14.2 or newer on Apple silicon**.

1. Download `NikoMusicHub-<version>.dmg` and its `.sha256` from the [latest release](https://github.com/Niko96-dotcom/niko-music-hub/releases/latest).
2. Optionally verify it: `shasum -a 256 -c NikoMusicHub-<version>.dmg.sha256`
3. Open the DMG and drag **Niko Music Hub** into `/Applications`.

The app is signed with a Developer ID and notarized. After the first install it checks for updates once a day and installs them for you; **Niko Music Hub ▸ Check for Updates…** checks immediately, and **Settings ▸ Updates** turns automatic checks off. Updates are downloaded from a signed feed and verified before anything is unpacked.

Optional helpers, each detected automatically if present: [`ffmpeg`](https://ffmpeg.org) for conversion and downloads, [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) for the Downloader, [`demucs-mlx`](docs/user-guide-stem-separation.md) for stem separation.

## Safety guarantees

- Archive scanning, previews and project opening are **read-only** toward your music folders. The app never renames, moves, deletes or rewrites a file there — the only exception is a Project Vault transfer you explicitly confirm.
- Everything the app creates goes to the output folder you choose (default `~/Music/Niko Music Hub/Inbox`).
- App state lives in `~/Library/Application Support/Niko Music Hub/`. Uninstall by removing the app; remove that folder only if you want to clear the local index and settings.
- Automation runs use `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1`, which logs what it would open instead of launching your DAW.

## Build from source

```bash
git clone https://github.com/Niko96-dotcom/niko-music-hub.git
cd niko-music-hub
./script/dev.sh run        # builds dist/NikoMusicHub.app and opens it
```

`./script/dev.sh doctor` checks that this Mac has what it needs; `./script/dev.sh check` runs every gate that matters. The two gates are:

```bash
./script/ci.sh              # build, unit tests, release-engineering regression tests
./script/e2e_user_smoke.sh  # drives the real app through the fixture archive
```

Tests run against a synthetic archive under `Fixtures/CubaseArchive/` — empty placeholder projects and near-silent mixdowns generated by `script/fixtures/generate_cubase_archive_fixtures.sh`. Never point tests at a real archive.

### Architecture

| Module | Role |
|---|---|
| `NikoMusicCore` | Pure Swift: scanning, indexing, search, preview ranking, project-vault engine, opening safety. No UI. |
| `AppCore` | Shared shell: tool registry, settings, jobs, output inbox, diagnostics, design system. |
| `FeatureArchiveBrowser` | The board, list, song detail, persistent player and Project Vault UI. |
| `FeatureAudioConverter` · `FeatureAudioRecorder` · `FeatureDownloader` · `FeatureStemSeparation` · `FeatureBPMTapper` | Independent tools registered through the same `ToolFeature` boundary. |
| `AppUpdates` | Sparkle integration, isolated so nothing else links it. |
| `NikoMusicHub` | The app target: composition root, shell, menus, settings. |

Full detail in [`docs/architecture.md`](docs/architecture.md); product intent in [`docs/product-scope.md`](docs/product-scope.md).

### Releases

Releases are built locally and fail closed: a clean tagged checkout, every gate green, an approved exact-commit acceptance record, Developer ID signing, notarization, stapling, and a signed update feed verified against the key inside the shipped app — before a single byte is uploaded. See [`docs/release.md`](docs/release.md), [`docs/release-validation.md`](docs/release-validation.md) and [`docs/update-feed.md`](docs/update-feed.md).

## Contributing

Issues and pull requests are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). Keep product code in Swift, keep archive access read-only, and run both gates before opening a PR. GitHub Actions are intentionally not used; the local gates are the source of truth.

## License

Niko Music Hub is **source-available, not open source**. The source is published so you can read it, audit it and build it for yourself; any other use needs a written agreement — see [`LICENSE`](LICENSE). Third-party components keep their own licenses, listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
