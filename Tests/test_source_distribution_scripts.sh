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

echo "== export flags that take a value reject a missing, empty, or flag value =="
assert_fail export-approval-missing-value "$ROOT/script/export-source-sale.sh" --approval
assert_contains "$TMP/export-approval-missing-value.err" "--approval requires a value"
assert_contains "$TMP/export-approval-missing-value.err" "usage:"
assert_fail export-output-dir-flag-value "$ROOT/script/export-source-sale.sh" --output-dir --approval "$APPROVAL"
assert_contains "$TMP/export-output-dir-flag-value.err" "--output-dir requires a value"
assert_fail export-output-dir-empty "$ROOT/script/export-source-sale.sh" --candidate --output-dir ""
assert_contains "$TMP/export-output-dir-empty.err" "--output-dir requires a value"

echo "== source scanner rejects PII, credentials, and private workflow state =="
assert_contains "$ROOT/script/export-source-sale.sh" "  RELEASE_ARCHITECTURES"
# Exported tests and release scripts read these files, so the buyer tree must ship them.
for exported_dependency in Package.resolved SPARKLE_PUBLIC_ED_KEY script/install-local.sh \
  script/local-build-identity.sh script/validate-update-feed.py; do
  grep -Fxq "  $exported_dependency" "$ROOT/script/export-source-sale.sh" || {
    echo "expected '$exported_dependency' in EXPORT_PATHS" >&2
    exit 1
  }
done
# Every repo script that an exported test names must be exported too, or the buyer's CI fails.
/usr/bin/python3 - "$ROOT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
text = (root / "script/export-source-sale.sh").read_text(encoding="utf-8")
block = re.search(r"^EXPORT_PATHS=\(\n(.*?)^\)", text, re.S | re.M).group(1)
exported = [line.strip() for line in block.splitlines() if line.strip()]
# Named only in a comment; no exported test reads it.
comment_only = {"script/performance/vault-recovery.swift"}
def covered(rel):
    return any(rel == path or rel.startswith(path + "/") for path in exported)
missing = set()
for test in (root / "Tests").rglob("*"):
    if not test.is_file():
        continue
    body = test.read_text(encoding="utf-8", errors="replace")
    for rel in re.findall(r"script/[A-Za-z0-9_./-]*[A-Za-z0-9_]", body):
        if rel not in comment_only and (root / rel).exists() and not covered(rel):
            missing.add(f"{rel} (named in {test.relative_to(root)})")
if missing:
    print("exported tests need files that EXPORT_PATHS leaves out:", *sorted(missing), sep="\n  ", file=sys.stderr)
    sys.exit(1)
PY
SCAN="$TMP/scan"
mkdir -p "$SCAN"
printf 'safe source\n' >"$SCAN/safe.txt"
"$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only >/dev/null
printf '/Users/jane/private\n' >"$SCAN/personal.txt"
assert_fail personal-path "$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only
assert_contains "$TMP/personal-path.out" "personal home path"
rm "$SCAN/personal.txt"
printf '/Users/user/x\n' >"$SCAN/placeholder.txt"
"$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only >/dev/null
rm "$SCAN/placeholder.txt"
printf '/Users/test.jane/private\n' >"$SCAN/personal.txt"
assert_fail personal-path-prefixed "$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only
assert_contains "$TMP/personal-path-prefixed.out" "personal home path"
rm "$SCAN/personal.txt"
printf 'RIFF\377\376\000/Users/jane/Media/take.wav\000' >"$SCAN/project.cpr"
assert_fail personal-path-binary "$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only
assert_contains "$TMP/personal-path-binary.out" "project.cpr: contains personal home path"
rm "$SCAN/project.cpr"
mkdir -p "$SCAN/.planning"
printf 'private\n' >"$SCAN/.planning/state.md"
assert_fail planning-state "$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only
assert_contains "$TMP/planning-state.out" "forbidden private/build path"
rm -rf "$SCAN/.planning"
mkdir -p "$SCAN/Sources"
printf 'NOTARY_PASSWORD=x\n' >"$SCAN/Sources/.env"
assert_fail dotenv "$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only
assert_contains "$TMP/dotenv.out" "Sources/.env: forbidden file type"
mv "$SCAN/Sources/.env" "$SCAN/Sources/.env.local"
assert_fail dotenv-local "$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only
assert_contains "$TMP/dotenv-local.out" "Sources/.env.local: forbidden file type"
rm -rf "$SCAN/Sources"
printf '%s\n' '-----BEGIN PRIVATE KEY-----' >"$SCAN/key.txt"
assert_fail private-key "$ROOT/script/verify-source-distribution.py" --tree "$SCAN" --scan-only
assert_contains "$TMP/private-key.out" "credential-shaped value"

echo "source distribution script regression tests passed."
