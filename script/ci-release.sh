#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "== release configuration build =="
swift build -c release --product NikoMusicHub

echo "== release configuration tests =="
swift test -c release \
  --skip CoreAudioTapAdapterTests \
  --skip 'RecorderIntegrationTests/testMaxDurationAutoStop' \
  --skip 'RecorderIntegrationTests/testOutputFileHasCorrectFormat' \
  --skip 'RecorderIntegrationTests/testRecordingCapturesRealSystemAudio' \
  --skip 'RecorderIntegrationTests/testRecordingProducesOutputInboxItem'
