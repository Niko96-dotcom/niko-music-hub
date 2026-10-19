#!/usr/bin/env bash
# Runs two benchmark binaries alternately (A, B, A, B ...) so machine drift lands on both, and stores one JSON
# file per run: <outdir>/<tag>-<round>.json. Build the binaries with build-commit-binaries.sh (tag = commit state)
# or with NMH_BENCH_BINARY_SUFFIX.
#
#   script/performance/ab.sh startup <outdir> <rounds> <tagA> <tagB> [archive-startup args ...]
#   script/performance/ab.sh launch  <outdir> <rounds> <tagA> <tagB> [archive-launch args ...]
#
# The archive and database come from the bake-off app.sh (BAKEOFF_NAME file, size 10k) unless
# NMH_BENCH_ARCHIVE / NMH_BENCH_DATABASE are set. Summarize with compare_phases.py (startup) or
# compare_runs.py (launch).
set -euo pipefail
cd "$(dirname "$0")/../.."

tool="${1:?startup|launch}"; outdir="${2:?outdir}"; rounds="${3:?rounds}"; tag_a="${4:?tagA}"; tag_b="${5:?tagB}"
shift 5
paths="$(script/bakeoff/app.sh paths 10k)"
archive="${NMH_BENCH_ARCHIVE:-$(sed -n 's/^ARCHIVE=//p' <<<"$paths")}"
database="${NMH_BENCH_DATABASE:-$(sed -n 's/^DATABASE=//p' <<<"$paths")}"
mkdir -p "$outdir"
for round in $(seq 1 "$rounds"); do
  for tag in "$tag_a" "$tag_b"; do
    binary=".build/performance-startup/archive-$tool-$tag"
    [[ -x "$binary" ]] || { echo "missing $binary" >&2; exit 1; }
    "$binary" --archive "$archive" --database "$database" "$@" >"$outdir/$tag-$round.json" 2>"$outdir/$tag-$round.err"
  done
done
