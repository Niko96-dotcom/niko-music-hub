#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"

EVIDENCE=""
EXPECTED_COMMIT="$(nmh_git_commit)"

usage() {
  echo "usage: script/validate-release-uat.sh --evidence evidence.json [--commit git-sha]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence) EVIDENCE="${2:-}"; shift 2 ;;
    --commit) EXPECTED_COMMIT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -f "$EVIDENCE" ]] || { echo "missing consolidated release UAT evidence: $EVIDENCE" >&2; exit 1; }
nmh_json_lint "$EVIDENCE"

read_json() {
  nmh_json_value "$EVIDENCE" "$1" 2>/dev/null || true
}

VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"

[[ "$(read_json schema_version)" == "1" ]] || { echo "release UAT evidence needs schema_version=1" >&2; exit 1; }
[[ "$(read_json version)" == "$VERSION" ]] || { echo "release UAT evidence version does not match $VERSION" >&2; exit 1; }
[[ "$(read_json commit)" == "$EXPECTED_COMMIT" ]] || { echo "release UAT evidence commit does not match $EXPECTED_COMMIT" >&2; exit 1; }
[[ "$(read_json bundle_id)" == "$BUNDLE_ID" ]] || { echo "release UAT evidence bundle_id does not match $BUNDLE_ID" >&2; exit 1; }
[[ "$(read_json status)" == "approved" ]] || { echo "release UAT evidence status must be approved" >&2; exit 1; }

APPROVER="$(read_json approved_by)"
APPROVED_AT="$(read_json approved_at_utc)"
MACHINE="$(read_json machine)"
[[ -n "$APPROVER" && "$APPROVER" != "TODO" ]] || { echo "release UAT evidence needs a real approved_by value" >&2; exit 1; }
[[ "$APPROVED_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { echo "release UAT approved_at_utc must be an ISO-8601 UTC timestamp" >&2; exit 1; }
[[ -n "$MACHINE" && "$MACHINE" != "TODO" ]] || { echo "release UAT evidence needs the tested machine description" >&2; exit 1; }

# The tested build must have the shape that ships. An ad-hoc debug build has a
# per-build TCC identity (permissions reset on every rebuild), no hardened
# runtime and no library validation, so its privacy, recorder and login-item
# results say nothing about the Developer ID artifact.
TESTED_BUILD_ID="$(read_json tested_build.build_id)"
TESTED_CONFIGURATION="$(read_json tested_build.build_configuration)"
TESTED_SIGNING="$(read_json tested_build.signing_identity)"
TESTED_HARDENED="$(read_json tested_build.hardened_runtime)"
[[ "$TESTED_BUILD_ID" == "$VERSION+"* ]] || { echo "release UAT tested_build.build_id must be the installed app's NMHBuildID and start with $VERSION+ (was '${TESTED_BUILD_ID:-missing}')" >&2; exit 1; }
[[ "$TESTED_CONFIGURATION" == "release" ]] || { echo "release UAT must be run on a release-configuration build (tested_build.build_configuration was '${TESTED_CONFIGURATION:-missing}')" >&2; exit 1; }
[[ "$TESTED_SIGNING" == "Developer ID Application:"* ]] || { echo "release UAT must be run on a Developer ID signed build; ad-hoc builds change TCC identity on every rebuild and skip hardened runtime (tested_build.signing_identity was '${TESTED_SIGNING:-missing}')" >&2; exit 1; }
[[ "$TESTED_HARDENED" == "true" ]] || { echo "release UAT must be run on a hardened-runtime build (tested_build.hardened_runtime was '${TESTED_HARDENED:-missing}')" >&2; exit 1; }

REQUIRED_CHECKS=(
  clean_install
  upgrade_preserves_settings
  uninstall
  launch_at_login
  privacy_permissions
  recorder_real_audio
  downloader_live
  archive_read_only
  output_handoffs
  e2e_user_smoke
)
for check in "${REQUIRED_CHECKS[@]}"; do
  result="$(read_json "checks.$check")"
  if [[ "$result" != "passed" ]]; then
    echo "release UAT evidence check '$check' must be passed (was '${result:-missing}')" >&2
    exit 1
  fi
done

echo "release UAT evidence ok: version=$VERSION commit=$EXPECTED_COMMIT approved_by=$APPROVER"
