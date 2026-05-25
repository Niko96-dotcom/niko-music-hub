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

echo "== archive smoke (CLI hook, not pgrep-only) =="
rm -f "$LOG_FILE"
(
  export NIKO_MUSIC_HUB_E2E_SMOKE=1
  export NIKO_MUSIC_HUB_FIXTURE_ROOT="$FIXTURE_ROOT"
  export NIKO_MUSIC_HUB_DRY_RUN_OPEN=1
  export HOME="$SMOKE_SUPPORT"
  cd "$ROOT"
  "$APP_BINARY"
) 2>&1 | tee "$LOG_FILE"

if ! grep -q "user_flow=scan_search_open" "$LOG_FILE"; then
  echo "E2E failed: view-model user flow marker missing" >&2
  exit 1
fi

if ! grep -q "neon_hook=Neon Hook" "$LOG_FILE"; then
  echo "E2E failed: Neon Hook not found in smoke output" >&2
  exit 1
fi

if ! grep -q "search_query=neon hk" "$LOG_FILE"; then
  echo "E2E failed: fuzzy search query marker missing" >&2
  exit 1
fi

if ! grep -q "search_matches=1" "$LOG_FILE"; then
  echo "E2E failed: Neon Hook search did not narrow to one song" >&2
  exit 1
fi

if ! grep -q "search_match_summary=.*neon" "$LOG_FILE"; then
  echo "E2E failed: search match explainability missing neon token" >&2
  exit 1
fi

if ! grep -q "search_match_summary=.*hk" "$LOG_FILE"; then
  echo "E2E failed: search match explainability missing hk token" >&2
  exit 1
fi

if ! grep -q "diagnostics_songs=" "$LOG_FILE"; then
  echo "E2E failed: scan diagnostics song count missing" >&2
  exit 1
fi

if ! grep -q "diagnostics_skipped=" "$LOG_FILE"; then
  echo "E2E failed: scan diagnostics skipped count missing" >&2
  exit 1
fi

if ! grep -q "Neon Hook/Neon Hook.cpr" "$LOG_FILE"; then
  echo "E2E failed: expected dry-run CPR path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "\[dry-run\] open CPR:" "$LOG_FILE"; then
  echo "E2E failed: dry-run open log line missing" >&2
  exit 1
fi

if ! grep -q "write_probe_denied=true" "$LOG_FILE"; then
  echo "E2E failed: read-only write probe not reported" >&2
  exit 1
fi

if ! grep -q "archive_unchanged=true" "$LOG_FILE"; then
  echo "E2E failed: fixture archive tree changed during smoke" >&2
  exit 1
fi

if ! grep -q "\[niko-music-hub-smoke\] ok" "$LOG_FILE"; then
  echo "E2E failed: smoke did not report ok" >&2
  exit 1
fi

echo "E2E user smoke passed."
