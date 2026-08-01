#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"

ALLOWLIST="$ROOT/script/release-version-allowlist.txt"
BUNDLE_PATH=""
PREVIOUS_VERSION="${NMH_PREVIOUS_VERSION:-}"

usage() {
  cat >&2 <<'USAGE'
usage: script/release-version-verify.sh [--bundle path] [--previous-version x.y.z]

Verifies VERSION is the canonical app release version and optionally blocks stale
previous-version literals outside script/release-version-allowlist.txt.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      BUNDLE_PATH="${2:-}"
      [[ -n "$BUNDLE_PATH" ]] || { usage; exit 2; }
      shift 2
      ;;
    --previous-version)
      PREVIOUS_VERSION="${2:-}"
      [[ -n "$PREVIOUS_VERSION" ]] || { usage; exit 2; }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"
MIN_MACOS_VERSION="$(nmh_release_min_macos_version)"
RELEASE_ARCHITECTURES="$(nmh_release_architectures)"

for commercial_file in LICENSE THIRD_PARTY_NOTICES.md SOURCE_PROVENANCE.md SBOM.spdx.json; do
  if [[ ! -f "$ROOT/$commercial_file" ]]; then
    echo "release commercial record missing: $commercial_file" >&2
    exit 1
  fi
done
SBOM_VERSION="$(nmh_json_value "$ROOT/SBOM.spdx.json" packages.0.versionInfo 2>/dev/null || true)"
if [[ "$SBOM_VERSION" != "$VERSION" ]]; then
  echo "release version violation: SBOM package version '$SBOM_VERSION' does not match VERSION=$VERSION" >&2
  exit 1
fi

CHANGELOG_HEADING="$(grep -E "^## ${VERSION} - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$ROOT/CHANGELOG.md" || true)"
if [[ -z "$CHANGELOG_HEADING" ]]; then
  echo "release version violation: CHANGELOG.md needs a dated '## $VERSION - YYYY-MM-DD' heading" >&2
  exit 1
fi
if grep -Eq "^## ${VERSION} - Unreleased$" "$ROOT/CHANGELOG.md"; then
  echo "release version violation: CHANGELOG.md still marks $VERSION as Unreleased" >&2
  exit 1
fi

if rg -n 'NMH_MARKETING_VERSION="\$\{NMH_MARKETING_VERSION:-[0-9]' "$ROOT/script" >/dev/null; then
  echo "release version violation: app lifecycle scripts must not hard-code marketing version defaults" >&2
  exit 1
fi

if [[ -n "$BUNDLE_PATH" ]]; then
  INFO_PLIST="$BUNDLE_PATH/Contents/Info.plist"
  if [[ ! -f "$INFO_PLIST" ]]; then
    echo "release version violation: bundle Info.plist missing at $INFO_PLIST" >&2
    exit 1
  fi
  BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
  if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
    echo "release version violation: bundle has CFBundleShortVersionString=$BUNDLE_VERSION but VERSION=$VERSION" >&2
    exit 1
  fi
  ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
  if [[ "$ACTUAL_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
    echo "release identity violation: bundle has CFBundleIdentifier=$ACTUAL_BUNDLE_ID but BUNDLE_ID=$BUNDLE_ID" >&2
    exit 1
  fi
  BUILD_ID="$(/usr/libexec/PlistBuddy -c 'Print :NMHBuildID' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ -z "$BUILD_ID" || "$BUILD_ID" != "$VERSION"+* ]]; then
    echo "release version violation: bundle NMHBuildID '$BUILD_ID' does not start with $VERSION+" >&2
    exit 1
  fi
  BUNDLE_MIN_MACOS_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ "$BUNDLE_MIN_MACOS_VERSION" != "$MIN_MACOS_VERSION" ]]; then
    echo "release platform violation: bundle has LSMinimumSystemVersion=$BUNDLE_MIN_MACOS_VERSION but Package.swift requires $MIN_MACOS_VERSION" >&2
    exit 1
  fi
fi

if [[ -n "$PREVIOUS_VERSION" ]]; then
  if [[ ! -f "$ALLOWLIST" ]]; then
    echo "release version violation: missing stale-version allowlist $ALLOWLIST" >&2
    exit 1
  fi
  VIOLATIONS=()
  while IFS= read -r hit; do
    file="${hit%%:*}"
    allowed=false
    while IFS= read -r rule; do
      [[ -z "$rule" || "$rule" =~ ^[[:space:]]*# ]] && continue
      pattern="${rule%%|*}"
      reason="${rule#*|}"
      pattern="${pattern%"${pattern##*[![:space:]]}"}"
      pattern="${pattern#"${pattern%%[![:space:]]*}"}"
      reason="${reason#"${reason%%[![:space:]]*}"}"
      if [[ -n "$pattern" && -n "$reason" && "$file" =~ $pattern ]]; then
        allowed=true
        break
      fi
    done <"$ALLOWLIST"
    if [[ "$allowed" != true ]]; then
      VIOLATIONS+=("$hit")
    fi
  done < <(git -C "$ROOT" grep -n -F "$PREVIOUS_VERSION" -- . ':!script/release-version-allowlist.txt' || true)

  if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "release version violation: previous version $PREVIOUS_VERSION appears outside allowlist:" >&2
    printf '  %s\n' "${VIOLATIONS[@]}" >&2
    exit 1
  fi
fi

echo "release identity ok: VERSION=$VERSION BUNDLE_ID=$BUNDLE_ID architectures=$RELEASE_ARCHITECTURES minimum_macos=$MIN_MACOS_VERSION"
