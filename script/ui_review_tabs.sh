#!/usr/bin/env bash
# Capture one window screenshot per main tool tab (no Accessibility / AppleScript required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/app_lifecycle.sh
source "$ROOT/script/lib/app_lifecycle.sh"

OUT_DIR="${OUT_DIR:-$ROOT/.ai/ui-review-tabs}"
mkdir -p "$OUT_DIR"

export NIKO_MUSIC_HUB_FIXTURE_ROOT="$ROOT/Fixtures/CubaseArchive"
export NIKO_MUSIC_HUB_DRY_RUN_OPEN=1
export NIKO_MUSIC_HUB_DISABLE_ARCHIVE_WATCHER=1

TOOLS=(
  archive-browser
  bpm-tapper
  wav-converter
  audio-recorder
  downloader
  settings
)

capture_tool() {
  local tool="$1"
  local wait_sec="${2:-6}"

  export NIKO_MUSIC_HUB_UI_TOOL="$tool"
  nmh_stop_app true
  nmh_open_app
  sleep "$wait_sec"
  nmh_focus_app
  sleep 0.5

  nmh_ui_probe \
    --capture "$OUT_DIR/$tool.png" \
    --require-nonempty-capture
  echo "captured $tool -> $OUT_DIR/$tool.png"
}

nmh_build_bundle

for tool in "${TOOLS[@]}"; do
  if [[ "$tool" == "archive-browser" ]]; then
    capture_tool "$tool" 22
  else
    capture_tool "$tool" 8
  fi
done

nmh_stop_app true
echo "UI review captures in $OUT_DIR"
