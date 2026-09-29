#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Git does not preserve the equal modification times used by ranking fixtures.
echo "== generate deterministic fixtures =="
./script/fixtures/generate_cubase_archive_fixtures.sh

echo "== swift build =="
swift build --build-tests --explicit-target-dependency-import-check error

echo "== swift test (local deterministic gate) =="
# The always-on Mac reports system-audio permission as authorized but cannot reliably
# start a CoreAudio aggregate capture device. Keep these real-device tests out of the
# default automation gate; run them manually on a supported release Mac when checking recorder hardware.
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

echo "== NikoMusicHubCLI export smoke =="
swift package describe --type json | /usr/bin/python3 -c '
import json
import sys
data = json.load(sys.stdin)
products = {product.get("name") for product in data.get("products", [])}
targets = {target.get("name") for target in data.get("targets", [])}
if "NikoMusicHubCLI" not in products or "NikoMusicHubCLI" not in targets:
    print("critical CLI missing: NikoMusicHubCLI product/target", file=sys.stderr)
    sys.exit(1)
'
FIXTURE_ROOT="$(pwd)/Fixtures/CubaseArchive"
OUT="$(mktemp -t niko-cli-index.XXXXXX.json)"
swift run NikoMusicHubCLI export-index --roots "$FIXTURE_ROOT" --output "$OUT"
# Expected facts are written down from script/fixtures/generate_cubase_archive_fixtures.sh
# (8 CPR song folders + "Broken Folder Example"), not recomputed from the export itself.
/usr/bin/python3 - "$OUT" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
songs = data.get("songs")
if not isinstance(songs, list):
    print("CLI export smoke: missing songs array", file=sys.stderr)
    sys.exit(1)
if not (data.get("songCount") == 9 == len(songs)):
    print(f"CLI export smoke: songCount={data.get('songCount')!r} rows={len(songs)}, expected 9 and 9", file=sys.stderr)
    sys.exit(1)
neon = [song for song in songs if song.get("displayTitle") == "Neon Hook"]
if len(neon) != 1:
    print(f"CLI export smoke: expected exactly one Neon Hook row, found {len(neon)}", file=sys.stderr)
    sys.exit(1)
latest = (neon[0].get("latestCPR") or {}).get("fileName")
if latest != "Neon Hook.cpr":
    print(f"CLI export smoke: Neon Hook latestCPR={latest!r}, expected 'Neon Hook.cpr'", file=sys.stderr)
    sys.exit(1)
preview = neon[0].get("mainPreviewCandidateID") or ""
if not preview.endswith("/Neon Hook/Mixdown/Neon Hook v3.wav"):
    print(f"CLI export smoke: Neon Hook mainPreviewCandidateID={preview!r}", file=sys.stderr)
    sys.exit(1)
PY
rm -f "$OUT"

echo "== NikoMusicHubCLI refuses export into the archive root =="
fixture_digest() {
  (cd "$FIXTURE_ROOT" && find . | LC_ALL=C sort && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256) | shasum -a 256
}
FIXTURE_BEFORE="$(fixture_digest)"
if swift run NikoMusicHubCLI export-index --roots "$FIXTURE_ROOT" --output "$FIXTURE_ROOT/cli-export-must-be-refused.json"; then
  echo "CLI export smoke: export-index wrote into the archive root" >&2
  exit 1
fi
if [[ "$(fixture_digest)" != "$FIXTURE_BEFORE" ]]; then
  echo "CLI export smoke: fixture archive changed after a refused export" >&2
  exit 1
fi

echo "== release engineering regression gate =="
./script/release-version-verify.sh
./script/public-tree-hygiene.sh
./Tests/test_release_scripts.sh
./Tests/test_source_distribution_scripts.sh
/usr/bin/python3 Tests/test_release_provenance.py
/usr/bin/python3 -m unittest discover -s Tests -p 'test_release_pipeline_provenance.py'
