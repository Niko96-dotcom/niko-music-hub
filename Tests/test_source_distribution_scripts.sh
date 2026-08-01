#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nmh-source-distribution-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

assert_fail() {
  local name="$1"
  shift
  if "$@" >"$TMP/$name.out" 2>"$TMP/$name.err"; then
    echo "expected failure but command passed: $name" >&2
    exit 1
  fi
}

assert_contains() {
  local file="$1"
  local value="$2"
  grep -Fq "$value" "$file" || { echo "expected '$value' in $file" >&2; exit 1; }
}

COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
APPROVAL="$TMP/approval.json"
cat >"$APPROVAL" <<JSON
{
  "schema_version": 1,
  "status": "approved",
  "commit": "$COMMIT",
  "legal_entity": "Release Test Entity",
  "approved_by": "Release Test Owner",
  "approved_at_utc": "2026-07-13T12:00:00Z",
  "attestations": {
    "source_rights_transferable": true,
    "seed_project_rights_transferable": true,
    "brand_asset_rights_transferable": true,
    "fixtures_are_synthetic_and_private_data_free": true,
    "excluded_material_reviewed": true,
    "written_sale_or_license_terms_exist": true
  }
}
JSON

echo "== owner attestation is exact-commit and complete =="
"$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT" >/dev/null
assert_fail wrong-commit "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit 0000000000000000000000000000000000000000
assert_contains "$TMP/wrong-commit.err" "commit mismatch"

echo "== source scanner rejects PII, credentials, and private workflow state =="
assert_contains "$ROOT/script/export-source-sale.sh" "  RELEASE_ARCHITECTURES"
SCAN="$TMP/scan"
mkdir -p "$SCAN"
printf 'safe source\n' >"$SCAN/safe.txt"
"$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only >/dev/null
printf '/Users/jane/private\n' >"$SCAN/personal.txt"
assert_fail personal-path "$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only
assert_contains "$TMP/personal-path.out" "personal home path"
rm "$SCAN/personal.txt"
mkdir -p "$SCAN/.planning"
printf 'private\n' >"$SCAN/.planning/state.md"
assert_fail planning-state "$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only
assert_contains "$TMP/planning-state.out" "forbidden private/build path"
rm -rf "$SCAN/.planning"
printf '%s\n' '-----BEGIN PRIVATE KEY-----' >"$SCAN/key.txt"
assert_fail private-key "$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only
assert_contains "$TMP/private-key.out" "credential-shaped value"

echo "source distribution script regression tests passed."
