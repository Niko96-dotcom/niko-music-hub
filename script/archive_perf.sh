#!/usr/bin/env bash
# Reproduce the 10k archive scenarios in the isolated running release app.
set -euo pipefail
cd "$(dirname "$0")/.."

label="${1:?usage: script/archive_perf.sh LABEL [RUNS]}"
runs="${2:-7}"
[[ "$label" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "invalid result label" >&2; exit 64; }
[[ "$runs" =~ ^([1-9]|[1-9][0-9]|100)$ ]] || { echo "runs must be 1...100" >&2; exit 64; }
mkdir -p .build
script/bakeoff/app.sh stop 10k
trap 'if [[ "${KEEP_RUNNING:-0}" != 1 ]]; then script/bakeoff/app.sh stop 10k; fi' EXIT
script/bakeoff/app.sh prepare 10k >".build/perf-$label-prepare.log" 2>&1

# The frozen launcher's conditional function call can mask a compiler failure
# and package an older executable. Require a successful strict build ourselves.
swift build -c release --product NikoMusicHub --explicit-target-dependency-import-check error \
  >".build/perf-$label-build.log" 2>&1 || { tail -n 40 ".build/perf-$label-build.log" >&2; exit 1; }
/usr/bin/python3 -I - "$label" "$runs" <<'PY'
import json, pathlib, sys
label, runs = sys.argv[1], int(sys.argv[2])
path = pathlib.Path('bakeoff-data/10k/perf-request.json')
path.write_text(json.dumps(dict(label=label, runs=runs, songCount=10000, settleSeconds=60)))
PY
launch="$(script/bakeoff/app.sh launch 10k release)"
printf '%s\n' "$launch"
if rg -q 'error:|Build failed' ".build/bakeoff-build-$(tr -d '[:space:]' < BAKEOFF_NAME)-release.log"; then
  echo "launcher build log contains errors; refusing stale-binary measurements" >&2
  exit 1
fi
pid="$(printf '%s\n' "$launch" | sed -n 's/^PID=\([0-9]*\).*/\1/p')"
[[ -n "$pid" ]] || { echo "launcher did not identify its process" >&2; exit 1; }
/usr/bin/python3 -I - "$label" "$runs" "$pid" <<'PY'
import json, os, pathlib, statistics, sys, time
label, runs, pid = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
root = pathlib.Path('bakeoff-data/10k')
requested = (root / 'perf-request.json').stat().st_mtime
result = root / f'perf-{label}.json'
deadline = time.monotonic() + 240 + runs * 25
while True:
    if result.exists() and result.stat().st_mtime >= requested:
        events = json.loads(result.read_text())
        break
    if time.monotonic() >= deadline:
        raise SystemExit('measurement timed out; inspect the isolated stdout log')
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        raise SystemExit('app exited before writing its results')
    time.sleep(0.25)
for name in ('catalog_ready', 'index_persisted', 'ready', 'wheel_to_oldest', 'fling_to_oldest', 'open_detail', 'detail_to_board'):
    rows = [row for row in events if row['scenario'] == name]
    if not rows or (name in ('wheel_to_oldest', 'fling_to_oldest', 'open_detail', 'detail_to_board') and len(rows) != runs):
        raise SystemExit(f'incomplete scenario: {name}')
    values = [row['ms'] for row in rows]
    passed = sum(row.get('reached', row.get('mounted', True)) for row in rows)
    print(f'{name}: median={statistics.median(values):.2f} ms range={min(values):.2f}..{max(values):.2f} n={len(rows)} passed={passed}')
settled = [row for row in events if row['scenario'] == 'settled']
if len(settled) != 1:
    raise SystemExit('missing settled-memory observation')
print(f'settled footprint: {settled[0]["footprintMiB"]:.2f} MiB')
print(f'result: {result}')
PY
