#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="/Applications/NikoMusicHub.app"

if [[ "${1:-}" == "--app-path" ]]; then
  [[ -n "${2:-}" ]] || { echo "usage: $0 [--app-path PATH]" >&2; exit 2; }
  APP_PATH="$2"
  shift 2
fi
[[ $# -eq 0 ]] || { echo "usage: $0 [--app-path PATH]" >&2; exit 2; }

EXPECTED_BUILD_ID="$("$ROOT/script/local-build-identity.sh")"
export NMH_BUILD_ID="$EXPECTED_BUILD_ID"
export NMH_SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"

# shellcheck source=lib/app_lifecycle.sh
source "$ROOT/script/lib/app_lifecycle.sh"

nmh_stop_app true
nmh_build_bundle

SOURCE_BINARY_SHA256="$(shasum -a 256 "$NMH_APP_BINARY" | awk '{print $1}')"
STAGING_PATH="${APP_PATH}.installing.$$"
BACKUP_PATH="${APP_PATH}.previous.$$"

cleanup() {
  rm -rf "$STAGING_PATH"
  if [[ -d "$BACKUP_PATH" && ! -d "$APP_PATH" ]]; then
    mv "$BACKUP_PATH" "$APP_PATH"
  else
    rm -rf "$BACKUP_PATH"
  fi
}
trap cleanup EXIT

rm -rf "$STAGING_PATH" "$BACKUP_PATH"
mkdir -p "$(dirname "$APP_PATH")"
/usr/bin/ditto "$NMH_APP_BUNDLE" "$STAGING_PATH"

NMH_EXPECTED_BUILD_ID="$EXPECTED_BUILD_ID" \
NMH_EXPECTED_BINARY_SHA256="$SOURCE_BINARY_SHA256" \
  "$ROOT/script/verify-installed-release.sh" "$STAGING_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGING_PATH"

if [[ -d "$APP_PATH" ]]; then
  mv "$APP_PATH" "$BACKUP_PATH"
fi
mv "$STAGING_PATH" "$APP_PATH"

NMH_EXPECTED_BUILD_ID="$EXPECTED_BUILD_ID" \
NMH_EXPECTED_BINARY_SHA256="$SOURCE_BINARY_SHA256" \
  "$ROOT/script/verify-installed-release.sh" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "local install ok: $APP_PATH build_id=$EXPECTED_BUILD_ID binary_sha256=$SOURCE_BINARY_SHA256"
