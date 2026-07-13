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
