#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"

OUTPUT="${1:-}"
[[ -n "$OUTPUT" ]] || { echo "usage: script/extract-release-notes.sh output.md" >&2; exit 2; }
VERSION="$(nmh_release_version)"

awk -v version="$VERSION" '
  $0 ~ "^## " version " - [0-9]{4}-[0-9]{2}-[0-9]{2}$" { active=1; next }
  active && /^## / { exit }
  active { print }
' "$ROOT/CHANGELOG.md" >"$OUTPUT"

if ! grep -Eq '^- ' "$OUTPUT"; then
  echo "release notes for $VERSION are missing or empty in CHANGELOG.md" >&2
  exit 1
fi

echo "release notes extracted: version=$VERSION output=$OUTPUT"
