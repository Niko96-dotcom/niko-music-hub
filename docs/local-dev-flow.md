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

The final startup check uses a fresh settings suite and `dist/verification/NikoMusicHub.app`.
It clears inherited `NIKO_MUSIC_HUB_*` launch overrides, enables dry-run CPR opening,
and checks the PID belonging to that exact binary. A missing window or unavailable
window API fails the check. It stops its own app and removes its isolated settings
and Application Support data on exit. The earlier E2E step still rebuilds and stops
the repository's ordinary `dist/NikoMusicHub.app`; finish work in that development
instance before running the full check.

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

## Fresh worktree and verification baseline

No package download, helper installation, fixture regeneration, or copied `.build`
directory was needed for a fresh detached worktree on the verification Mac. The
synthetic archive fixtures are tracked. From a fresh worktree, run:

```bash
./script/dev.sh doctor
./script/ci.sh
./script/dev.sh startup
```

Verified on 2026-09-05 with macOS 26.5.2, Xcode's Swift 6.3.3, and `HEAD` at
`5c9369911eda`:

- The existing dirty working tree passed CI: 1,154 XCTest cases (5 skipped),
  54 Swift Testing cases, core self-test, CLI export, and release/source-script gates.
- A fresh detached `HEAD` worktree passed doctor, clean compilation, and CI.
- Baseline strict E2E passed archive scan, fuzzy search, dry-run latest-CPR open,
  read-only/archive-unchanged checks, synthetic recorder-to-inbox handoff, and
  accessibility-visible first-run UI. The ordinary startup command also passed
  when explicitly given an isolated settings suite.
- A manual UI pass selected `Fixtures/CubaseArchive`, scanned nine songs, searched
  `neon hk`, and displayed Neon Hook's latest CPR and preview. The Open in Cubase
  button was exercised in dry-run mode; the automated smoke provides its log assertion.
- The new startup mode was exercised alongside an existing fixture app: the other
  PID survived, the new window was verified, runtime/AX logs were retained, and the
  new process and settings suite were cleaned up. Lifecycle regression tests cover
  inherited launch overrides, unavailable window APIs, launch failure cleanup,
  and invalid arguments without stopping or building an app.
- The completed `./script/dev.sh check` passed all three stages after these changes.
- A deliberately malformed `output-inbox.json` in a separate disposable suite
  produced the visible “Output Inbox could not be loaded” message and a captured
  `[error] Output Inbox load failed` line in stdout, confirming runtime-error access.

No baseline gate failures were observed. Error messages emitted by deliberate
failure-injection tests are not test failures; inspect test exit status and assertions.

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
