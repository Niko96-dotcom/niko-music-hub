#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-/Applications/NikoMusicHub.app}"
APP_BINARY="$APP_PATH/Contents/MacOS/NikoMusicHub"
[[ -x "$APP_BINARY" ]] || { echo "installed app binary missing: $APP_BINARY" >&2; exit 1; }

SUITE="NikoMusicHub.BookmarkProof.$(uuidgen)"
PROOF_ROOT="$(mktemp -d /tmp/niko-music-hub-bookmark-proof.XXXXXX)"
ACTIVE_ROOT="$PROOF_ROOT/Active Projects"
ARCHIVE_ROOT="$PROOF_ROOT/Archive Projects"
SEED_LOG="$PROOF_ROOT/seed.log"
VERIFY_LOG="$PROOF_ROOT/verify.log"
ISOLATED_SUPPORT="$HOME/Library/Application Support/Niko Music Hub/Isolated/$SUITE"
mkdir -p "$ACTIVE_ROOT" "$ARCHIVE_ROOT"

cleanup() {
  # Same reason as nmh_forget_settings_suite: `defaults delete` leaves the plist behind.
  defaults delete "$SUITE" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$SUITE.plist"
  rm -rf "$ISOLATED_SUPPORT" "$PROOF_ROOT"
}
trap cleanup EXIT

run_proof_process() {
  local mode="$1"
  local log="$2"
  env \
    NIKO_MUSIC_HUB_SETTINGS_SUITE="$SUITE" \
    NIKO_MUSIC_HUB_DISABLE_ARCHIVE_WATCHER=1 \
    NIKO_MUSIC_HUB_BOOKMARK_PROOF_MODE="$mode" \
    NIKO_MUSIC_HUB_BOOKMARK_PROOF_ACTIVE_ROOT="$ACTIVE_ROOT" \
    NIKO_MUSIC_HUB_BOOKMARK_PROOF_ARCHIVE_ROOT="$ARCHIVE_ROOT" \
    "$APP_BINARY" >"$log" 2>&1
}

run_proof_process seed "$SEED_LOG"
grep -Fq '[bookmark-relaunch-proof] seeded' "$SEED_LOG" || {
  echo "bookmark seed process did not confirm persistence" >&2
  exit 1
}

# The seed process has exited. A new app process must reconstruct both selections
# solely from the isolated persisted settings and their security-scoped bookmarks.
run_proof_process verify "$VERIFY_LOG"
grep -Fq '[bookmark-relaunch-proof] verified' "$VERIFY_LOG" || {
  echo "bookmark relaunch process did not confirm resolution" >&2
  exit 1
}

echo "bookmark relaunch proof ok: two app processes, isolated suite, synthetic folders"
