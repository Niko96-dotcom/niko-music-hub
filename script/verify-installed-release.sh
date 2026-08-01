#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"

APP_PATH="${1:-/Applications/NikoMusicHub.app}"
VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"
MIN_MACOS_VERSION="$(nmh_release_min_macos_version)"
EXPECTED_ARCHITECTURES="$(nmh_release_architectures)"

if [[ ! -d "$APP_PATH" ]]; then
  echo "installed app missing: $APP_PATH" >&2
  exit 1
fi

INFO="$APP_PATH/Contents/Info.plist"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
BUILD_ID="$(/usr/libexec/PlistBuddy -c 'Print :NMHBuildID' "$INFO" 2>/dev/null || true)"
SOURCE_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :NMHSourceCommit' "$INFO" 2>/dev/null || true)"
INSTALLED_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"
INSTALLED_BINARY="$APP_PATH/Contents/MacOS/NikoMusicHub"
INSTALLED_MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO" 2>/dev/null || true)"

if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
  echo "installed version mismatch: $BUNDLE_VERSION != $VERSION" >&2
  exit 1
fi
if [[ "$INSTALLED_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
  echo "installed bundle identifier mismatch: $INSTALLED_BUNDLE_ID != $BUNDLE_ID" >&2
  exit 1
fi
if [[ "$INSTALLED_MIN_MACOS" != "$MIN_MACOS_VERSION" ]]; then
  echo "installed minimum macOS mismatch: $INSTALLED_MIN_MACOS != $MIN_MACOS_VERSION" >&2
  exit 1
fi
if [[ "$BUILD_ID" != "$VERSION"+* ]]; then
  echo "installed build id mismatch: '$BUILD_ID' does not start with $VERSION+" >&2
  exit 1
fi

if [[ ! -x "$INSTALLED_BINARY" ]]; then
  echo "installed executable missing: $INSTALLED_BINARY" >&2
  exit 1
fi
INSTALLED_ARCHITECTURES="$(lipo -archs "$INSTALLED_BINARY" | tr ' ' '\n' | sed '/^[[:space:]]*$/d' | sort | paste -sd' ' -)"
if [[ "$INSTALLED_ARCHITECTURES" != "$EXPECTED_ARCHITECTURES" ]]; then
  echo "installed architecture mismatch: $INSTALLED_ARCHITECTURES != $EXPECTED_ARCHITECTURES" >&2
  exit 1
fi
if [[ -n "${NMH_EXPECTED_BUILD_ID:-}" && "$BUILD_ID" != "$NMH_EXPECTED_BUILD_ID" ]]; then
  echo "installed build id mismatch: '$BUILD_ID' != '$NMH_EXPECTED_BUILD_ID'" >&2
  exit 1
fi
if [[ -n "${NMH_EXPECTED_BINARY_SHA256:-}" ]]; then
  INSTALLED_BINARY_SHA256="$(shasum -a 256 "$INSTALLED_BINARY" | awk '{print $1}')"
  if [[ "$INSTALLED_BINARY_SHA256" != "$NMH_EXPECTED_BINARY_SHA256" ]]; then
    echo "installed binary hash mismatch: '$INSTALLED_BINARY_SHA256' != '$NMH_EXPECTED_BINARY_SHA256'" >&2
    exit 1
  fi
fi

echo "installed release ok: $APP_PATH bundle_id=$INSTALLED_BUNDLE_ID version=$BUNDLE_VERSION build_id=$BUILD_ID source_commit=$SOURCE_COMMIT architectures=$INSTALLED_ARCHITECTURES minimum_macos=$INSTALLED_MIN_MACOS"
