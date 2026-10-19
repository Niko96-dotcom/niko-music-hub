#!/usr/bin/env bash
# Launches the real bake-off app bundle through script/bakeoff/app.sh (release build, isolated suite, synthetic
# archive) and times it from the moment its process exists:
#
#   script/performance/real-launch.sh <out.json> [size]      (size: 10k by default)
#
# window-probe reports milliseconds from process start to the first on-screen window, the process CPU seconds, and
# when the process went quiet (CPU below 0.15 cores for one second). "Quiet" is when the launch scan and the cache
# save are done, but a scan that waits on disk latency can look quiet early, so read it with the CPU curve in the
# JSON (`samples`). The app is stopped afterwards. To compare two code states, check out Sources/ of the older
# commit first (git checkout <commit> -- Sources), run this, then `git checkout HEAD -- Sources` again.
set -euo pipefail
cd "$(dirname "$0")/../.."

out="${1:?usage: real-launch.sh <out.json> [size]}"
size="${2:-10k}"
name="${BAKEOFF_NAME:-$(tr -d '[:space:]' <BAKEOFF_NAME)}"
probe=".build/performance-startup/window-probe"
if [[ ! -x "$probe" ]]; then
  mkdir -p "$(dirname "$probe")"
  swiftc -O script/performance/window-probe.swift -o "$probe"
fi

script/bakeoff/app.sh stop "$size"
sleep 1
log="$(mktemp -t nmh-real-launch)"
(script/bakeoff/app.sh launch "$size" release >"$log" 2>&1 &)

# The app's own executable is the first word of its command line; the build's `cp` of it is not.
pid=""
for _ in $(seq 1 30000); do
  pid="$(ps -axo pid=,command= | awk -v pattern="bakeoff/$name-release/NikoMusicHub\\\\.app/Contents/MacOS/NikoMusicHub\$" '$2 ~ pattern {print $1; exit}')"
  [[ -n "$pid" ]] && break
  sleep 0.01
done
[[ -n "$pid" ]] || { echo "app did not start" >&2; cat "$log" >&2; exit 1; }
"$probe" "$pid" 90 >"$out"
script/bakeoff/app.sh stop "$size"
rm -f "$log"
