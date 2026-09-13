#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ALLOW_MISSING_TAG=false

usage() {
  echo "usage: script/release-preflight.sh [--root checkout] [--allow-missing-tag]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    # A publish rehearsal (--dry-run-publish) may run before the tag exists so the
    # full gate chain, signing and notarization can be proven without moving a tag
    # afterwards. A tag that does exist must still point at HEAD.
    --allow-missing-tag) ALLOW_MISSING_TAG=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -d "$ROOT/.git" ]] || { echo "public release preflight requires a Git checkout: $ROOT" >&2; exit 1; }

VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
TAG="v$VERSION"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"

if [[ -n "$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)" ]]; then
  echo "public release requires a completely clean working tree, including untracked files" >&2
  git -C "$ROOT" status --short >&2
  exit 1
fi

TAG_COMMIT="$(git -C "$ROOT" rev-list -n 1 "$TAG" 2>/dev/null || true)"
if [[ -z "$TAG_COMMIT" && "$ALLOW_MISSING_TAG" == true ]]; then
  echo "public release preflight ok: clean=true tag=$TAG (not created yet; rehearsal) commit=$COMMIT"
  exit 0
fi
if [[ -z "$TAG_COMMIT" || "$TAG_COMMIT" != "$COMMIT" ]]; then
  echo "public release requires tag $TAG to resolve exactly to HEAD $COMMIT" >&2
  exit 1
fi

echo "public release preflight ok: clean=true tag=$TAG commit=$COMMIT"
