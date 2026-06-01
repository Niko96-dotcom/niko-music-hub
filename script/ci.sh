#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "== swift build =="
swift build

echo "== swift test (local deterministic gate) =="
# Some Macs report system-audio permission as authorized but cannot reliably start a
# CoreAudio aggregate capture device in automation. Keep these real-device tests out
# of the default gate; run them manually when checking recorder hardware.
swift test \
  --skip CoreAudioTapAdapterTests \
  --skip 'RecorderIntegrationTests/testMaxDurationAutoStop' \
  --skip 'RecorderIntegrationTests/testOutputFileHasCorrectFormat' \
  --skip 'RecorderIntegrationTests/testRecordingCapturesRealSystemAudio' \
  --skip 'RecorderIntegrationTests/testRecordingProducesOutputInboxItem'

if swift package describe --type json | /usr/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); print(any(t.get("name") == "NikoMusicCoreSelfTest" for t in data.get("targets", [])))' | grep -q True; then
  echo "== NikoMusicCoreSelfTest =="
  swift run NikoMusicCoreSelfTest
else
  echo "== NikoMusicCoreSelfTest =="
  echo "not implemented yet; executor must add it before v0.1 is done"
fi
