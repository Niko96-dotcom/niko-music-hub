#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "${NIKO_MUSIC_HUB_LIVE_DOWNLOADER:-}" != "1" ]]; then
  echo "downloader live smoke skipped (set NIKO_MUSIC_HUB_LIVE_DOWNLOADER=1 to run)"
  exit 0
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

resolve_binary() {
  local name="$1"
  for candidate in \
    "/opt/homebrew/bin/$name" \
    "/usr/local/bin/$name" \
    "/opt/local/bin/$name"; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

YT_DLP="$(resolve_binary yt-dlp)" || {
  echo "downloader live smoke failed: yt-dlp not found" >&2
  exit 1
}
FFPROBE="$(resolve_binary ffprobe)" || {
  echo "downloader live smoke failed: ffprobe not found" >&2
  exit 1
}
FFMPEG_DIR="$(dirname "$(resolve_binary ffmpeg)")"

OUTPUT_DIR="$ROOT/.build/downloader-live-smoke-$(date +%Y%m%d%H%M%S)"
LOG_FILE="$OUTPUT_DIR/smoke.log"
mkdir -p "$OUTPUT_DIR"
trap 'rm -rf "$OUTPUT_DIR"' EXIT

SUCCESS_URL="https://www.youtube.com/watch?v=BaW_jenozKc"
FAIL_URL="https://www.youtube.com/watch?v=invalidvideo123456789"

echo "== helper path smoke (stripped PATH + --ffmpeg-location) =="
PATH=/usr/bin:/bin \
  "$YT_DLP" \
  --simulate \
  --no-playlist \
  --ffmpeg-location "$FFMPEG_DIR" \
  --print "%(title)s" \
  "$SUCCESS_URL" >"$OUTPUT_DIR/simulate-stripped.log" 2>&1

echo "== live download (audio-only, beyond 18s happy path) =="
PATH=/usr/bin:/bin \
  "$YT_DLP" \
  --newline \
  --no-playlist \
  --no-overwrites \
  --progress \
  --progress-template "NIKO_PROGRESS:%(progress)s" \
  --ffmpeg-location "$FFMPEG_DIR" \
  -f "bestaudio[ext=m4a]/bestaudio" \
  -o "$OUTPUT_DIR/%(title)s [%(id)s].%(ext)s" \
  "$SUCCESS_URL" 2>&1 | tee "$LOG_FILE"

if ! grep -Fq "NIKO_PROGRESS:" "$LOG_FILE"; then
  echo "downloader live smoke failed: missing NIKO_PROGRESS markers" >&2
  exit 1
fi

DOWNLOADED_FILE="$(find "$OUTPUT_DIR" -type f \( -name '*.m4a' -o -name '*.mp3' -o -name '*.webm' -o -name '*.mp4' \) | head -1 || true)"
if [[ -z "$DOWNLOADED_FILE" ]]; then
  echo "downloader live smoke failed: no output media file" >&2
  exit 1
fi

DURATION="$("$FFPROBE" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$DOWNLOADED_FILE" | tr -d '[:space:]')"
if awk "BEGIN { exit !($DURATION > 18.0) }"; then
  :
else
  echo "downloader live smoke failed: duration ${DURATION}s is not beyond 18s" >&2
  exit 1
fi

echo "== failure path =="
set +e
PATH=/usr/bin:/bin \
  "$YT_DLP" \
  --simulate \
  --no-playlist \
  "$FAIL_URL" >"$OUTPUT_DIR/failure.log" 2>&1
FAIL_EXIT=$?
set -e
if [[ "$FAIL_EXIT" -eq 0 ]]; then
  echo "downloader live smoke failed: invalid URL unexpectedly succeeded" >&2
  exit 1
fi

echo "downloader live smoke passed (duration=${DURATION}s, file=$(basename "$DOWNLOADED_FILE"))"
