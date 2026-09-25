#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"
# shellcheck source=lib/release_gates.sh
source "$ROOT/script/lib/release_gates.sh"

APPROVAL=""
ARTIFACT=""
MANIFEST=""
UAT=""
EXPECTED_COMMIT_OVERRIDE=""
EXPECTED_SIGNING_IDENTITY="${NMH_DEVELOPER_ID_APPLICATION:-}"
EXPECTED_BUILD_ID_OVERRIDE=""

usage() {
  echo "usage: script/validate-release-approval.sh --approval approval.json --artifact app.dmg --manifest manifest.json --uat evidence.json [--commit git-sha] [--expected-signing-identity 'Developer ID Application: ...'] [--expected-build-id VERSION+SHORT]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --approval) APPROVAL="${2:-}"; shift 2 ;;
    --artifact) ARTIFACT="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --uat) UAT="${2:-}"; shift 2 ;;
    --commit) EXPECTED_COMMIT_OVERRIDE="${2:-}"; shift 2 ;;
    --expected-signing-identity) EXPECTED_SIGNING_IDENTITY="${2:-}"; shift 2 ;;
    --expected-build-id) EXPECTED_BUILD_ID_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

for file in "$APPROVAL" "$ARTIFACT" "$MANIFEST" "$UAT"; do
  [[ -f "$file" ]] || { echo "release approval input missing: $file" >&2; exit 1; }
done

VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"
if [[ -n "$EXPECTED_COMMIT_OVERRIDE" ]]; then
  COMMIT="$EXPECTED_COMMIT_OVERRIDE"
else
  COMMIT="$(nmh_git_commit)"
fi
TAG="v$VERSION"
# Resolve --commit to its canonical full SHA, verifying it is an actual commit
# object (not blob/tree/missing). Rejects unknown objects before evidence.
COMMIT="$(nmh_resolve_commit "$COMMIT")" || exit 1
EXPECTED_SHORT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 --verify --end-of-options "$COMMIT" 2>/dev/null)" || {
  echo "unknown commit object: $COMMIT" >&2
  exit 1
}
CANONICAL_BUILD_ID="$VERSION+$EXPECTED_SHORT_COMMIT"
if [[ -n "$EXPECTED_BUILD_ID_OVERRIDE" ]]; then
  [[ "$EXPECTED_BUILD_ID_OVERRIDE" == "$CANONICAL_BUILD_ID" ]] || { echo "explicit --expected-build-id '$EXPECTED_BUILD_ID_OVERRIDE' does not match canonical $CANONICAL_BUILD_ID for commit $COMMIT" >&2; exit 1; }
fi
EXPECTED_BUILD_ID="$CANONICAL_BUILD_ID"
if [[ -n "$EXPECTED_SIGNING_IDENTITY" ]]; then
  [[ "$EXPECTED_SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { echo "explicit --expected-signing-identity must be a Developer ID Application identity (was '$EXPECTED_SIGNING_IDENTITY')" >&2; exit 1; }
fi

# Single source of truth for gates/checks: join the shared contract arrays and
# hand them to the python validator so names cannot drift between bash and
# python. Join with commas (names contain only [a-z0-9_-]).
REQUIRED_GATES_CSV="$(IFS=,; printf '%s' "${NMH_REQUIRED_RELEASE_GATES[*]}")"
OVERRIDABLE_GATES_CSV="$(IFS=,; printf '%s' "${NMH_EMERGENCY_OVERRIDABLE_GATES[*]}")"
REQUIRED_CHECKS_CSV="$(IFS=,; printf '%s' "${NMH_REQUIRED_UAT_CHECKS[*]}")"

/usr/bin/python3 - "$APPROVAL" "$ARTIFACT" "$MANIFEST" "$UAT" "$VERSION" "$BUNDLE_ID" "$COMMIT" "$TAG" "$EXPECTED_BUILD_ID" "${EXPECTED_SIGNING_IDENTITY:-}" "$REQUIRED_GATES_CSV" "$OVERRIDABLE_GATES_CSV" "$REQUIRED_CHECKS_CSV" "$ROOT/script/lib" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

approval_path, artifact_path, manifest_path, uat_path = map(pathlib.Path, sys.argv[1:5])
version, bundle_id, commit, tag = sys.argv[5:9]
expected_build_id, expected_signing_identity = sys.argv[9:11]
required_gates = [g for g in sys.argv[11].split(",") if g]
overridable_gates = set(g for g in sys.argv[12].split(",") if g)
required_checks = [c for c in sys.argv[13].split(",") if c]
sys.path.insert(0, sys.argv[14])
import release_uat

TIMESTAMP_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")

def load_bytes(path):
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise SystemExit(f"cannot read {path}: {error}")
    try:
        return raw, json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"could not parse {path}: {error}")

def sha_bytes(raw):
    return hashlib.sha256(raw).hexdigest()

def sha_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

# Read each JSON record once: the sha is computed over the exact bytes that are
# then semantically validated, so a file swapped between hashing and validation
# cannot pass (same-bytes TOCTOU fix for R2).
approval_raw, approval = load_bytes(approval_path)
manifest_raw, manifest = load_bytes(manifest_path)
uat_raw, uat = load_bytes(uat_path)

# Strict types (no coercion): schema_version must be exact int 1
# (type is int; rejects True and 1.0 since True == 1 and 1.0 == 1),
# release_approved must be `is True` (rejects 1, 1.0, "true").
approval_schema = approval.get("schema_version")
if type(approval_schema) is not int or approval_schema != 1:
    raise SystemExit(f"approval schema_version mismatch: {approval_schema!r} != 1")
if approval.get("release_approved") is not True:
    raise SystemExit(f"approval release_approved mismatch: {approval.get('release_approved')!r} != True")
expected = {
    "product": "Niko Music Hub",
    "version": version,
    "bundle_id": bundle_id,
    "tag": tag,
    "commit": commit,
    "artifact": artifact_path.name,
    "artifact_sha256": sha_file(artifact_path),
    "manifest": manifest_path.name,
    "manifest_sha256": sha_bytes(manifest_raw),
}
for key, value in expected.items():
    if approval.get(key) != value:
        raise SystemExit(f"approval {key} mismatch: {approval.get(key)!r} != {value!r}")

if manifest.get("validation_status") != "passed":
    raise SystemExit("approval cannot reference a manifest that is not passed")

# Manifest must describe the same intended candidate: exact commit, version,
# bundle, tag, and build id, plus the intended signing identity. It must also
# bind the supplied artifact file (basename and hash): without this, an
# approval could hash one manifest while the manifest describes a different
# artifact than the file on disk.
for key, value in (("version", version), ("bundle_id", bundle_id), ("commit", commit), ("tag", tag)):
    if manifest.get(key) != value:
        raise SystemExit(f"manifest {key} mismatch: {manifest.get(key)!r} != {value!r}")
if manifest.get("build_id") != expected_build_id:
    raise SystemExit(
        f"manifest build_id mismatch: {manifest.get('build_id')!r} != {expected_build_id!r} "
        "(stale build for another commit)"
    )
if manifest.get("artifact") != artifact_path.name:
    raise SystemExit(
        f"manifest artifact mismatch: {manifest.get('artifact')!r} != {artifact_path.name!r} "
        "(manifest must describe the supplied artifact file)"
    )
if manifest.get("artifact_sha256") != sha_file(artifact_path):
    raise SystemExit(
        f"manifest artifact_sha256 mismatch: {manifest.get('artifact_sha256')!r} != "
        f"{sha_file(artifact_path)!r} (manifest must bind the supplied artifact bytes)"
    )
manifest_signing = manifest.get("signing", {}) if isinstance(manifest.get("signing"), dict) else {}
manifest_identity = manifest_signing.get("identity")
if expected_signing_identity:
    if not expected_signing_identity.startswith("Developer ID Application:"):
        raise SystemExit(
            f"explicit --expected-signing-identity must be a Developer ID Application identity (was {expected_signing_identity!r})"
        )
    if not isinstance(manifest_identity, str) or not manifest_identity.startswith("Developer ID Application:"):
        raise SystemExit(
            f"manifest must record a Developer ID signing identity (was {manifest_identity!r})"
        )
    if manifest_identity != expected_signing_identity:
        raise SystemExit(
            f"manifest signing.identity mismatch: {manifest_identity!r} != {expected_signing_identity!r}"
        )
else:
    if not isinstance(manifest_identity, str) or not manifest_identity.startswith("Developer ID Application:"):
        raise SystemExit(
            f"manifest must record a Developer ID signing identity (was {manifest_identity!r})"
        )

# UAT evidence identity: the sha is over the same bytes parsed above.
uat_record = approval.get("uat_evidence", {})
if uat_record.get("file") != uat_path.name or uat_record.get("sha256") != sha_bytes(uat_raw):
    raise SystemExit("approval UAT evidence identity mismatch")
if uat_record.get("approved_by") != uat.get("approved_by") or uat_record.get("approved_at_utc") != uat.get("approved_at_utc"):
    raise SystemExit("approval UAT approver metadata mismatch")

# Full UAT semantics on the SAME bytes that were hashed (R2 fix), through the
# shared script/lib/release_uat.py helper so the standalone and final
# validators cannot drift (strict types, placeholder/blank rejection, exact
# checks). The final validator must not trust the approval's hash while waving
# through a UAT file whose status, commit, checks, build, or signing would fail
# the UAT validator.
release_uat.validate_uat(
    uat,
    version,
    bundle_id,
    commit,
    expected_build_id,
    expected_signing_identity,
    required_checks,
)
# Signing consistency: the tested UAT build and the manifest candidate must be
# the same signing team. A UAT run on one team's build says nothing about a
# candidate signed by another team.
tested = uat.get("tested_build", {})
tested_signing = tested.get("signing_identity") if isinstance(tested, dict) else None
if tested_signing != manifest_identity:
    raise SystemExit(
        f"UAT signing identity {tested_signing!r} does not match manifest signing identity {manifest_identity!r} "
        "(different signing team)"
    )

release = approval.get("release_approval", {})
if not release.get("machine") or not release.get("created_utc"):
    raise SystemExit("approval requires machine and created_utc")

# Exact required gate set (R3 fix): no duplicates, no missing, no unknown.
# Emergency overrides are allowed only for the narrow overridable subset.
gates = approval.get("gates")
if not isinstance(gates, list) or not gates:
    raise SystemExit("approval requires the complete release gate list")
names = [gate.get("name") if isinstance(gate, dict) else None for gate in gates]
if len(names) != len(set(names)):
    raise SystemExit(f"approval gate list contains duplicates: {sorted(n for n in names if n)}")
if set(names) != set(required_gates):
    raise SystemExit(
        f"approval gate list must be exactly {sorted(required_gates)!r}: "
        f"missing={sorted(set(required_gates) - set(names))!r} "
        f"unknown={sorted(set(names) - set(required_gates))!r}"
    )
results = {gate.get("result") for gate in gates if isinstance(gate, dict)}
if not results <= {"passed", "emergency-override"}:
    raise SystemExit(f"approval contains invalid gate results: {sorted(r for r in results if r)}")
for gate in gates:
    if not isinstance(gate, dict) or not all(gate.get(field) for field in ("name", "command", "result", "completed_utc")):
        raise SystemExit("approval gate records require name, command, result, and completed_utc")
    completed = gate.get("completed_utc")
    if not isinstance(completed, str) or not TIMESTAMP_RE.match(completed):
        raise SystemExit(
            f"approval gate {gate.get('name')!r} completed_utc must be ISO-8601 UTC (was {completed!r})"
        )
    if gate.get("result") == "emergency-override" and gate.get("name") not in overridable_gates:
        raise SystemExit(
            f"approval gate {gate.get('name')!r} is not emergency-overridable "
            f"(overridable: {sorted(overridable_gates)!r})"
        )
has_override = "emergency-override" in results
# Strict boolean: emergency_override must be exactly True/False (is-checks;
# 1/0 and "true" must not coerce via bool()).
_emergency_override = release.get("emergency_override")
if _emergency_override is True:
    _emergency_flag = True
elif _emergency_override is False:
    _emergency_flag = False
else:
    raise SystemExit(f"approval emergency_override must be boolean True/False (was {_emergency_override!r})")
if _emergency_flag != has_override:
    raise SystemExit("approval emergency_override flag does not match gate results")
if has_override and not release.get("emergency_reason"):
    raise SystemExit("approval emergency override requires a recorded reason")

print(f"release approval ok: version={version} commit={commit} build_id={expected_build_id} gates={len(gates)} emergency_override={has_override}")
PY
