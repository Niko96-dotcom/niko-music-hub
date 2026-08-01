#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../script/release-env.sh
source "$ROOT/script/release-env.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nmh-release-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# These tests intentionally exercise the missing-credential fail-closed path.
# Keep them deterministic when the surrounding public release command has
# valid signing/notary/UAT credentials in its environment.
unset NMH_DEVELOPER_ID_APPLICATION NMH_NOTARY_PROFILE NMH_RELEASE_UAT_EVIDENCE

assert_fail() {
  local name="$1"
  shift
  if "$@" >"$TMP/$name.out" 2>"$TMP/$name.err"; then
    echo "expected failure but command passed: $name" >&2
    exit 1
  fi
}

assert_pass() {
  local name="$1"
  shift
  "$@" >"$TMP/$name.out" 2>"$TMP/$name.err"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "expected '$needle' in $file" >&2
    sed -n '1,120p' "$file" >&2
    exit 1
  fi
}

line_number() {
  local needle="$1"
  local file="$2"
  awk -v needle="$needle" 'index($0, needle) { print NR; exit }' "$file"
}

assert_order() {
  local first="$1"
  local second="$2"
  local file="$3"
  local first_line second_line
  first_line="$(line_number "$first" "$file")"
  second_line="$(line_number "$second" "$file")"
  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    echo "expected '$first' before '$second' in $file" >&2
    exit 1
  fi
}

echo "== release version verifier =="
assert_pass version-ok "$ROOT/script/release-version-verify.sh"
assert_fail stale-version "$ROOT/script/release-version-verify.sh" --previous-version 1.4
assert_contains "$TMP/stale-version.err" "previous version 1.4 appears outside allowlist"

echo "== permanent bundle identity =="
EXPECTED_BUNDLE_ID="$(tr -d '[:space:]' <"$ROOT/BUNDLE_ID")"
EXPECTED_MIN_MACOS="$(nmh_release_min_macos_version)"
EXPECTED_ARCHITECTURES="$(nmh_release_architectures)"
[[ "$EXPECTED_BUNDLE_ID" == "com.niko96.NikoMusicHub" ]] || {
  echo "unexpected canonical bundle identifier: $EXPECTED_BUNDLE_ID" >&2
  exit 1
}
assert_fail bundle-id-override env NMH_BUNDLE_ID=local.niko-music-hub.app bash -c "source '$ROOT/script/lib/app_lifecycle.sh'"
assert_contains "$TMP/bundle-id-override.err" "does not match canonical"

BUNDLE="$TMP/Test.app"
mkdir -p "$BUNDLE/Contents"
cat >"$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$EXPECTED_BUNDLE_ID</string>
  <key>CFBundleShortVersionString</key><string>$(cat "$ROOT/VERSION")</string>
  <key>NMHBuildID</key><string>$(cat "$ROOT/VERSION")+test</string>
  <key>LSMinimumSystemVersion</key><string>$EXPECTED_MIN_MACOS</string>
</dict></plist>
PLIST
assert_pass bundle-id-ok "$ROOT/script/release-version-verify.sh" --bundle "$BUNDLE"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.niko-music-hub.app' "$BUNDLE/Contents/Info.plist"
assert_fail bundle-id-placeholder "$ROOT/script/release-version-verify.sh" --bundle "$BUNDLE"
assert_contains "$TMP/bundle-id-placeholder.err" "release identity violation"

echo "== public-tree hygiene =="
assert_pass hygiene "$ROOT/script/public-tree-hygiene.sh"

echo "== checksum basename validation =="
CHECK_DIR="$TMP/checksum"
mkdir -p "$CHECK_DIR"
printf 'payload' >"$CHECK_DIR/NikoMusicHub-test.dmg"
(cd "$CHECK_DIR" && shasum -a 256 NikoMusicHub-test.dmg >NikoMusicHub-test.dmg.sha256)
if grep -q '/' "$CHECK_DIR/NikoMusicHub-test.dmg.sha256"; then
  echo "checksum file unexpectedly contains a path" >&2
  exit 1
fi

assert_order 'log "local gates"' 'run ci "$ROOT/script/ci.sh"' "$ROOT/script/release-all.sh"
assert_order 'run ci "$ROOT/script/ci.sh"' 'run e2e "$ROOT/script/e2e_user_smoke.sh"' "$ROOT/script/release-all.sh"
assert_contains "$ROOT/script/release-all.sh" 'run ci "$ROOT/script/ci.sh"'
assert_contains "$ROOT/script/release-all.sh" 'run e2e "$ROOT/script/e2e_user_smoke.sh"'
assert_contains "$ROOT/script/release-all.sh" 'run e2e env NMH_STRICT_UI_E2E=1 "$ROOT/script/e2e_user_smoke.sh"'

echo "== release command order stays fail-closed =="
assert_order 'log "build app bundle"' 'log "package dmg"' "$ROOT/script/release-all.sh"
assert_order 'log "package dmg"' 'log "checksums and manifest"' "$ROOT/script/release-all.sh"
assert_order 'log "checksums and manifest"' 'log "publication"' "$ROOT/script/release-all.sh"
assert_order 'run validate-artifact-final' 'run validate-approval' "$ROOT/script/release-all.sh"
assert_order 'run validate-approval' 'log "publication"' "$ROOT/script/release-all.sh"
assert_order 'log "public app signature validation"' 'log "checksums and manifest"' "$ROOT/script/release-all.sh"
assert_order 'run notary-dmg' 'log "checksums and manifest"' "$ROOT/script/release-all.sh"
assert_order 'run hdiutil-create' '(cd "$RELEASE_DIR" && shasum' "$ROOT/script/release-all.sh"
assert_contains "$ROOT/script/release-all.sh" 'nmh_validate_release_host_architecture'
assert_contains "$ROOT/script/release-all.sh" '--architectures "$RELEASE_ARCHITECTURES"'
assert_contains "$ROOT/script/release-all.sh" '--minimum-macos "$MIN_MACOS_VERSION"'
assert_contains "$ROOT/script/release-all.sh" '--artifact-size "$ARTIFACT_SIZE"'
assert_contains "$ROOT/script/validate-release-artifact.sh" 'lipo -archs "$BINARY"'

echo "== hardened runtime output variants are accepted =="
for script in "$ROOT/script/release-all.sh" "$ROOT/script/validate-release-artifact.sh"; do
  grep -Fq 'Runtime\ Version' "$script" || {
    echo "missing Runtime Version verifier in $script" >&2
    exit 1
  }
  grep -Fq 'flags=.*runtime' "$script" || {
    echo "missing runtime flags verifier in $script" >&2
    exit 1
  }
done

echo "== public mode rejects ordinary test skipping =="
assert_fail public-skip-tests "$ROOT/script/release-all.sh" --public --dry-run-publish --skip-tests
assert_contains "$TMP/public-skip-tests.err" "public release rejects --skip-tests"
assert_fail public-emergency-no-reason "$ROOT/script/release-all.sh" --public --dry-run-publish --emergency-skip-tests
assert_contains "$TMP/public-emergency-no-reason.err" "requires a non-empty --reason"

echo "== public mode fails closed without credentials =="
assert_fail public-missing-creds "$ROOT/script/release-all.sh" --public --dry-run-publish
assert_contains "$TMP/public-missing-creds.err" "NMH_DEVELOPER_ID_APPLICATION"

echo "== explicit local-only mode does not publish =="
assert_fail local-publish "$ROOT/script/release-all.sh" --local-only --publish --skip-tests
assert_contains "$TMP/local-publish.err" "local-only release cannot publish"

echo "== clean tagged checkout preflight =="
PREFLIGHT_REPO="$TMP/preflight-repo"
mkdir -p "$PREFLIGHT_REPO"
git -C "$PREFLIGHT_REPO" init -q
git -C "$PREFLIGHT_REPO" config user.name "Release Test"
git -C "$PREFLIGHT_REPO" config user.email "release-test@example.invalid"
printf '%s\n' "$(cat "$ROOT/VERSION")" >"$PREFLIGHT_REPO/VERSION"
git -C "$PREFLIGHT_REPO" add VERSION
git -C "$PREFLIGHT_REPO" commit -qm initial
git -C "$PREFLIGHT_REPO" tag "v$(cat "$ROOT/VERSION")"
assert_pass preflight-clean "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO"
printf 'dirty\n' >"$PREFLIGHT_REPO/untracked.txt"
assert_fail preflight-dirty "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO"
assert_contains "$TMP/preflight-dirty.err" "completely clean working tree"

echo "== consolidated exact-commit UAT evidence =="
UAT="$TMP/uat.json"
CURRENT_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
cat >"$UAT" <<JSON
{
  "schema_version": 1,
  "version": "$(cat "$ROOT/VERSION")",
  "commit": "$CURRENT_COMMIT",
  "bundle_id": "$EXPECTED_BUNDLE_ID",
  "status": "approved",
  "approved_by": "Release Test",
  "approved_at_utc": "2026-07-13T12:00:00Z",
  "machine": "arm64 macOS test machine",
  "checks": {
    "clean_install": "passed",
    "upgrade_preserves_settings": "passed",
    "uninstall": "passed",
    "launch_at_login": "passed",
    "privacy_permissions": "passed",
    "recorder_real_audio": "passed",
    "downloader_live": "passed",
    "archive_read_only": "passed",
    "output_handoffs": "passed",
    "e2e_user_smoke": "passed"
  }
}
JSON
assert_pass uat-valid "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["checks"]["privacy_permissions"] = "pending"
path.write_text(json.dumps(payload))
PY
assert_fail uat-pending "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-pending.err" "privacy_permissions"

echo "== approval record binds exact artifact, manifest, UAT, and gates =="
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["checks"]["privacy_permissions"] = "passed"
path.write_text(json.dumps(payload))
PY
APPROVAL_ARTIFACT="$TMP/NikoMusicHub-$(cat "$ROOT/VERSION").dmg"
printf 'release-artifact-test\n' >"$APPROVAL_ARTIFACT"
APPROVAL_ARTIFACT_SHA="$(shasum -a 256 "$APPROVAL_ARTIFACT" | awk '{print $1}')"
APPROVAL_MANIFEST="$TMP/NikoMusicHub-$(cat "$ROOT/VERSION")-manifest.json"
"$ROOT/script/generate-release-record.py" manifest \
  --output "$APPROVAL_MANIFEST" \
  --version "$(cat "$ROOT/VERSION")" \
  --bundle-id "$EXPECTED_BUNDLE_ID" \
  --tag "v$(cat "$ROOT/VERSION")" \
  --commit "$CURRENT_COMMIT" \
  --build-id "$(cat "$ROOT/VERSION")+test" \
  --build-number 1 \
  --architectures "$EXPECTED_ARCHITECTURES" \
  --minimum-macos "$EXPECTED_MIN_MACOS" \
  --artifact "$(basename "$APPROVAL_ARTIFACT")" \
  --artifact-size "$(stat -f%z "$APPROVAL_ARTIFACT")" \
  --artifact-sha256 "$APPROVAL_ARTIFACT_SHA" \
  --created-utc 2026-07-13T12:00:00Z \
  --signing-identity "Developer ID Application: Release Test (TEAM)" \
  --validation-status passed \
  --public-release
APPROVAL_MANIFEST_SHA="$(shasum -a 256 "$APPROVAL_MANIFEST" | awk '{print $1}')"
UAT_SHA="$(shasum -a 256 "$UAT" | awk '{print $1}')"
APPROVAL="$TMP/NikoMusicHub-$(cat "$ROOT/VERSION")-release-approval.json"
APPROVAL_ARGS=(
  approval
  --output "$APPROVAL"
  --version "$(cat "$ROOT/VERSION")"
  --bundle-id "$EXPECTED_BUNDLE_ID"
  --tag "v$(cat "$ROOT/VERSION")"
  --commit "$CURRENT_COMMIT"
  --artifact "$(basename "$APPROVAL_ARTIFACT")"
  --artifact-sha256 "$APPROVAL_ARTIFACT_SHA"
  --manifest "$(basename "$APPROVAL_MANIFEST")"
  --manifest-sha256 "$APPROVAL_MANIFEST_SHA"
  --machine "arm64 macOS test machine"
  --created-utc 2026-07-13T12:00:00Z
  --uat-file "$(basename "$UAT")"
  --uat-sha256 "$UAT_SHA"
  --uat-approved-by "Release Test"
  --uat-approved-at-utc 2026-07-13T12:00:00Z
)
for gate in {1..10}; do
  APPROVAL_ARGS+=(--gate "gate-$gate|command-$gate|passed|2026-07-13T12:00:00Z")
done
"$ROOT/script/generate-release-record.py" "${APPROVAL_ARGS[@]}"
assert_pass approval-valid "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
printf 'tampered\n' >>"$APPROVAL_ARTIFACT"
assert_fail approval-tampered "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-tampered.err" "artifact_sha256 mismatch"

echo "== release notes are current-section only =="
NOTES="$TMP/release-notes.md"
assert_pass release-notes "$ROOT/script/extract-release-notes.sh" "$NOTES"
assert_contains "$NOTES" "fail-closed local release engineering"
if grep -Fq '# Changelog' "$NOTES"; then
  echo "release notes unexpectedly contain the whole changelog" >&2
  exit 1
fi

echo "release script regression tests passed."
