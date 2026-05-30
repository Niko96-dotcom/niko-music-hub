#!/usr/bin/env bash
# GSD SDK wrapper — ensures gsd-sdk is on PATH for Cursor terminals and CI-adjacent scripts.
set -euo pipefail

export PATH="/opt/homebrew/bin:${HOME}/.local/bin:${PATH}"

if ! command -v gsd-sdk >/dev/null 2>&1; then
  echo "gsd-sdk not found; installing get-shit-done-cc globally..." >&2
  npm install -g get-shit-done-cc@latest
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec gsd-sdk "$@"
