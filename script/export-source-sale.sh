#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"

OUTPUT_DIR="${NMH_SOURCE_EXPORT_DIR:-$ROOT/dist/source-sale}"
APPROVAL=""
CANDIDATE=false

usage() {
  cat >&2 <<'USAGE'
usage:
  script/export-source-sale.sh --approval /path/to/approved.json [--output-dir path]
  script/export-source-sale.sh --candidate [--output-dir path]

An approved export is sale-labeled and requires an exact-commit owner/rightsholder
attestation. Candidate mode proves the technical export but is marked NOT FOR SALE.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --approval) APPROVAL="${2:-}"; shift 2 ;;
    --candidate) CANDIDATE=true; shift ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

if [[ "$CANDIDATE" == true && -n "$APPROVAL" ]] || [[ "$CANDIDATE" != true && -z "$APPROVAL" ]]; then
  usage
  exit 2
fi
if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
  echo "source export requires no tracked or staged changes; it exports exact HEAD" >&2
  exit 1
fi

VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"
COMMIT="$(nmh_git_commit)"
SHORT_COMMIT="$(nmh_git_short_commit)"
MODE="approved"
LABEL="NikoMusicHub-source-$VERSION-$SHORT_COMMIT"
if [[ "$CANDIDATE" == true ]]; then
  MODE="candidate-not-for-sale"
  LABEL="$LABEL-CANDIDATE-NOT-FOR-SALE"
else
  "$ROOT/script/validate-source-sale-approval.py" --approval "$APPROVAL" --commit "$COMMIT"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/nmh-source-sale.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
TREE="$TMP/$LABEL"
mkdir -p "$TREE" "$OUTPUT_DIR"

EXPORT_PATHS=(
  .gitignore
  BUNDLE_ID
  CHANGELOG.md
  CONTRIBUTING.md
  LICENSE
  Package.swift
  README.md
  RELEASE_ARCHITECTURES
  Resources
  SBOM.spdx.json
  SOURCE_PROVENANCE.md
  Sources
  THIRD_PARTY_NOTICES.md
  Tests
  VERSION
  Fixtures
  docs/install.md
  docs/local-dev-flow.md
  docs/menu-bar-quick-access.md
  docs/release-checklist.md
  docs/release-uat-evidence.template.json
  docs/release-validation.md
  docs/release.md
  docs/source-sale-approval.template.json
  docs/source-sale.md
  docs/user-e2e.md
  docs/user-guide-stem-separation.md
  script/build_and_run.sh
  script/capture_window_proof.sh
  script/ci-release.sh
  script/ci-tsan.sh
  script/ci.sh
  script/dev.sh
  script/downloader_live_smoke.sh
  script/e2e_user_smoke.sh
  script/export-source-sale.sh
  script/extract-release-notes.sh
  script/fixtures
  script/generate-release-record.py
  script/lib
  script/live_smoke_stem_separation.sh
  script/public-tree-hygiene.sh
  script/release-all.sh
  script/release-env.sh
  script/release-preflight.sh
  script/release-version-verify.sh
  script/ui_probe.swift
  script/validate-release-approval.sh
  script/validate-release-artifact.sh
  script/validate-release-uat.sh
  script/validate-source-sale-approval.py
  script/verify-installed-release.sh
  script/verify-source-distribution.py
)

git -C "$ROOT" archive --format=tar HEAD -- "${EXPORT_PATHS[@]}" | tar -xf - -C "$TREE"

APPROVAL_SHA=""
if [[ "$CANDIDATE" == true ]]; then
  printf '%s\n' \
    '# Source Sale Approval Required' \
    '' \
    'This is a technically verified candidate export, not an approved sale package.' \
    'Create and validate an exact-commit owner attestation from docs/source-sale-approval.template.json, then rerun without --candidate.' \
    >"$TREE/SOURCE_SALE_APPROVAL_REQUIRED.md"
else
  cp "$APPROVAL" "$TREE/SOURCE_SALE_APPROVAL.json"
  APPROVAL_SHA="$(shasum -a 256 "$TREE/SOURCE_SALE_APPROVAL.json" | awk '{print $1}')"
fi

/usr/bin/python3 - "$TREE" "$VERSION" "$BUNDLE_ID" "$COMMIT" "$MODE" "$APPROVAL_SHA" <<'PY'
import hashlib
import json
import pathlib
import sys

tree = pathlib.Path(sys.argv[1])
version, bundle_id, commit, mode, approval_sha = sys.argv[2:]

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

files = {
    str(path.relative_to(tree)): sha(path)
    for path in sorted(tree.rglob("*"))
    if path.is_file() and path.name != "SOURCE_EXPORT_MANIFEST.json"
}
payload = {
    "schema_version": 1,
    "product": "Niko Music Hub",
    "sale_status": mode,
    "version": version,
    "bundle_id": bundle_id,
    "source_commit": commit,
    "source_sale_approval_sha256": approval_sha or None,
    "files_sha256": files,
    "excluded_categories": [
        "AI and agent workflow state",
        "planning and milestone history",
        "development-only vendored tooling",
        "private UAT logs and machine-specific evidence",
        "build outputs and credentials",
        "internal product research and reference projects",
    ],
}
(tree / "SOURCE_EXPORT_MANIFEST.json").write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY

VERIFY_ARGS=(--tree "$TREE")
if [[ "$CANDIDATE" == true ]]; then VERIFY_ARGS+=(--candidate); fi
"$ROOT/script/verify-source-distribution.py" "${VERIFY_ARGS[@]}"
(cd "$TREE" && swift package dump-package >/dev/null)

ARCHIVE="$OUTPUT_DIR/$LABEL.tar.gz"
rm -f "$ARCHIVE" "$ARCHIVE.sha256"
COPYFILE_DISABLE=1 tar -czf "$ARCHIVE" -C "$TMP" "$LABEL"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ARCHIVE")" >"$(basename "$ARCHIVE").sha256")

echo "source export complete: mode=$MODE commit=$COMMIT"
echo "archive: $ARCHIVE"
echo "checksum: $ARCHIVE.sha256"
