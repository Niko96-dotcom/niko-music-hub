#!/usr/bin/env bash
# Builds the startup and launch benchmark binaries as they behave at an earlier commit, so a fix can be
# measured against the commit before it with the same harness:
#
#   script/performance/build-commit-binaries.sh <tag> <commit> [tools]
#
# `tools` is "startup launch" by default; pass "startup" to skip the launch binary.
#
# It copies Sources/ from <commit> into the working tree, builds .build/performance-startup/archive-startup-<tag>
# and archive-launch-<tag> (the harness itself always comes from the current checkout), and puts Sources/ back
# to HEAD. It refuses to run with uncommitted changes under Sources/ and never touches the index of anything
# else. Run the binaries alternately (before, after, before, after ...) to cancel machine drift; see
# docs/perf-bakeoff/PERF-REPORT.md for the commands.
set -euo pipefail
cd "$(dirname "$0")/../.."

tag="${1:?usage: build-commit-binaries.sh <tag> <commit>}"
commit="${2:?usage: build-commit-binaries.sh <tag> <commit>}"
tools="${3:-startup launch}"
archive="bakeoff-data/10k/CubaseArchive"
database="${NMH_BENCH_DATABASE:?set NMH_BENCH_DATABASE to an archive-index.sqlite (only used to prove the build links)}"

if ! git diff --quiet HEAD -- Sources; then
  echo "refusing: uncommitted changes under Sources/" >&2
  exit 1
fi
restore() { git checkout HEAD -- Sources >/dev/null 2>&1 || true; }
trap restore EXIT

git checkout "$commit" -- Sources
for tool in $tools; do
  # --runs 1 with one cheap phase/scenario: the wrapper builds, links and runs the binary once.
  extra=(snapshot-load)
  [[ "$tool" == "launch" ]] && extra=(--scenarios open --runs 1 --timeout 1)
  NMH_BENCH_BINARY_SUFFIX="-$tag" script/benchmark_archive_startup.sh "$tool" \
    --archive "$archive" --database "$database" "${extra[@]}" >/dev/null
done
echo "built $tools ($tag) from $commit"
