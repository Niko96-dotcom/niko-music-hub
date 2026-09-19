#!/usr/bin/env bash
# Reproducible Output Inbox refresh benchmark (fixture-only, no real data).
#
# Builds AppCore once, then compiles script/performance/output-inbox.swift
# against it and measures refreshAvailability+listItems (baseline, two JSON
# loads) vs loadRefreshedItems (optimized, one JSON load) on 100/1000/10000
# distinct 64-byte files. Optional sizes: ./script/benchmark_output_inbox.sh 100,1000
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release --target AppCore >&2
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p .build/performance-inbox
swiftc -O -I "$BIN_DIR/Modules" script/performance/output-inbox.swift \
  "$BIN_DIR"/AppCore.build/*.o "$BIN_DIR"/NikoMusicCore.build/*.o -lsqlite3 \
  -framework AppKit -framework SwiftUI -framework Combine \
  -o .build/performance-inbox/output-inbox
exec .build/performance-inbox/output-inbox "$@"
