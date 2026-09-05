#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
# Testing visibility exposes fixture injection without adding product benchmark hooks.
swift build -c release --target FeatureArchiveBrowser -Xswiftc -enable-testing >&2
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p .build/performance-ui
OBJECTS=()
while IFS= read -r object; do OBJECTS+=("$object"); done < <(
  python3 - "$BIN_DIR" <<'PYOBJECTS'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for module in ("FeatureArchiveBrowser", "AppCore", "NikoMusicCore"):
    mapping = json.loads((root / (module + ".build") / "output-file-map.json").read_text())
    for entry in mapping.values():
        obj = entry.get("object")
        if obj and pathlib.Path(obj).is_file(): print(obj)
PYOBJECTS
)
swiftc -O -parse-as-library -I "$BIN_DIR/Modules" \
  script/performance/archive-ui.swift \
  "${OBJECTS[@]}" -lsqlite3 \
  -o .build/performance-ui/archive-ui
exec .build/performance-ui/archive-ui "$@"
