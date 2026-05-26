# Local development — Niko Music Hub

Niko Music Hub is a **native macOS** SwiftPM app. Build, run, and tests require a Mac with Xcode (or Xcode Command Line Tools + a full Swift toolchain). Linux and cloud sandboxes are fine for editing docs and Swift source, but **local gates must pass on your Mac** before you merge.

## One-time setup on your Mac

### 1. Clone the repo

Recommended working copy (matches project docs):

```bash
mkdir -p ~/src
git clone https://github.com/Niko96-dotcom/niko-music-hub.git ~/src/niko-music-hub
cd ~/src/niko-music-hub
```

Use SSH if you prefer:

```bash
git clone git@github.com:Niko96-dotcom/niko-music-hub.git ~/src/niko-music-hub
```

### 2. Prerequisites

| Requirement | Why |
|-------------|-----|
| macOS **14.2+** | `Package.swift` platform minimum |
| **Xcode** (recent) or CLT + Swift 6 | `swift build`, `swift test`, app bundle script |
| **Git** | Branch workflow with GitHub / Cursor Cloud |

Optional (only when using those tools in the app):

| Tool | Feature |
|------|---------|
| `ffmpeg` | WAV Converter (FFmpeg path) |
| `yt-dlp` | Downloader |
| System audio capture permission | Audio Recorder (macOS Privacy) |

Check toolchain quickly:

```bash
./script/setup_mac_check.sh
```

### 3. Open in Cursor (or Xcode)

```bash
cursor ~/src/niko-music-hub
```

For UI debugging, build and launch the `.app`:

```bash
./script/build_and_run.sh
```

Output: `dist/NikoMusicHub.app` (display name **Niko Music Hub**).

## Daily workflow

### Build and run

```bash
swift build
./script/build_and_run.sh          # opens dist/NikoMusicHub.app
./script/build_and_run.sh --verify # launch + confirm process running
```

### Tests and gates (run before push)

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```

`ci.sh` skips five CoreAudio recorder tests that need a working system-audio capture device on the host. They remain in the suite; they are just not a reliable always-on gate.

### Fixtures and core CLI

```bash
./script/fixtures/generate_cubase_archive_fixtures.sh
swift run NikoMusicCoreSelfTest
```

### Point the archive browser at your real Cubase tree (read-only)

In the app: choose your archive root in Archive Browser settings.

CLI smoke (no writes under the root):

```bash
swift run NikoMusicCoreSelfTest --real-root "/path/to/your/cubase/archive" --read-only
```

Automation dry-run (no Cubase launch):

```bash
export NIKO_MUSIC_HUB_DRY_RUN_OPEN=1
```

See `docs/user-e2e.md` for fixture and E2E env vars.

## Working with Cursor Cloud Agent

| Where | Good for |
|-------|----------|
| **Cloud agent** (this repo on GitHub) | Multi-file edits, docs, planning, PRs |
| **Mac checkout** | `swift test`, app UI, CoreAudio, real archive smoke |

Typical loop:

1. Agent (or you) pushes a branch to `origin`.
2. On the Mac: `git fetch origin && git checkout <branch> && git pull`.
3. Run `./script/ci.sh` and `./script/e2e_user_smoke.sh`.
4. Review in Cursor locally; push fixes from the Mac if needed.

App state and inbox data live under:

```text
~/Library/Application Support/Niko Music Hub/
```

Build artifacts stay in-repo but are gitignored: `.build/`, `dist/`, `DerivedData/`.

## Syncing from the old MacBook seed (reference only)

The product was seeded from **OutsideCubaseHub** on the MacBook. That folder is **read-only reference** — do not edit it in place during hub work. If you ever need to re-copy reference files, use rsync into this repo only (see `docs/niko-music-hub-composer-execution-plan.md` bootstrap section).

Current canonical product code is **this GitHub repo**, not `/Users/niko/Documents/OutSideCubaseHub`.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `swift: command not found` | Install Xcode or `xcode-select --install` |
| Wrong SDK / Swift version | `xcode-select -p`, open project in Xcode once |
| App does not open | `./script/build_and_run.sh --debug` |
| Recorder tests fail locally | System Settings → Privacy → Screen & System Audio Recording |
| E2E fails after fixture edits | `./script/fixtures/generate_cubase_archive_fixtures.sh` then re-run smoke |

More architecture and agent rules: `AGENTS.md`, `docs/architecture.md`, `README.md`.
