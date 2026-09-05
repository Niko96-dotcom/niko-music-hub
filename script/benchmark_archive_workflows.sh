#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release --target NikoMusicCore >&2
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p .build/performance-search
swiftc -O -parse-as-library -I "$BIN_DIR/Modules" \
  script/performance/archive-workflows.swift \
  Sources/FeatureArchiveBrowser/ArchiveBoardProjection.swift \
  Sources/FeatureArchiveBrowser/ArchiveAnalyticsProjection.swift \
  "$BIN_DIR"/NikoMusicCore.build/*.o -lsqlite3 \
  -o .build/performance-search/archive-workflows
exec .build/performance-search/archive-workflows "$@"
