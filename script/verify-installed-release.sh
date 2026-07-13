#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"

APP_PATH="${1:-/Applications/NikoMusicHub.app}"
VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"

if [[ ! -d "$APP_PATH" ]]; then
  echo "installed app missing: $APP_PATH" >&2
  exit 1
fi

INFO="$APP_PATH/Contents/Info.plist"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
BUILD_ID="$(/usr/libexec/PlistBuddy -c 'Print :NMHBuildID' "$INFO" 2>/dev/null || true)"
SOURCE_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :NMHSourceCommit' "$INFO" 2>/dev/null || true)"
INSTALLED_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"

if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
  echo "installed version mismatch: $BUNDLE_VERSION != $VERSION" >&2
  exit 1
fi
if [[ "$INSTALLED_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
  echo "installed bundle identifier mismatch: $INSTALLED_BUNDLE_ID != $BUNDLE_ID" >&2
  exit 1
fi
if [[ "$BUILD_ID" != "$VERSION"+* ]]; then
  echo "installed build id mismatch: '$BUILD_ID' does not start with $VERSION+" >&2
  exit 1
fi

echo "installed release ok: $APP_PATH bundle_id=$INSTALLED_BUNDLE_ID version=$BUNDLE_VERSION build_id=$BUILD_ID source_commit=$SOURCE_COMMIT"
