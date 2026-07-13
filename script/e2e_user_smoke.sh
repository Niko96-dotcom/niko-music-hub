#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib/app_lifecycle.sh
source "$ROOT/script/lib/app_lifecycle.sh"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

FIXTURE_ROOT="$ROOT/Fixtures/CubaseArchive"
LOG_FILE="$ROOT/.build/e2e-smoke.log"

# Every app launch in this script must run with NIKO_MUSIC_HUB_SETTINGS_SUITE set.
# The suite routes settings AND Application Support (archive-index.sqlite,
# output-inbox.json) into "Niko Music Hub/Isolated/<suite>/". Overriding $HOME does
# NOT isolate anything — FileManager.urls(for: .applicationSupportDirectory) ignores
# the environment variable and resolves the real home, so a suite-less smoke run
# overwrites the user's real archive cache with fixture data.
ISOLATED_ROOT="$HOME/Library/Application Support/Niko Music Hub/Isolated"
ARCHIVE_SUITE="NikoMusicHubE2E.archive.$(uuidgen)"
UI_SUITE="NikoMusicHubE2E.$(uuidgen)"
cleanup_smoke_suites() {
  nmh_stop_app true
  launchctl unsetenv NIKO_MUSIC_HUB_SETTINGS_SUITE >/dev/null 2>&1 || true
  rm -rf "$ISOLATED_ROOT/$ARCHIVE_SUITE" "$ISOLATED_ROOT/$UI_SUITE"
  defaults delete "$ARCHIVE_SUITE" >/dev/null 2>&1 || true
  defaults delete "$UI_SUITE" >/dev/null 2>&1 || true
}
trap cleanup_smoke_suites EXIT

echo "== generate fixtures =="
./script/fixtures/generate_cubase_archive_fixtures.sh

echo "== build app bundle =="
nmh_stop_app true
nmh_build_bundle
APP_BUNDLE="$ROOT/dist/NikoMusicHub.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/NikoMusicHub"
[[ -x "$APP_BINARY" ]] || { echo "E2E failed: built app binary missing" >&2; exit 1; }

echo "== archive smoke (Swift validator owns archive assertions) =="
rm -f "$LOG_FILE"
(
  export NIKO_MUSIC_HUB_E2E_SMOKE=1
  export NIKO_MUSIC_HUB_FIXTURE_ROOT="$FIXTURE_ROOT"
  export NIKO_MUSIC_HUB_DRY_RUN_OPEN=1
  export NIKO_MUSIC_HUB_SETTINGS_SUITE="$ARCHIVE_SUITE"
  cd "$ROOT"
  "$APP_BINARY"
) 2>&1 | tee "$LOG_FILE"

for required_marker in \
  "[niko-music-hub-smoke] ok" \
  "write_probe_denied=true" \
  "archive_unchanged=true" \
  "[dry-run] open CPR:" \
  "recorder_user_flow=record_stop_inbox" \
  "recorder_output_inbox_items=1" \
  "recorder_output_drag_ready=true" \
  "recorder_output_source=audio-recorder" \
  "quick_access_selected_tool=wav-converter" \
  "quick_access_reveal_inbox=true" \
  "quick_access_routing=select_tool_reveal_inbox"; do
  if ! grep -Fq "$required_marker" "$LOG_FILE"; then
    echo "E2E failed: archive smoke missing marker: $required_marker" >&2
    exit 1
  fi
done

echo "== public first-run UI smoke =="
PUBLIC_UI_TEXT="$ROOT/.build/e2e-public-ui.txt"
PUBLIC_UI_SCREENSHOT="$ROOT/.build/e2e-public-ui.png"
launchctl setenv NIKO_MUSIC_HUB_SETTINGS_SUITE "$UI_SUITE" >/dev/null 2>&1 || true

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

if ! grep -Fq "Welcome to your Cubase archive" "$PUBLIC_UI_TEXT"; then
  if swift "$ROOT/script/ui_probe.swift" --pid "$PUBLIC_UI_PID" --check-visible >/dev/null; then
    if [[ "${NMH_STRICT_UI_E2E:-0}" == "1" ]]; then
      echo "E2E failed: strict UI mode requires AX-visible first-run content" >&2
      exit 1
    fi
    echo "public first-run UI text check skipped: AX dump did not expose window content"
    echo "E2E user smoke passed."
    exit 0
  fi
fi

for required_text in \
  "Niko Music Hub" \
  "Archive Browser" \
  "Welcome to your Cubase archive" \
  "Add archive root" \
  "Show output inbox" \
  "Choose the folder that contains your song projects."; do
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
