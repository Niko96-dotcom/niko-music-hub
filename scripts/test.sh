#!/usr/bin/env bash
set -euo pipefail

# SwiftPM test targets need XCTest from full Xcode, not Command Line Tools alone.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "$(dirname "$0")/.."
swift test "$@"
