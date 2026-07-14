#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
SHORT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
INPUTS=(Package.swift Package.resolved Sources Resources VERSION)

if [[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all -- "${INPUTS[@]}")" ]]; then
  printf '%s+%s\n' "$VERSION" "$SHORT_COMMIT"
  exit 0
fi

MANIFEST="$(mktemp -t niko-music-hub-build-inputs.XXXXXX)"
trap 'rm -f "$MANIFEST"' EXIT

while IFS= read -r -d '' path; do
  if [[ -f "$ROOT/$path" ]]; then
    digest="$(shasum -a 256 "$ROOT/$path" | awk '{print $1}')"
    printf 'file\t%s\t%s\n' "$path" "$digest" >>"$MANIFEST"
  else
    printf 'missing\t%s\n' "$path" >>"$MANIFEST"
  fi
done < <(git -C "$ROOT" ls-files -z --cached --others --exclude-standard -- "${INPUTS[@]}")

FINGERPRINT="$(shasum -a 256 "$MANIFEST" | awk '{print substr($1, 1, 16)}')"
printf '%s+%s.dirty.%s\n' "$VERSION" "$SHORT_COMMIT" "$FINGERPRINT"
