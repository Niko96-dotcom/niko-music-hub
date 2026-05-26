# Local development — Niko Music Hub

Niko Music Hub is a **native macOS** SwiftPM app. Build, run, and tests require a Mac with Xcode (or Xcode Command Line Tools + a full Swift toolchain). Linux and cloud sandboxes are fine for editing docs and Swift source, but **local gates must pass on your Mac** before you merge.

## Canonical Mac folder

```text
/Users/niko/Documents/Niko-Music-Hub
```

Open this folder in Cursor for day-to-day work on your Mac.

## One-command install (Mac)

From any machine with the repo (or after a shallow clone), or paste the script path after you have `main` once:

```bash
# If you do not have the repo yet — download bootstrap from GitHub main:
curl -fsSL https://raw.githubusercontent.com/Niko96-dotcom/niko-music-hub/main/script/bootstrap_documents_mac.sh \
  -o /tmp/bootstrap_documents_mac.sh
chmod +x /tmp/bootstrap_documents_mac.sh
/tmp/bootstrap_documents_mac.sh
```

If you already have a checkout:

```bash
cd /path/to/niko-music-hub
./script/bootstrap_documents_mac.sh
```

Optional: install a specific branch (e.g. a Cursor agent branch):

```bash
./script/bootstrap_documents_mac.sh cursor/local-development-setup-2a89
```

The bootstrap script will:

1. Clone or update `/Users/niko/Documents/Niko-Music-Hub`
2. Run `setup_mac_check.sh`
3. Regenerate fixtures
4. Run `./script/ci.sh`
5. `swift build` and verify the `.app` launches

Override the target path:

```bash
export NIKO_MUSIC_HUB_REPO=/other/path
./script/bootstrap_documents_mac.sh
```

### Manual clone (same folder)

```bash
git clone https://github.com/Niko96-dotcom/niko-music-hub.git /Users/niko/Documents/Niko-Music-Hub
cd /Users/niko/Documents/Niko-Music-Hub
./script/setup_mac_check.sh
./script/ci.sh
```

SSH:

```bash
git clone git@github.com:Niko96-dotcom/niko-music-hub.git /Users/niko/Documents/Niko-Music-Hub
```

### Prerequisites

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

### Open in Cursor

```bash
cursor /Users/niko/Documents/Niko-Music-Hub
```

For UI debugging:

```bash
cd /Users/niko/Documents/Niko-Music-Hub
./script/build_and_run.sh
```

Output: `dist/NikoMusicHub.app` (display name **Niko Music Hub**).

## Daily workflow

```bash
cd /Users/niko/Documents/Niko-Music-Hub
swift build
./script/build_and_run.sh
./script/ci.sh
./script/e2e_user_smoke.sh
```

`ci.sh` skips five CoreAudio recorder tests that need a working system-audio capture device on the host.

### Fixtures and core CLI

```bash
./script/fixtures/generate_cubase_archive_fixtures.sh
swift run NikoMusicCoreSelfTest
```

### Real Cubase archive (read-only)

In the app: set archive root in Archive Browser settings.

CLI:

```bash
swift run NikoMusicCoreSelfTest --real-root "/path/to/your/cubase/archive" --read-only
```

Automation dry-run:

```bash
export NIKO_MUSIC_HUB_DRY_RUN_OPEN=1
```

See `docs/user-e2e.md` for E2E env vars.

## Working with Cursor Cloud Agent

| Where | Good for |
|-------|----------|
| **Cloud agent** (GitHub) | Multi-file edits, docs, planning, PRs |
| **`/Users/niko/Documents/Niko-Music-Hub`** | `swift test`, app UI, CoreAudio, real archive |

Typical loop:

1. Agent pushes a branch to `origin`.
2. On the Mac: `cd /Users/niko/Documents/Niko-Music-Hub && git fetch && git checkout <branch> && git pull`.
3. `./script/ci.sh` and `./script/e2e_user_smoke.sh`.

App state: `~/Library/Application Support/Niko Music Hub/`

Build artifacts (gitignored): `.build/`, `dist/`, `DerivedData/`.

## Reference only (do not edit in place)

- MacBook seed: `/Users/niko/Documents/OutSideCubaseHub`
- Old dev path (superseded): `/Users/nikolaymohr/src/niko-music-hub`

Product source of truth is **GitHub** and your **Documents** checkout above.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `swift: command not found` | Install Xcode or `xcode-select --install` |
| Wrong SDK / Swift version | `xcode-select -p`, open project in Xcode once |
| App does not open | `./script/build_and_run.sh --debug` |
| Recorder tests fail locally | System Settings → Privacy → Screen & System Audio Recording |
| E2E fails after fixture edits | Regenerate fixtures, re-run smoke |
| Folder exists but is not git | Move aside `Niko-Music-Hub`, re-run bootstrap |

More: `AGENTS.md`, `docs/architecture.md`, `README.md`.
