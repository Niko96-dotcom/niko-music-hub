#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "== swift build =="
swift build

echo "== swift test (local deterministic gate) =="
# The always-on Mac reports system-audio permission as authorized but cannot reliably
# start a CoreAudio aggregate capture device. Keep these real-device tests out of the
# default automation gate; run them manually/on the MacBook when checking recorder hardware.
swift test \
  --skip CoreAudioTapAdapterTests \
  --skip 'RecorderIntegrationTests/testMaxDurationAutoStop' \
  --skip 'RecorderIntegrationTests/testOutputFileHasCorrectFormat' \
  --skip 'RecorderIntegrationTests/testRecordingCapturesRealSystemAudio' \
  --skip 'RecorderIntegrationTests/testRecordingProducesOutputInboxItem'

echo "== recorder deterministic gate =="
swift test --filter 'AudioRecorderViewModelTests/testMaxDurationAutoFinishFinalizesWAVAndInboxItem'

echo "== ui probe malformed AX self-test =="
swift script/ui_probe.swift --self-test-malformed-ax

echo "== NikoMusicCoreSelfTest =="
swift package describe --type json | /usr/bin/python3 -c '
import json
import sys
data = json.load(sys.stdin)
products = {product.get("name") for product in data.get("products", [])}
targets = {target.get("name") for target in data.get("targets", [])}
if "NikoMusicCoreSelfTest" not in products or "NikoMusicCoreSelfTest" not in targets:
    print("critical self-test missing: NikoMusicCoreSelfTest product/target", file=sys.stderr)
    sys.exit(1)
'
swift run NikoMusicCoreSelfTest

echo "== release engineering regression gate =="
./script/release-version-verify.sh
./script/public-tree-hygiene.sh
./Tests/test_release_scripts.sh
