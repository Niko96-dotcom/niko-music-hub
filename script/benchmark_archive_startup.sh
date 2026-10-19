#!/usr/bin/env bash
# Headless startup-path benchmark: snapshot decode, metadata load, scan, cache save, status history, inbox.
#   script/benchmark_archive_startup.sh --archive <CubaseArchive> --database <archive-index.sqlite> [--runs N] [phase ...]
# Reads the archive and a COPY of the database; see script/performance/archive-startup.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
# Testing visibility exposes the catalog coordinator without adding product benchmark hooks.
swift build -c release --target FeatureArchiveBrowser -Xswiftc -enable-testing >&2
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p .build/performance-startup
OBJECTS=()
for module in FeatureArchiveBrowser AppCore NikoMusicCore; do
  if [[ -f "$BIN_DIR/$module.o" ]]; then
    # Single-object layout: one module object next to its swiftmodule.
    OBJECTS+=("$BIN_DIR/$module.o")
  else
    # Per-source objects under <Module>.build, listed in the output file map.
    while IFS= read -r object; do OBJECTS+=("$object"); done < <(
      python3 - "$BIN_DIR" "$module" <<'PYOBJECTS'
import json, pathlib, sys
root, module = pathlib.Path(sys.argv[1]), sys.argv[2]
mapping = json.loads((root / (module + ".build") / "output-file-map.json").read_text())
for entry in mapping.values():
    obj = entry.get("object")
    if obj and pathlib.Path(obj).is_file(): print(obj)
PYOBJECTS
    )
  fi
done
swiftc -O -parse-as-library -I "$BIN_DIR/Modules" -I "$BIN_DIR" \
  script/performance/archive-startup.swift \
  "${OBJECTS[@]}" -lsqlite3 \
  -o .build/performance-startup/archive-startup
exec .build/performance-startup/archive-startup "$@"
