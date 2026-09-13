#!/usr/bin/env bash
# Capture baseline screenshots of every main tool tab + output-inbox states.
# Extended for v1.9 baseline captures (Phase 50): adds stem-separation,
# output-inbox closed/open states, and a size loop. Preserves the existing
# fixture-root + dry-run-open + ui-probe harness and nmh_* lifecycle helpers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/app_lifecycle.sh
source "$ROOT/script/lib/app_lifecycle.sh"

OUT_DIR="${OUT_DIR:-$ROOT/tmp/baseline-captures/v1.9}"
mkdir -p "$OUT_DIR"

export NIKO_MUSIC_HUB_FIXTURE_ROOT="$ROOT/Fixtures/CubaseArchive"
export NIKO_MUSIC_HUB_DRY_RUN_OPEN=1
export NIKO_MUSIC_HUB_DISABLE_ARCHIVE_WATCHER=1

# 7 tool surfaces (stem-separation added for v1.9 baseline coverage).
TOOLS=(
  archive-browser
  bpm-tapper
  wav-converter
  audio-recorder
  downloader
  stem-separation
  settings
)

# Size variants. AppleScript window-resize probe (Phase 50 Task 1) found that
# SwiftUI WindowGroup windows do NOT support 'set bounds' via AppleScript
# (error -10006). Compact-width (~1000x720) captures are deferred to Phase 52.
# Single default size = 9 captures (7 tools + 2 inbox states).
SIZES=("default:1280:820")

capture_tool() {
  local tool="$1" size_label="$2" w="$3" h="$4" wait_sec="${5:-8}"

  # Per-capture suite isolation (research Pitfall 5).
  local suite="nmh-baseline-${tool}-${size_label}"
  export NIKO_MUSIC_HUB_SETTINGS_SUITE="$suite"
  export NIKO_MUSIC_HUB_UI_TOOL="$tool"

  nmh_stop_app true
  nmh_open_app
  sleep "$wait_sec"
  nmh_focus_app
  sleep 0.5

  # AppleScript resize — only for compact sizes (skipped for 'default').
  if [[ "$size_label" != "default" ]]; then
    /usr/bin/osascript -e "tell application \"System Events\" to tell process \"NikoMusicHub\" to set bounds of window 1 to {0, 0, $w, $h}" 2>/dev/null || true
    sleep 1.0
    nmh_focus_app
    sleep 0.5
  fi

  nmh_ui_probe \
    --capture "$OUT_DIR/${tool}-${size_label}.png" \
    --require-nonempty-capture \
    --min-width $((w - 50)) \
    --min-height $((h - 50))
  echo "captured $tool @ $size_label -> $OUT_DIR/${tool}-${size_label}.png"

  # Cleanup suite to prevent preference bleed (research Pitfall 5).
  nmh_forget_settings_suite "$suite"
}

capture_inbox_state() {
  local state="$1" size_label="$2" w="$3" h="$4"
  local suite="nmh-baseline-inbox-${state}-${size_label}"

  # Seed inbox visibility preference (AppShellView.swift:6 key).
  defaults delete "$suite" >/dev/null 2>&1 || true
  defaults write "$suite" "hub.shell.panels.inboxVisible" -bool $([[ "$state" == "open" ]] && echo true || echo false)

  export NIKO_MUSIC_HUB_SETTINGS_SUITE="$suite"
  export NIKO_MUSIC_HUB_UI_TOOL="archive-browser"
  nmh_stop_app true
  nmh_open_app
  sleep 8
  nmh_focus_app
  sleep 0.5

  # AppleScript resize — only for compact sizes (skipped for 'default').
  if [[ "$size_label" != "default" ]]; then
    /usr/bin/osascript -e "tell application \"System Events\" to tell process \"NikoMusicHub\" to set bounds of window 1 to {0, 0, $w, $h}" 2>/dev/null || true
    sleep 1.0
    nmh_focus_app
    sleep 0.5
  fi

  nmh_ui_probe \
    --capture "$OUT_DIR/output-inbox-${state}-${size_label}.png" \
    --require-nonempty-capture \
    --min-width $((w - 50)) \
    --min-height $((h - 50))
  echo "captured output-inbox-${state} @ $size_label -> $OUT_DIR/output-inbox-${state}-${size_label}.png"

  # Cleanup suite.
  nmh_forget_settings_suite "$suite"
}

nmh_build_bundle

for size_tuple in "${SIZES[@]}"; do
  IFS=':' read -r label w h <<< "$size_tuple"
  for tool in "${TOOLS[@]}"; do
    if [[ "$tool" == "archive-browser" ]]; then
      capture_tool "$tool" "$label" "$w" "$h" 22
    else
      capture_tool "$tool" "$label" "$w" "$h" 8
    fi
  done
  capture_inbox_state closed "$label" "$w" "$h"
  capture_inbox_state open   "$label" "$w" "$h"
done

nmh_stop_app true
echo "UI review captures in $OUT_DIR"
