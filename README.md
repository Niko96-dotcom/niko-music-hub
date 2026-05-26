# Niko Music Hub

Native macOS SwiftUI app combining outside-Cubase production tools with a read-only Cubase archive browser.

## Local setup (Mac)

Clone and open on your Mac (Swift does not build on Linux CI sandboxes):

```bash
git clone https://github.com/Niko96-dotcom/niko-music-hub.git ~/src/niko-music-hub
cd ~/src/niko-music-hub
./script/setup_mac_check.sh
```

Full workflow (Cursor + cloud agent + real archive): **[docs/local-development.md](docs/local-development.md)**.

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
