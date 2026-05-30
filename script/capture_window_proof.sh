#!/usr/bin/env bash
# Capture dist/window-visible-proof.png once the main window is on screen.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/app_lifecycle.sh
source "$ROOT_DIR/script/lib/app_lifecycle.sh"

OUT="$NMH_DIST_DIR/window-visible-proof.png"

nmh_stop_app true
nmh_build_bundle
nmh_open_app
sleep "$NMH_LAUNCH_WAIT_SEC"

/usr/bin/osascript -e 'tell application "System Events" to tell process "NikoMusicHub" to set frontmost to true' >/dev/null 2>&1 || true
sleep 0.5

CAPTURE_STATUS=0
nmh_window_verify \
  --capture "$OUT" \
  --blank-check || CAPTURE_STATUS=$?
case "$CAPTURE_STATUS" in
  0) ;;
  2)
    echo "capture skipped: AX/window check unavailable" >&2
    exit 2
    ;;
  *)
    echo "capture failed: Niko Music Hub window not found or screenshot invalid" >&2
    exit 1
    ;;
esac

/usr/bin/screencapture -x "$NMH_DIST_DIR/desktop-proof.png"
echo "Saved $OUT and $NMH_DIST_DIR/desktop-proof.png"
