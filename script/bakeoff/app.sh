#!/usr/bin/env bash
# Performance bake-off: the only supported way to run the app on synthetic data.
#
#   script/bakeoff/app.sh prepare <1k|10k>            data + isolated suite (idempotent)
#   script/bakeoff/app.sh launch  <1k|10k> [debug|release]   prints PID=...
#   script/bakeoff/app.sh stop    <1k|10k>
#   script/bakeoff/app.sh reset   <1k|10k>            suite + database to the Trash (next launch = first scan)
#   script/bakeoff/app.sh paths   <1k|10k>
#
# <name> comes from $BAKEOFF_NAME or the BAKEOFF_NAME file at the checkout root.
# Every launch uses its own settings suite (NikoMusicHubBakeoff.<name>.<size>),
# which also isolates the SQLite folder, the synthetic archive under
# bakeoff-data/<size>/ as its only scan root, an output folder inside
# bakeoff-data/, and dry-run project opening. Real settings, real archives and
# the real Inbox are never touched. The archive is a normal scan root (not the
# fixture root), so launch takes the same path as a real archive: cached index,
# then background rescan and archive watcher.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
usage() { sed -n 2,10p "$0" | sed 's/^# \{0,1\}//'; exit 64; }
die() { echo "bakeoff: $*" >&2; exit 1; }

command="${1:-}"; size="${2:-}"
[[ -n "$command" && -n "$size" ]] || usage
name="${BAKEOFF_NAME:-}"
[[ -n "$name" || ! -f "$ROOT/BAKEOFF_NAME" ]] || name="$(tr -d '[:space:]' <"$ROOT/BAKEOFF_NAME")"
[[ -n "$name" ]] || die "set BAKEOFF_NAME or write it to $ROOT/BAKEOFF_NAME"
[[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || die "name must be letters, digits, - or _"
case "$size" in 1k) songs=1000 ;; 10k) songs=10000 ;; *) die "size must be 1k or 10k" ;; esac

DATA="$ROOT/bakeoff-data/$size"
ARCHIVE="$DATA/CubaseArchive"
OUTPUT="$DATA/output-$name"
SUITE="NikoMusicHubBakeoff.$name.$size"
SUPPORT="$HOME/Library/Application Support/Niko Music Hub/Isolated/$SUITE"
DATABASE="$SUPPORT/archive-index.sqlite"
ROOT_ID="B0BA0FF0-0000-4000-8000-$(printf '%012d' "$songs")"

seed_settings() {
  local json
  json="$(/usr/bin/python3 -I - "$ARCHIVE" "$OUTPUT" "$ROOT_ID" <<'PY'
import json, pathlib, sys
archive, output, root_id = sys.argv[1:4]
print(json.dumps({
    "outputFolder": {"url": pathlib.Path(output).as_uri() + "/"},
    "musicRoots": [{
        "id": root_id, "role": "scanOnly", "displayName": "Synthetic Archive",
        "pathFallback": archive, "isEnabled": True,
    }],
    "archiveOnboardingCompleted": True,
}))
PY
)"
  defaults write "$SUITE" nikoMusicHub.settings -data "$(printf '%s' "$json" | xxd -p | tr -d '\n')"
}

build_seed_tool() {
  local bin_dir
  # shellcheck source=../lib/app_lifecycle.sh
  source "$ROOT/script/lib/app_lifecycle.sh"
  (cd "$ROOT" && nmh_swift build -c release --target NikoMusicCore >&2)
  bin_dir="$(cd "$ROOT" && nmh_swift build -c release --show-bin-path)"
  mkdir -p "$ROOT/.build/bakeoff"
  # Two SwiftPM layouts: Modules/ + NikoMusicCore.build/*.o, or one module and one object.
  local -a objects=("$bin_dir"/NikoMusicCore.o)
  [[ -f "${objects[0]}" ]] || objects=("$bin_dir"/NikoMusicCore.build/*.o)
  xcrun swiftc -O -parse-as-library -I "$bin_dir/Modules" -I "$bin_dir" \
    "$ROOT/script/bakeoff/seed-history.swift" "${objects[@]}" -lsqlite3 \
    -o "$ROOT/.build/bakeoff/seed-history"
}

cmd_prepare() {
  if [[ ! -d "$ARCHIVE" ]]; then
    mkdir -p "$(dirname "$DATA")"
    /usr/bin/python3 -I "$ROOT/script/bakeoff/generate_synthetic_archive.py" --songs "$songs" --out "$DATA"
  fi
  mkdir -p "$OUTPUT"
  seed_settings
  if [[ ! -f "$DATABASE" ]]; then
    build_seed_tool
    "$ROOT/.build/bakeoff/seed-history" --archive "$ARCHIVE" --database "$DATABASE"
  fi
  cmd_paths
}

running_pids() {
  /usr/bin/pgrep -f "dist/bakeoff/$name-" || true
}

cmd_launch() {
  local config="${1:-debug}" dist bundle pid deadline
  case "$config" in debug|release) ;; *) die "configuration must be debug or release" ;; esac
  [[ -f "$DATABASE" ]] || die "run: script/bakeoff/app.sh prepare $size"
  [[ -z "$(running_pids)" ]] || die "a $name build is already running; run: script/bakeoff/app.sh stop $size"
  dist="$ROOT/dist/bakeoff/$name-$config"
  export NMH_BUILD_CONFIGURATION="$config" NMH_DIST_DIR="$dist"
  # shellcheck source=../lib/app_lifecycle.sh
  source "$ROOT/script/lib/app_lifecycle.sh"
  nmh_build_bundle >"$ROOT/.build/bakeoff-build-$name-$config.log" 2>&1 \
    || { tail -n 30 "$ROOT/.build/bakeoff-build-$name-$config.log" >&2; die "build failed"; }
  nmh_prepare_isolated_app "$SUITE"
  bundle="$NMH_ISOLATED_APP_BUNDLE"
  mkdir -p "$DATA/logs"
  /usr/bin/open -n -g \
    --stdout "$DATA/logs/$name-stdout.log" --stderr "$DATA/logs/$name-stderr.log" \
    --env "NIKO_MUSIC_HUB_SETTINGS_SUITE=$SUITE" \
    --env "NIKO_MUSIC_HUB_DRY_RUN_OPEN=1" \
    --env "NSUnbufferedIO=YES" \
    "$bundle"
  deadline=$((SECONDS + 30))
  while ((SECONDS < deadline)); do
    pid="$(nmh_running_app_binary_pids "$bundle/Contents/MacOS/NikoMusicHub" | head -n 1)"
    [[ -n "$pid" ]] && { echo "PID=$pid SUITE=$SUITE BUNDLE=$bundle"; return 0; }
    sleep 0.2
  done
  die "app did not start; see $DATA/logs/$name-stderr.log"
}

cmd_stop() {
  local pid
  for pid in $(running_pids); do kill -TERM "$pid" 2>/dev/null || true; done
}

cmd_reset() {
  cmd_stop
  [[ -d "$SUPPORT" ]] && /usr/bin/trash "$SUPPORT"
  defaults delete "$SUITE" >/dev/null 2>&1 || true
  echo "reset $SUITE (archive kept: $ARCHIVE)"
}

cmd_paths() {
  printf 'SUITE=%s\nARCHIVE=%s\nDATABASE=%s\nOUTPUT=%s\n' "$SUITE" "$ARCHIVE" "$DATABASE" "$OUTPUT"
}

shift 2
case "$command" in
  prepare) cmd_prepare ;;
  launch) cmd_launch "$@" ;;
  stop) cmd_stop ;;
  reset) cmd_reset ;;
  paths) cmd_paths ;;
  *) usage ;;
esac
