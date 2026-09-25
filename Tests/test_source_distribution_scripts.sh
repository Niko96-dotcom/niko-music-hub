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

echo "== owner attestation rejects lax types and placeholders =="
VALID_COPY="$TMP/approval-valid.json"
cp "$APPROVAL" "$VALID_COPY"
restore_approval() { cp "$VALID_COPY" "$APPROVAL"; }
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["schema_version"] = True
path.write_text(json.dumps(payload))
PY
assert_fail sale-schema-bool "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
assert_contains "$TMP/sale-schema-bool.err" "schema_version"
restore_approval
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["schema_version"] = "1"
path.write_text(json.dumps(payload))
PY
assert_fail sale-schema-string "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
assert_contains "$TMP/sale-schema-string.err" "schema_version"
restore_approval
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["schema_version"] = 1.0
path.write_text(json.dumps(payload))
PY
assert_fail sale-schema-float "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
assert_contains "$TMP/sale-schema-float.err" "schema_version"
restore_approval
for placeholder in "TODO" "TODO_REAL_NAME_REQUIRED" "TODO_ENTITY" "   " ""; do
  /usr/bin/python3 - "$APPROVAL" "$placeholder" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["approved_by"] = sys.argv[2]
path.write_text(json.dumps(payload))
PY
  assert_fail sale-placeholder-approver "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
  assert_contains "$TMP/sale-placeholder-approver.err" "real approved_by"
  restore_approval
  /usr/bin/python3 - "$APPROVAL" "$placeholder" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["legal_entity"] = sys.argv[2]
path.write_text(json.dumps(payload))
PY
  assert_fail sale-placeholder-entity "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
  assert_contains "$TMP/sale-placeholder-entity.err" "real legal_entity"
  restore_approval
done
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["approved_by"] = "REPLACE_WITH_SOMEONE"
path.write_text(json.dumps(payload))
PY
assert_fail sale-replace-approver "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
assert_contains "$TMP/sale-replace-approver.err" "real approved_by"
restore_approval
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["legal_entity"] = 12345
path.write_text(json.dumps(payload))
PY
assert_fail sale-entity-type "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
assert_contains "$TMP/sale-entity-type.err" "real legal_entity"
restore_approval
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["attestations"] = ["source_rights_transferable"]
path.write_text(json.dumps(payload))
PY
assert_fail sale-attestations-type "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
assert_contains "$TMP/sale-attestations-type.err" "attestations must be an object"
restore_approval
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["attestations"]["source_rights_transferable"] = 1
path.write_text(json.dumps(payload))
PY
assert_fail sale-attestation-int "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
assert_contains "$TMP/sale-attestation-int.err" "must be true"
restore_approval
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["attestations"]["source_rights_transferable"] = "true"
path.write_text(json.dumps(payload))
PY
assert_fail sale-attestation-string "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
assert_contains "$TMP/sale-attestation-string.err" "must be true"
restore_approval
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["approved_at_utc"] = "2026-13-99T99:99:99Z"
path.write_text(json.dumps(payload))
PY
assert_fail sale-bad-date "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
assert_contains "$TMP/sale-bad-date.err" "approved_at_utc"
restore_approval
"$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT" >/dev/null

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
