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

# Fail on environment problems before any lengthy gate. rg and the
# cryptography module for /usr/bin/python3 are not stock assumptions on every
# Mac, and the Apple/Swift tools below are required by the signing,
# notarization, and packaging path. Only presence is checked here, never exact
# host versions, so supported Xcode/Swift patch updates keep passing. gh stays
# conditional on --publish in release-all.sh and is intentionally not required
# here; resolved .build artifacts are likewise not demanded because swift build
# resolves them before feed generation.
require_public_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "public release preflight missing required tool '$1': $2" >&2
    exit 1
  }
}

require_public_tool git "install Xcode command line tools before releasing (release identity and tagging)"
require_public_tool rg "install ripgrep before releasing (version and packaging gates search tracked sources)"
require_public_tool swift "install Xcode with Swift 6.x before releasing (the release build step)"
require_public_tool xcrun "install Xcode command line tools before releasing (notarization and stapling run through xcrun)"
require_public_tool codesign "install Xcode command line tools before releasing (Developer ID signing)"
require_public_tool hdiutil "hdiutil packages the release DMG and is required before releasing"
require_public_tool plutil "plutil reads candidate bundle metadata and is required before releasing"
require_public_tool spctl "install Xcode command line tools before releasing (Gatekeeper assessment of the signed app and DMG)"
require_public_tool ditto "ditto stages and archives the release app bundle and is required before releasing"
require_public_tool curl "curl fetches the live update feed to prove the build number advances"
require_public_tool shasum "shasum writes and verifies release checksums and manifests"
require_public_tool lipo "install Xcode command line tools before releasing (release architecture verification runs through lipo)"
[[ -x /usr/libexec/PlistBuddy ]] || {
  echo "public release preflight missing required tool '/usr/libexec/PlistBuddy': PlistBuddy reads candidate bundle metadata and is required before releasing" >&2
  exit 1
}
xcrun --find notarytool >/dev/null 2>&1 || {
  echo "public release preflight requires notarytool via xcrun: install Xcode command line tools before releasing (notarization runs through xcrun notarytool)" >&2
  exit 1
}
xcrun --find stapler >/dev/null 2>&1 || {
  echo "public release preflight requires stapler via xcrun: install Xcode command line tools before releasing (stapling runs through xcrun stapler)" >&2
  exit 1
}
# Match the compiler selection used by script/lib/app_lifecycle.sh:nmh_swift
# and script/ci.sh. A PATH-only probe can inspect a Homebrew/swiftly compiler
# even though the release build will use Xcode through DEVELOPER_DIR.
release_swift_version() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    DEVELOPER_DIR="$DEVELOPER_DIR" swift --version
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift --version
  else
    swift --version
  fi
}

SWIFT_VERSION_OUTPUT="$(release_swift_version 2>&1 || true)"
if ! printf '%s\n' "$SWIFT_VERSION_OUTPUT" | grep -Eq 'Swift version 6(\.| |$)'; then
  echo "public release preflight requires Swift 6.x: swift --version reported '${SWIFT_VERSION_OUTPUT:-unknown}'; install Xcode with Swift 6.x before releasing" >&2
  exit 1
fi
[[ -x /usr/bin/python3 ]] || {
  echo "public release preflight missing required tool '/usr/bin/python3': macOS system Python validates the update feed and release metadata" >&2
  exit 1
}
/usr/bin/python3 -c "import cryptography" 2>/dev/null || {
  echo "public release preflight requires the 'cryptography' module for /usr/bin/python3: update-feed signature verification cannot run without it" >&2
  exit 1
}

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
