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
2. `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh`
3. `./script/build_and_run.sh --verify-isolated`

Green means the app compiled, deterministic tests passed, the user-style archive smoke passed, and the rebuilt app launched with a visible window.

Passing command output is saved under `.build/dev-flow/` so the screen stays readable. If a step fails, `./script/dev.sh check` prints the last useful log lines and points to the full log file.

The final startup check builds `dist/verification/NikoMusicHub.app`, then makes a disposable
copy under `dist/verification/isolated-apps/` with a fresh settings suite and a distinct
bundle identifier. AppKit preferences (including folder-picker locations) stay in that
test identity. The embedded suite survives Finder relaunches; Sparkle and startup
login-item reconciliation are disabled in isolated runs. Direct suite launches of the
canonical app are refused before SwiftUI creates the application.
It clears inherited `NIKO_MUSIC_HUB_*` launch overrides, enables dry-run CPR opening,
and checks the PID belonging to that exact binary. A missing window or unavailable
window API fails the check. It stops its own app and removes its isolated settings
and Application Support data on exit. The earlier E2E step still rebuilds and stops
the repository's ordinary `dist/NikoMusicHub.app`; finish work in that development
instance before running the full check.

For fixture UI work, export `NIKO_MUSIC_HUB_SETTINGS_SUITE` with a fresh alphanumeric,
dot, underscore or hyphen name, then use `./script/build_and_run.sh` or source
`script/lib/app_lifecycle.sh` and call `nmh_open_app`. For a direct process launch, call
`nmh_prepare_isolated_app "$NIKO_MUSIC_HUB_SETTINGS_SUITE"` and launch
`"$NMH_ISOLATED_APP_BINARY"`; resolve that exact binary's PID for AX checks.
The helper ad-hoc signs the copy and leaves the canonical source bundle unchanged.
These fixture copies do not prove release signing, permissions, updates or login behavior.

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
| `./script/dev.sh startup` | Build, verify, and close a disposable app; retain startup evidence. |
| `./script/dev.sh logs` | Open the app and stream logs. |
| `./script/dev.sh proof` | Save visible-window screenshots under `dist/`. |
| `./script/dev.sh stop` | Stop any running app instance. |
| `./script/dev.sh clean` | Delete generated build output only. |
| `./script/dev.sh helpers` | Install or update `ffmpeg` and `yt-dlp` through Homebrew. |

## Inspecting startup and runtime errors

```bash
./script/dev.sh startup
```

This is the same as `./script/build_and_run.sh --verify-isolated`. The command prints
its unique `.build/dev-flow/startup.XXXXXX/` evidence directory. Inspect `stdout.log`
for the app's `ConsoleDiagnostics` messages and `stderr.log` for native runtime
messages. `window.txt` records the visible-window result; `accessibility.txt` and
`accessibility-error.log` retain a best-effort, window-only accessibility snapshot.
Missing accessibility content does not pass the strict E2E gate, even when a window
is visible. Empty runtime logs are normal for an uneventful first launch.

`./script/dev.sh logs` streams macOS unified logging, which does not include the
app's stdout-based `ConsoleDiagnostics`. It also launches with normal user settings.
Use the disposable startup command for unattended startup verification. Window
visibility alone does not certify every workflow or guarantee error-free logs.

## Fresh worktree

No package download, helper installation, fixture regeneration, or copied `.build`
directory is needed for a fresh worktree: the synthetic archive fixtures are tracked. Run:

```bash
./script/dev.sh doctor
./script/ci.sh
./script/dev.sh startup
```

The latest `./script/ci.sh` result is the check baseline in the
[architecture map](architecture-map.md#check-baseline-2026-10-25). Error messages emitted by
deliberate failure-injection tests are not test failures; inspect test exit status and assertions.

Verification limits and what resolves them:

| Limit | Required tool, access, or information |
|-------|--------------------------------------|
| Real system-audio capture is excluded from default CI. | A usable CoreAudio capture device, macOS Screen & System Audio Recording permission, a known playing signal, and the excluded recorder tests. |
| Live Dropbox/File Provider and external-drive recovery are not covered by these local gates. | An explicitly disposable provider folder/external volume and provider credentials; run the existing opt-in live Vault tests and hash-check a restore. |
| Placeholder CPRs cannot establish that a restored project opens in Cubase. | A valid disposable Cubase project with its media and an installed Cubase host. |
| Downloader network success and real stem-model execution are not certified here. | A permitted test URL/network access and the installed helper/model assets; use the existing opt-in downloader smoke and a disposable stem input/output. |
| UI probes require a logged-in desktop and relevant macOS permissions. | Accessibility access for the invoking terminal/agent; Screen Recording access for screenshots. Strict UI E2E must pass on that Mac. |

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
