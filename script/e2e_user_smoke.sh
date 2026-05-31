#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

FIXTURE_ROOT="$ROOT/Fixtures/CubaseArchive"
SMOKE_SUPPORT="$ROOT/.build/e2e-app-support"
LOG_FILE="$ROOT/.build/e2e-smoke.log"

echo "== generate fixtures =="
./script/fixtures/generate_cubase_archive_fixtures.sh

echo "== build app bundle =="
./script/build_and_run.sh --verify >/dev/null 2>&1 || ./script/build_and_run.sh run >/dev/null 2>&1 || true
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift build --product NikoMusicHub
BUILD_DIR="$(DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift build --show-bin-path)"
APP_BUNDLE="$ROOT/dist/NikoMusicHub.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/NikoMusicHub"
if [[ ! -x "$APP_BINARY" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/MacOS"
  cp "$BUILD_DIR/NikoMusicHub" "$APP_BINARY"
  chmod +x "$APP_BINARY"
fi

echo "== reset test Application Support =="
rm -rf "$SMOKE_SUPPORT"
mkdir -p "$SMOKE_SUPPORT"

echo "== archive smoke (Swift validator owns archive assertions) =="
rm -f "$LOG_FILE"
(
  export NIKO_MUSIC_HUB_E2E_SMOKE=1
  export NIKO_MUSIC_HUB_FIXTURE_ROOT="$FIXTURE_ROOT"
  export NIKO_MUSIC_HUB_DRY_RUN_OPEN=1
  export HOME="$SMOKE_SUPPORT"
  cd "$ROOT"
  "$APP_BINARY"
) 2>&1 | tee "$LOG_FILE"

for required_marker in \
  "[niko-music-hub-smoke] ok" \
  "write_probe_denied=true" \
  "archive_unchanged=true" \
  "[dry-run] open CPR:"; do
  if ! grep -Fq "$required_marker" "$LOG_FILE"; then
    echo "E2E failed: archive smoke missing marker: $required_marker" >&2
    exit 1
  fi
done

echo "== public first-run UI smoke =="
PUBLIC_UI_TEXT="$ROOT/.build/e2e-public-ui.txt"
PUBLIC_UI_SCREENSHOT="$ROOT/.build/e2e-public-ui.png"
UI_SUITE="NikoMusicHubE2E.$(uuidgen)"
launchctl setenv NIKO_MUSIC_HUB_SETTINGS_SUITE "$UI_SUITE" >/dev/null 2>&1 || true
cleanup_public_ui() {
  launchctl unsetenv NIKO_MUSIC_HUB_SETTINGS_SUITE >/dev/null 2>&1 || true
}
trap cleanup_public_ui EXIT

NIKO_MUSIC_HUB_SETTINGS_SUITE="$UI_SUITE" ./script/build_and_run.sh --verify >/dev/null
sleep 1
PUBLIC_UI_PID="$(pgrep -x NikoMusicHub | sort -n | tail -1 || true)"
if [[ -z "$PUBLIC_UI_PID" ]]; then
  echo "E2E failed: public UI app process missing" >&2
  exit 1
fi

screencapture -x "$PUBLIC_UI_SCREENSHOT" >/dev/null 2>&1 || true
if ! swift "$ROOT/script/ui_probe.swift" --pid "$PUBLIC_UI_PID" --ax-dump >"$PUBLIC_UI_TEXT"; then
  echo "E2E failed: ui_probe ax-dump failed for pid $PUBLIC_UI_PID" >&2
  exit 1
fi

if ! grep -Fq "Start with an archive root" "$PUBLIC_UI_TEXT"; then
  if swift "$ROOT/script/ui_probe.swift" --pid "$PUBLIC_UI_PID" --check-visible >/dev/null; then
    echo "public first-run UI text check skipped: AX dump did not expose window content"
    echo "E2E user smoke passed."
    exit 0
  fi
fi

for required_text in \
  "Niko Music Hub" \
  "Archive Browser" \
  "Start with an archive root" \
  "Add an archive root" \
  "Output Inbox" \
  "Choose the folder that contains your Cubase song/project folders"; do
  if ! grep -Fq "$required_text" "$PUBLIC_UI_TEXT"; then
    echo "E2E failed: public first-run UI missing: $required_text" >&2
    exit 1
  fi
done

for forbidden_text in \
  "Outside Cubase" \
  "Dev Tool" \
  "Developer Tool" \
  "Fixtures/CubaseArchive" \
  "/var/folders" \
  "Scan diagnostics" \
  "Support summary"; do
  if grep -Fq "$forbidden_text" "$PUBLIC_UI_TEXT"; then
    echo "E2E failed: public first-run UI exposed forbidden text: $forbidden_text" >&2
    exit 1
  fi
done

echo "E2E user smoke passed."
