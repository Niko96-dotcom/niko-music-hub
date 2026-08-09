# Niko Music Hub

Native macOS SwiftUI app for music-production chores around Cubase: browse a local Cubase archive, tap tempos, convert audio to Cubase-ready WAV, record system audio, download media, separate stems locally, and collect generated files in one output inbox.

The app is local-first. Archive scanning is read-only by default: it never renames, moves, deletes, or rewrites real Cubase/music files.

## Local dev flow

If you do not want to think like a developer, use the friendly front door:

```bash
./script/dev.sh run
```

Or double-click `Run Niko Music Hub.command` in Finder. Both paths build a fresh `dist/NikoMusicHub.app`, stop any old running copy, and open the new one.

To check whether this Mac and repo are ready:

```bash
./script/dev.sh doctor
```

To prove everything important is green:

```bash
./script/dev.sh check
```

See `docs/local-dev-flow.md` for the full no-dev workflow.

## Build and run

Requirements:

- macOS 14.2 or newer
- Apple silicon (`arm64`); Intel and universal builds are not supported release targets
- Xcode with the Swift 6 toolchain
- Optional helper tools for all workflows: `ffmpeg` and `yt-dlp`

```bash
./script/build_and_run.sh
```

Produces `dist/NikoMusicHub.app`. The first launch starts clean: add the folder that contains your Cubase song/project folders, choose an output folder if the default is not right, then scan.

Codex is wired to the same command through `.codex/environments/environment.toml`, so the app Run button builds a fresh bundle and launches Niko Music Hub.

## Local gates

```bash
./script/dev.sh check
```

Equivalent manual gates:

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
./script/build_and_run.sh --verify
```

`ci.sh` skips host-only CoreAudio recorder tests that need a working system-audio capture device.

For visual proof of a foreground app window:

```bash
./script/capture_window_proof.sh
```

This saves `dist/window-visible-proof.png` and `dist/desktop-proof.png`.

## GitHub workflow

This repo uses GitHub for review and history, but local gates are the source of truth. Before opening or merging a PR, run:

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```

GitHub Actions are intentionally not required for this project.

## Release engineering

`VERSION` is the canonical release version and `BUNDLE_ID` is the permanent app identity. Maintainer release commands live in `script/release-all.sh`; public mode signs, notarizes, staples, validates, checksums, creates an approval record, and optionally publishes GitHub Release assets. Local-only mode is explicitly labeled and cannot publish.

```bash
./script/release-all.sh --local-only
./script/release-all.sh --public --dry-run-publish
```

See `docs/release.md` and `docs/release-validation.md`.

## Fixtures

```bash
./script/fixtures/generate_cubase_archive_fixtures.sh
swift run NikoMusicCoreSelfTest
```

Fixture archive layout: `Fixtures/CubaseArchive/` — synthetic song folders covering the happy path
(Neon Hook, Second Song), preview ranking and score tiebreaks (Preview Ranking Lab, Equal Score
Duration/Version/Extension Tiebreak), real-world naming (90s Rave, Amber Moth), and malformed input
(Broken Folder Example, LOOSE_FILE.txt). `.cpr` files are empty placeholders and `.wav` files are
minimal silence — never copy a real user archive into this tree. See
`Fixtures/CubaseArchive/README.md`.

## Visible tools

| Tool | What it does |
|------|--------------|
| Archive | Scans selected Cubase archive roots, searches songs, previews mixdowns, and opens the newest `.cpr` read-only. |
| BPM Tapper | Tap or press Space to estimate tempo, adjust half/double time, save recent BPMs, and copy results. |
| WAV Converter | Drag or choose audio files, convert to Cubase-ready WAV presets, and hand verified outputs to the inbox. |
| Recorder | Capture system audio on supported macOS versions and save recordings to the selected output folder. |
| Downloader | Download supported URLs through `yt-dlp` into the shared output folder. |
| Stem Separation | Split audio into vocals/drums/bass/other stems locally using `demucs-mlx`. |
| Output Inbox | Shows generated files from registered tools with reveal/drag-out actions. |

## Safety

- Archive scanning and CPR open are **read-only** toward music roots.
- Use `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1` for automation (logs path, does not open Cubase).
- App metadata lives under `~/Library/Application Support/Niko Music Hub/`.
- Developer-only surfaces are hidden from normal builds. Set `NIKO_MUSIC_HUB_SHOW_DEV_TOOL=1` only when working on app internals.

## Known limitations

- GitHub Actions are not configured; local gates are the source of truth.
- System-audio recording depends on macOS support and local privacy permission.
- `ffmpeg` and `yt-dlp` are optional external tools. The app shows compact helper health, but installing or updating them is still a user action.
- `demucs-mlx` is an optional external tool for stem separation. See `docs/user-guide-stem-separation.md`.
- The archive browser is intentionally local-only and does not manage files inside real Cubase archives.
- Menu bar quick access provides one-click routing to all tools from the macOS status bar. See `docs/menu-bar-quick-access.md` for the entry list and design rationale.

## Automation

`./script/e2e_user_smoke.sh` covers the fixture archive flow, dry-run CPR open, read-only archive proof, diagnostics export parity, and a public first-run UI smoke that rejects prototype labels, fixture paths, temp paths, and exposed diagnostics in the normal app window.

Every public build requires a newly approved exact-commit UAT record. See `docs/release.md` for the evidence format and `docs/user-e2e.md` for smoke details.

For a commercial source handoff, use `script/export-source-sale.sh`. It creates a buyer-safe export without private planning/agent history and refuses a sale-labeled archive without an exact-commit provenance attestation.
