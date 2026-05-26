#!/usr/bin/env bash
# Non-interactive prerequisite check for macOS local development.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label"
    failures=$((failures + 1))
  fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This project builds on macOS only (found: $(uname -s))."
  echo "You can still edit source here; run ./script/ci.sh on a Mac before merging."
  exit 0
fi

echo "Niko Music Hub — macOS setup check"
echo "Repo: $ROOT_DIR"
echo

check "git" git --version
check "swift" swift --version
check "xcode-select" xcode-select -p

if command -v ffmpeg >/dev/null 2>&1; then
  printf 'ok   ffmpeg (optional, WAV Converter)\n'
else
  printf 'skip ffmpeg (optional)\n'
fi

if command -v yt-dlp >/dev/null 2>&1; then
  printf 'ok   yt-dlp (optional, Downloader)\n'
else
  printf 'skip yt-dlp (optional)\n'
fi

echo
if [[ "$failures" -gt 0 ]]; then
  echo "$failures required check(s) failed. See docs/local-development.md"
  exit 1
fi

echo "Ready. Next: ./script/ci.sh && ./script/build_and_run.sh"
exit 0
