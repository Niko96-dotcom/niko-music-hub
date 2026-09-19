#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"
# shellcheck source=lib/release_gates.sh
source "$ROOT/script/lib/release_gates.sh"

EVIDENCE=""
EXPECTED_COMMIT="$(nmh_git_commit)"
EXPECTED_SIGNING_IDENTITY="${NMH_DEVELOPER_ID_APPLICATION:-}"
EXPECTED_BUILD_ID_OVERRIDE=""

usage() {
  echo "usage: script/validate-release-uat.sh --evidence evidence.json [--commit git-sha] [--expected-signing-identity 'Developer ID Application: ...'] [--expected-build-id VERSION+SHORT]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence) EVIDENCE="${2:-}"; shift 2 ;;
    --commit) EXPECTED_COMMIT="${2:-}"; shift 2 ;;
    --expected-signing-identity) EXPECTED_SIGNING_IDENTITY="${2:-}"; shift 2 ;;
    --expected-build-id) EXPECTED_BUILD_ID_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -f "$EVIDENCE" ]] || { echo "missing consolidated release UAT evidence: $EVIDENCE" >&2; exit 1; }
nmh_json_lint "$EVIDENCE"

VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"

# Exact tested-commit build binding: the tested build must be the exact
# candidate for EXPECTED_COMMIT, not any older build with the same VERSION
# prefix. BUILD_ID is VERSION+SHORT_COMMIT (short=12) in release-all.sh.
# An explicit --expected-build-id must also equal that canonical value; a
# mismatched override is rejected so it cannot mask a stale build.
EXPECTED_SHORT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 "$EXPECTED_COMMIT" 2>/dev/null || printf '%s' "$EXPECTED_COMMIT" | cut -c1-12)"
CANONICAL_BUILD_ID="$VERSION+$EXPECTED_SHORT_COMMIT"
if [[ -n "$EXPECTED_BUILD_ID_OVERRIDE" ]]; then
  [[ "$EXPECTED_BUILD_ID_OVERRIDE" == "$CANONICAL_BUILD_ID" ]] || { echo "explicit --expected-build-id '$EXPECTED_BUILD_ID_OVERRIDE' does not match canonical $CANONICAL_BUILD_ID for commit $EXPECTED_COMMIT" >&2; exit 1; }
fi
EXPECTED_BUILD_ID="$CANONICAL_BUILD_ID"

# The tested build must have the shape that ships. An ad-hoc debug build has a
# per-build TCC identity (permissions reset on every rebuild), no hardened
# runtime and no library validation, so its privacy, recorder and login-item
# results say nothing about the Developer ID artifact.
#
# Single byte snapshot: read the evidence once in python and validate all
# semantics (strict types, placeholder/blank rejection, exact checks) through
# the shared script/lib/release_uat.py helper, so a file swapped between
# per-key reads cannot pass and JSON string "true"/"1" cannot drift past the
# shell scalar path.
if [[ -n "$EXPECTED_SIGNING_IDENTITY" ]]; then
  [[ "$EXPECTED_SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { echo "explicit --expected-signing-identity must be a Developer ID Application identity (was '$EXPECTED_SIGNING_IDENTITY')" >&2; exit 1; }
fi
REQUIRED_CHECKS_CSV="$(IFS=,; printf '%s' "${NMH_REQUIRED_UAT_CHECKS[*]}")"
APPROVER="$(/usr/bin/python3 - "$EVIDENCE" "$VERSION" "$BUNDLE_ID" "$EXPECTED_COMMIT" "$EXPECTED_BUILD_ID" "${EXPECTED_SIGNING_IDENTITY:-}" "$REQUIRED_CHECKS_CSV" "$ROOT/script/lib" <<'PY'
import json
import pathlib
import sys

evidence_path = pathlib.Path(sys.argv[1])
version, bundle_id, commit = sys.argv[2:5]
expected_build_id, expected_signing_identity = sys.argv[5:7]
required_checks = [c for c in sys.argv[7].split(",") if c]
lib_dir = sys.argv[8]
sys.path.insert(0, lib_dir)
import release_uat

try:
    raw = evidence_path.read_bytes()
except OSError as error:
    raise SystemExit(f"cannot read {evidence_path}: {error}")
try:
    payload = json.loads(raw.decode("utf-8"))
except (UnicodeDecodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"could not parse UAT evidence: {error}")
release_uat.validate_uat(
    payload,
    version,
    bundle_id,
    commit,
    expected_build_id,
    expected_signing_identity,
    required_checks,
)
print(payload.get("approved_by"))
PY
)"

echo "release UAT evidence ok: version=$VERSION commit=$EXPECTED_COMMIT approved_by=$APPROVER build_id=$EXPECTED_BUILD_ID"
