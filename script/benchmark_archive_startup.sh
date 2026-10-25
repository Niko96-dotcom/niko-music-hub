#!/usr/bin/env bash
# Startup-path benchmarks for a large archive. Both read the archive and a COPY of the database.
#   script/benchmark_archive_startup.sh [startup] --archive <CubaseArchive> --database <archive-index.sqlite> [--runs N] [phase ...]
#       headless: snapshot decode, metadata load, cache load, scan, cache save, status history, inbox
#       (script/performance/archive-startup.swift)
#   script/benchmark_archive_startup.sh launch --archive <CubaseArchive> --database <archive-index.sqlite> [--scenarios a,b]
#       one in-process launch plus timed interactions in a hosted ArchiveBrowserView
#       (script/performance/archive-launch.swift)
#   script/benchmark_archive_startup.sh tools [--runs N]
#       first-open cost of each tool screen (script/performance/archive-tools.swift)
# Set NMH_BENCH_BINARY_SUFFIX=-name to keep the built binary as <tool>-name (for before/after pairs).
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
# Testing visibility exposes the catalog coordinator without adding product benchmark hooks.
swift build -c release --target FeatureArchiveBrowser -Xswiftc -enable-testing >&2
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p .build/performance-startup
TOOL=startup
if [[ "${1:-}" == "launch" || "${1:-}" == "startup" || "${1:-}" == "tools" ]]; then TOOL="$1"; shift; fi
MODULES=(FeatureArchiveBrowser ProjectVaultRuntime AppCore NikoMusicCore)
if [[ "$TOOL" == "tools" ]]; then
  MODULES+=(FeatureBPMTapper FeatureAudioConverter FeatureAudioRecorder FeatureDownloader FeatureStemSeparation)
  for module in FeatureBPMTapper FeatureAudioConverter FeatureAudioRecorder FeatureDownloader FeatureStemSeparation; do
    swift build -c release --target "$module" -Xswiftc -enable-testing >&2
  done
fi
OBJECTS=()
for module in "${MODULES[@]}"; do
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
OUTPUT=".build/performance-startup/archive-$TOOL${NMH_BENCH_BINARY_SUFFIX:-}"
swiftc -O -parse-as-library -I "$BIN_DIR/Modules" -I "$BIN_DIR" \
  "script/performance/archive-$TOOL.swift" \
  "${OBJECTS[@]}" -lsqlite3 \
  -o "$OUTPUT"
exec "$OUTPUT" "$@"
