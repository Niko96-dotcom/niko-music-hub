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

# Every local release tag except the one being cut must already exist on origin
# at the same object. A stray local v* tag anchors history that never went
# through the public filter; `git push --tags` would publish it, and the
# protect-release-tags ruleset then forbids deleting it again.
if ! REMOTE_TAGS="$(git -C "$ROOT" ls-remote --tags origin 'refs/tags/v*')"; then
  echo "public release preflight could not list release tags on origin" >&2
  exit 1
fi
while read -r sha ref; do
  tag="${ref#refs/tags/}"
  [[ "$tag" == "$TAG" ]] && continue
  remote_sha="$(awk -v ref="$ref" '$2 == ref { print $1 }' <<<"$REMOTE_TAGS")"
  if [[ "$remote_sha" != "$sha" ]]; then
    echo "local tag $tag ($sha) does not match origin (${remote_sha:-missing}); delete it with 'git tag -d $tag' or push it deliberately before releasing" >&2
    exit 1
  fi
done < <(git -C "$ROOT" for-each-ref --format='%(objectname) %(refname)' 'refs/tags/v*')

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
