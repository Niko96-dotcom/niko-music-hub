#!/usr/bin/env bash
# Read-only full-scan timing of one archive root with 1, 2, 4 and 8 folder workers
# (script/performance/scan-workers.swift). Run it on the real archive disk before changing
# ScanWorkerBudget.volumeLimit; the scanner never writes to the archive.
#   script/benchmark_scan_workers.sh <archive-root> [--runs N]
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release --target NikoMusicCore -Xswiftc -enable-testing >&2
BIN_DIR="$(swift build -c release --show-bin-path)"
OBJECTS=("$BIN_DIR"/NikoMusicCore.o)
[[ -f "${OBJECTS[0]}" ]] || OBJECTS=("$BIN_DIR"/NikoMusicCore.build/*.o)
mkdir -p .build/performance-scan
swiftc -O -parse-as-library -I "$BIN_DIR/Modules" -I "$BIN_DIR" \
  script/performance/scan-workers.swift "${OBJECTS[@]}" -lsqlite3 \
  -o .build/performance-scan/scan-workers
exec .build/performance-scan/scan-workers "$@"
