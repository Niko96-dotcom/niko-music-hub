#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release --target NikoMusicCore >&2
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p .build/performance-search
swiftc -O -I "$BIN_DIR/Modules" script/performance/archive-search.swift \
  "$BIN_DIR"/NikoMusicCore.build/*.o -lsqlite3 \
  -o .build/performance-search/archive-search
exec .build/performance-search/archive-search "$@"
