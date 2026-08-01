#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"

MODE="public"
MANIFEST=""
ARTIFACT=""
ALLOW_PENDING=false

usage() {
  cat >&2 <<'USAGE'
usage: script/validate-release-artifact.sh --artifact path.dmg --manifest manifest.json [--mode public|local-only] [--allow-pending]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact) ARTIFACT="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --allow-pending) ALLOW_PENDING=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -f "$ARTIFACT" ]] || { echo "missing artifact: $ARTIFACT" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "missing manifest: $MANIFEST" >&2; exit 1; }
[[ "$MODE" == "public" || "$MODE" == "local-only" ]] || { usage; exit 2; }

VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"
COMMIT="$(nmh_git_commit)"
EXPECTED_ARCHITECTURES="$(nmh_release_architectures)"
MIN_MACOS_VERSION="$(nmh_release_min_macos_version)"
ARTIFACT_DIR="$(cd "$(dirname "$ARTIFACT")" && pwd)"
ARTIFACT_BASENAME="$(basename "$ARTIFACT")"
SHA_FILE="$ARTIFACT.sha256"

manifest_value() {
  nmh_json_value "$MANIFEST" "$1" 2>/dev/null || true
}

nmh_json_lint "$MANIFEST"
[[ "$(manifest_value schema_version)" == "1" ]] || { echo "manifest schema_version must be 1" >&2; exit 1; }
[[ "$(manifest_value product)" == "Niko Music Hub" ]] || { echo "manifest product mismatch" >&2; exit 1; }
[[ "$(manifest_value version)" == "$VERSION" ]] || { echo "manifest version mismatch" >&2; exit 1; }
[[ "$(manifest_value bundle_id)" == "$BUNDLE_ID" ]] || { echo "manifest bundle_id mismatch" >&2; exit 1; }
[[ "$(manifest_value commit)" == "$COMMIT" ]] || { echo "manifest commit mismatch" >&2; exit 1; }
[[ "$(manifest_value minimum_macos)" == "$MIN_MACOS_VERSION" ]] || { echo "manifest minimum_macos mismatch" >&2; exit 1; }
[[ "$(manifest_value artifact)" == "$ARTIFACT_BASENAME" ]] || { echo "manifest artifact name mismatch" >&2; exit 1; }
[[ "$(manifest_value checksum)" == "$ARTIFACT_BASENAME.sha256" ]] || { echo "manifest checksum name mismatch" >&2; exit 1; }
EXPECTED_ARCHITECTURES_JSON="$(/usr/bin/python3 - "$EXPECTED_ARCHITECTURES" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1].split()))
PY
)"
[[ "$(manifest_value architectures)" == "$EXPECTED_ARCHITECTURES_JSON" ]] || { echo "manifest architectures mismatch" >&2; exit 1; }
if [[ "$MODE" == "public" ]]; then
  [[ "$ARTIFACT_BASENAME" == "NikoMusicHub-$VERSION.dmg" ]] || { echo "public artifact name mismatch: $ARTIFACT_BASENAME" >&2; exit 1; }
  [[ "$(manifest_value public_release)" == "true" ]] || { echo "public manifest must set public_release=true" >&2; exit 1; }
else
  [[ "$(manifest_value public_release)" == "false" ]] || { echo "local-only manifest must set public_release=false" >&2; exit 1; }
fi
VALIDATION_STATUS="$(manifest_value validation_status)"
if [[ "$VALIDATION_STATUS" != "passed" ]]; then
  if [[ "$ALLOW_PENDING" != true || "$VALIDATION_STATUS" != "pending" ]]; then
    echo "manifest validation_status must be passed (pending is allowed only for the internal candidate validation)" >&2
    exit 1
  fi
fi

[[ -f "$SHA_FILE" ]] || { echo "missing checksum file: $SHA_FILE" >&2; exit 1; }
if rg -n '/' "$SHA_FILE" >/dev/null; then
  echo "checksum file must contain artifact basenames only: $SHA_FILE" >&2
  exit 1
fi
(cd "$ARTIFACT_DIR" && shasum -a 256 -c "$(basename "$SHA_FILE")")
ACTUAL_SHA="$(awk '{print $1}' "$SHA_FILE")"
[[ "$(manifest_value artifact_sha256)" == "$ACTUAL_SHA" ]] || { echo "manifest artifact_sha256 mismatch" >&2; exit 1; }
ACTUAL_ARTIFACT_SIZE="$(stat -f%z "$ARTIFACT")"
[[ "$(manifest_value artifact_size_bytes)" == "$ACTUAL_ARTIFACT_SIZE" ]] || { echo "manifest artifact_size_bytes mismatch" >&2; exit 1; }

MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nmh-release-mount.XXXXXX")"
MOUNT_DIR="$(cd "$MOUNT_DIR" && pwd -P)"
cleanup() {
  set +e
  if mount | grep -Fq " on $MOUNT_DIR "; then
    hdiutil detach "$MOUNT_DIR" -quiet -force >/dev/null 2>&1
    diskutil unmount force "$MOUNT_DIR" >/dev/null 2>&1
  fi
  if mount | grep -Fq " on $MOUNT_DIR "; then
    echo "warning: could not detach release validation mount at $MOUNT_DIR" >&2
  else
    rm -rf "$MOUNT_DIR"
  fi
}
trap cleanup EXIT

hdiutil attach "$ARTIFACT" -mountpoint "$MOUNT_DIR" -nobrowse -readonly -quiet
APP="$MOUNT_DIR/NikoMusicHub.app"
[[ -d "$APP" ]] || { echo "artifact layout invalid: NikoMusicHub.app missing in $ARTIFACT_BASENAME" >&2; exit 1; }
INFO="$APP/Contents/Info.plist"
[[ -f "$INFO" ]] || { echo "artifact layout invalid: app Info.plist missing" >&2; exit 1; }

BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
[[ "$BUNDLE_VERSION" == "$VERSION" ]] || {
  echo "artifact version mismatch: $BUNDLE_VERSION != $VERSION" >&2
  exit 1
}
BUILD_ID="$(/usr/libexec/PlistBuddy -c 'Print :NMHBuildID' "$INFO" 2>/dev/null || true)"
[[ "$BUILD_ID" == "$VERSION"+* ]] || {
  echo "artifact build id mismatch: '$BUILD_ID' does not start with $VERSION+" >&2
  exit 1
}
ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"
[[ "$ACTUAL_BUNDLE_ID" == "$BUNDLE_ID" ]] || {
  echo "artifact bundle identifier mismatch: $ACTUAL_BUNDLE_ID != $BUNDLE_ID" >&2
  exit 1
}
APP_MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO" 2>/dev/null || true)"
[[ "$APP_MIN_MACOS" == "$MIN_MACOS_VERSION" ]] || {
  echo "artifact minimum macOS mismatch: $APP_MIN_MACOS != $MIN_MACOS_VERSION" >&2
  exit 1
}
SOURCE_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :NMHSourceCommit' "$INFO" 2>/dev/null || true)"
[[ "$SOURCE_COMMIT" == "$COMMIT" ]] || {
  echo "artifact source commit mismatch: $SOURCE_COMMIT != $COMMIT" >&2
  exit 1
}
[[ "$(manifest_value build_id)" == "$BUILD_ID" ]] || { echo "manifest build_id mismatch" >&2; exit 1; }

SIGNING_IDENTITY="$(manifest_value signing.identity)"
if [[ "$MODE" == "public" ]]; then
  [[ -n "$SIGNING_IDENTITY" && "$SIGNING_IDENTITY" != "ad-hoc" && "$SIGNING_IDENTITY" != "-" ]] || {
    echo "public manifest must record a real signing identity" >&2
    exit 1
  }
  [[ "$(manifest_value signing.hardened_runtime)" == "true" ]] || { echo "public manifest must record hardened runtime" >&2; exit 1; }
  [[ "$(manifest_value signing.notarization)" == "stapled" ]] || { echo "public manifest must record stapled notarization" >&2; exit 1; }
else
  [[ "$SIGNING_IDENTITY" == "ad-hoc" ]] || { echo "local-only manifest must record ad-hoc signing" >&2; exit 1; }
  [[ "$(manifest_value signing.hardened_runtime)" == "false" ]] || { echo "local-only manifest must not claim hardened runtime" >&2; exit 1; }
  [[ "$(manifest_value signing.notarization)" == "not-applicable" ]] || { echo "local-only manifest must not claim notarization" >&2; exit 1; }
fi

BINARY="$APP/Contents/MacOS/NikoMusicHub"
[[ -x "$BINARY" ]] || { echo "artifact layout invalid: executable missing at $BINARY" >&2; exit 1; }
ACTUAL_ARCHITECTURES="$(lipo -archs "$BINARY" | tr ' ' '\n' | sed '/^[[:space:]]*$/d' | sort | paste -sd' ' -)"
[[ "$ACTUAL_ARCHITECTURES" == "$EXPECTED_ARCHITECTURES" ]] || {
  echo "artifact architectures mismatch: $ACTUAL_ARCHITECTURES != $EXPECTED_ARCHITECTURES" >&2
  exit 1
}

if [[ "$MODE" == "public" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP"
  SIGN_OUTPUT="$(codesign -dv --verbose=4 "$APP" 2>&1 || true)"
  if ! grep -Fq "Authority=$SIGNING_IDENTITY" <<<"$SIGN_OUTPUT"; then
    echo "public artifact signing identity does not match manifest" >&2
    exit 1
  fi
  if [[ ! "$SIGN_OUTPUT" =~ Runtime\ Version && ! "$SIGN_OUTPUT" =~ flags=.*runtime ]]; then
    echo "public artifact is not hardened-runtime signed" >&2
    exit 1
  fi
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose "$APP"
  xcrun stapler validate "$ARTIFACT"
  spctl --assess --type open --context context:primary-signature --verbose "$ARTIFACT"
else
  echo "local-only validation: signature/notarization/Gatekeeper checks intentionally skipped"
fi

echo "release artifact ok: $ARTIFACT_BASENAME bundle_id=$ACTUAL_BUNDLE_ID version=$VERSION build_id=$BUILD_ID mode=$MODE"
