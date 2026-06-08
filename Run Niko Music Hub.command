#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

status=0
./script/dev.sh run || status=$?

printf '\n'
if [[ "$status" -eq 0 ]]; then
  printf 'Niko Music Hub was built and launched.\n'
else
  printf 'Niko Music Hub launch failed with exit code %s.\n' "$status"
fi

if [[ -t 0 ]]; then
  read -r -p "Press Return to close this window. " _
fi

exit "$status"
