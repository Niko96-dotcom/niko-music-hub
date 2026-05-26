# Niko Music Hub

Native macOS SwiftUI app combining outside-Cubase production tools with a read-only Cubase archive browser.

## Working in Cursor (this session)

If your workspace is this repository (cloud or local checkout), **you are already set up** — no install script, no clone step, nothing to run first. Ask the agent to change code, docs, or tests here.

- **Edit & ship from Cursor Cloud:** full repo at workspace root; push via git when ready.
- **Build the Mac app:** needs a Mac with Xcode (`swift build`, `./script/build_and_run.sh`). Cloud/Linux cannot compile SwiftUI.

Optional Mac-only folder (only if you want a separate copy under Documents): see `docs/local-development.md`.

## Build and run

```bash
swift build
./script/build_and_run.sh
```

Produces `dist/NikoMusicHub.app`.

## Local gates

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```

`ci.sh` skips host-only CoreAudio recorder tests that need a working system-audio capture device.

## Fixtures

```bash
./script/fixtures/generate_cubase_archive_fixtures.sh
swift run NikoMusicCoreSelfTest
```

Fixture archive layout: `Fixtures/CubaseArchive/` (Neon Hook, Second Song, Broken Folder Example).

## Safety

- Archive scanning and CPR open are **read-only** toward music roots.
- Use `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1` for automation (logs path, does not open Cubase).
- App metadata lives under `~/Library/Application Support/Niko Music Hub/`.

## Tools

| Tool | ID |
|------|-----|
| Archive Browser (default home) | `archive-browser` |
| BPM Tapper | `bpm-tapper` |
| WAV Converter | `wav-converter` |
| Audio Recorder | `audio-recorder` |
| Downloader | `downloader` |

See `docs/user-e2e.md` for smoke details and `AGENTS.md` for agent workflow rules.
