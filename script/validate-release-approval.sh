#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"

APPROVAL=""
ARTIFACT=""
MANIFEST=""
UAT=""

usage() {
  echo "usage: script/validate-release-approval.sh --approval approval.json --artifact app.dmg --manifest manifest.json --uat evidence.json" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --approval) APPROVAL="${2:-}"; shift 2 ;;
    --artifact) ARTIFACT="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --uat) UAT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

for file in "$APPROVAL" "$ARTIFACT" "$MANIFEST" "$UAT"; do
  [[ -f "$file" ]] || { echo "release approval input missing: $file" >&2; exit 1; }
done

VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"
COMMIT="$(nmh_git_commit)"
TAG="v$VERSION"

/usr/bin/python3 - "$APPROVAL" "$ARTIFACT" "$MANIFEST" "$UAT" "$VERSION" "$BUNDLE_ID" "$COMMIT" "$TAG" <<'PY'
import hashlib
import json
import pathlib
import sys

approval_path, artifact_path, manifest_path, uat_path = map(pathlib.Path, sys.argv[1:5])
version, bundle_id, commit, tag = sys.argv[5:9]

def load(path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

approval = load(approval_path)
manifest = load(manifest_path)
uat = load(uat_path)

expected = {
    "schema_version": 1,
    "product": "Niko Music Hub",
    "release_approved": True,
    "version": version,
    "bundle_id": bundle_id,
    "tag": tag,
    "commit": commit,
    "artifact": artifact_path.name,
    "artifact_sha256": sha(artifact_path),
    "manifest": manifest_path.name,
    "manifest_sha256": sha(manifest_path),
}
for key, value in expected.items():
    if approval.get(key) != value:
        raise SystemExit(f"approval {key} mismatch: {approval.get(key)!r} != {value!r}")

if manifest.get("validation_status") != "passed":
    raise SystemExit("approval cannot reference a manifest that is not passed")

uat_record = approval.get("uat_evidence", {})
if uat_record.get("file") != uat_path.name or uat_record.get("sha256") != sha(uat_path):
    raise SystemExit("approval UAT evidence identity mismatch")
if uat_record.get("approved_by") != uat.get("approved_by") or uat_record.get("approved_at_utc") != uat.get("approved_at_utc"):
    raise SystemExit("approval UAT approver metadata mismatch")

release = approval.get("release_approval", {})
if not release.get("machine") or not release.get("created_utc"):
    raise SystemExit("approval requires machine and created_utc")

gates = approval.get("gates")
if not isinstance(gates, list) or len(gates) < 10:
    raise SystemExit("approval requires the complete release gate list")
results = {gate.get("result") for gate in gates}
if not results <= {"passed", "emergency-override"}:
    raise SystemExit(f"approval contains invalid gate results: {sorted(results)}")
for gate in gates:
    if not all(gate.get(field) for field in ("name", "command", "result", "completed_utc")):
        raise SystemExit("approval gate records require name, command, result, and completed_utc")
has_override = "emergency-override" in results
if bool(release.get("emergency_override")) != has_override:
    raise SystemExit("approval emergency_override flag does not match gate results")
if has_override and not release.get("emergency_reason"):
    raise SystemExit("approval emergency override requires a recorded reason")

print(f"release approval ok: version={version} commit={commit} gates={len(gates)} emergency_override={has_override}")
PY
