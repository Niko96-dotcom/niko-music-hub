# Local Dev Flow

This is the plain-English workflow for keeping Niko Music Hub easy to run on this Mac. It is safe toward real Cubase/music folders: the automated checks use fixtures, and archive scanning remains read-only by default.

## Best Everyday Flow

Use one of these:

- Press the Codex Run button. It runs `./script/build_and_run.sh`.
- Double-click `Run Niko Music Hub.command` in Finder.
- In Terminal, run `./script/dev.sh run`.

Each path rebuilds `dist/NikoMusicHub.app`, stops the old running app, and opens the fresh one.

## When You Want To Know Everything Is Good

Use one of these:

- Double-click `Check Niko Music Hub.command` in Finder.
- In Terminal, run `./script/dev.sh check`.

That runs the full local truth:

1. `./script/ci.sh`
2. `./script/e2e_user_smoke.sh`
3. `./script/build_and_run.sh --verify`

Green means the app compiled, deterministic tests passed, the user-style archive smoke passed, and the rebuilt app launched with a visible window.

Passing command output is saved under `.build/dev-flow/` so the screen stays readable. If a step fails, `./script/dev.sh check` prints the last useful log lines and points to the full log file.

## If Something Breaks

Start with:

```bash
./script/dev.sh doctor
```

Doctor checks macOS, Swift/Xcode tools, repo wiring, executable scripts, ignored generated output, the Codex Run action, and helper tools.

Then use the focused commands:

| Command | Use it for |
|---------|------------|
| `./script/dev.sh run` | Build and open the app. |
| `./script/dev.sh check` | Full local verification before calling work done. |
| `./script/dev.sh doctor` | Find missing setup or wiring problems. |
| `./script/dev.sh logs` | Open the app and stream logs. |
| `./script/dev.sh proof` | Save visible-window screenshots under `dist/`. |
| `./script/dev.sh stop` | Stop any running app instance. |
| `./script/dev.sh clean` | Delete generated build output only. |
| `./script/dev.sh helpers` | Install or update `ffmpeg` and `yt-dlp` through Homebrew. |

## What Not To Worry About

- `dist/`, `.build/`, `DerivedData/`, screenshots, and smoke logs are generated output.
- `./script/dev.sh clean` removes generated build output only; it does not touch music archives or app settings.
- The local checks may open Niko Music Hub. That is expected.
- Recorder hardware tests are intentionally skipped by `./script/ci.sh` because system-audio capture depends on local macOS permissions and devices.

## What To Ask Codex

Good prompts:

- `run ./script/dev.sh doctor and fix anything required`
- `run ./script/dev.sh check and fix failures`
- `build and restart the app`
- `show me the app logs while I try the broken thing`
