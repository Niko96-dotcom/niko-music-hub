#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../script/release-env.sh
source "$ROOT/script/release-env.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nmh-release-tests.XXXXXX")"
DIRTY_PROBE="$ROOT/release-script-dirty-probe-$$.txt"
trap 'rm -rf "$TMP"; rm -f "$DIRTY_PROBE"' EXIT

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

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "did not expect '$needle' in $file" >&2
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
assert_fail derived-output-override env NMH_APP_BUNDLE="$TMP/unsafe.app" bash -c "source '$ROOT/script/lib/app_lifecycle.sh'"
assert_contains "$TMP/derived-output-override.err" "derived from NMH_DIST_DIR"
assert_fail output-outside-repo env NMH_DIST_DIR="$TMP/outside" bash -c "source '$ROOT/script/lib/app_lifecycle.sh'"
assert_contains "$TMP/output-outside-repo.err" "output directory must stay beneath"
assert_pass lifecycle-missing-target bash -c "source '$ROOT/script/lib/app_lifecycle.sh'; nmh_stop_app_binary '$TMP/Missing.app/Contents/MacOS/NikoMusicHub' true"
assert_fail lifecycle-relative-target bash -c "source '$ROOT/script/lib/app_lifecycle.sh'; nmh_stop_app_binary 'relative/NikoMusicHub' true"
assert_contains "$TMP/lifecycle-relative-target.err" "app binary path must be absolute"

echo "== isolated startup control flow =="
# Exercise the real entrypoint with lifecycle doubles; no GUI or real settings.
STARTUP_REPO="$TMP/startup-repo"
mkdir -p "$STARTUP_REPO/script/lib"
cp "$ROOT/script/build_and_run.sh" "$STARTUP_REPO/script/build_and_run.sh"
cat >"$STARTUP_REPO/script/lib/app_lifecycle.sh" <<'SH'
NMH_ROOT_DIR="$ROOT_DIR"
NMH_APP_BINARY="$NMH_DIST_DIR/NikoMusicHub.app/Contents/MacOS/NikoMusicHub"
nmh_stop_app() { echo stop >>"$NMH_STARTUP_TEST_EVENTS"; }
nmh_build_bundle() { echo build >>"$NMH_STARTUP_TEST_EVENTS"; }
# Cleanup must forget the throwaway suite only after the app is stopped.
nmh_forget_settings_suite() {
  [[ "$1" == NikoMusicHubStartup.* ]]
  echo forget >>"$NMH_STARTUP_TEST_EVENTS"
}
nmh_open_app() {
  [[ "$NIKO_MUSIC_HUB_SETTINGS_SUITE" == NikoMusicHubStartup.* ]]
  [[ "$NIKO_MUSIC_HUB_DRY_RUN_OPEN" == 1 ]]
  [[ -z "${NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT+x}" ]]
  [[ -z "${NIKO_MUSIC_HUB_BOOKMARK_PROOF_MODE+x}" ]]
  [[ "$NMH_DIST_DIR" == "$ROOT_DIR/dist/verification" ]]
  [[ "$*" == *--stdout* && "$*" == *--stderr* ]]
  echo open >>"$NMH_STARTUP_TEST_EVENTS"
  return "${NMH_STARTUP_TEST_OPEN_STATUS:-0}"
}
nmh_running_dist_app_pids() { echo 12345; }
nmh_ui_probe() {
  [[ "$*" == *'--pid 12345 --binary-path '* ]]
  return "${NMH_STARTUP_TEST_PROBE_STATUS:-0}"
}
SH
STARTUP_EVENTS="$TMP/startup-events"
assert_pass isolated-startup env NMH_STARTUP_TEST_EVENTS="$STARTUP_EVENTS" \
  NIKO_MUSIC_HUB_SETTINGS_SUITE=must-not-reuse \
  NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT=/must-not-scan \
  NIKO_MUSIC_HUB_BOOKMARK_PROOF_MODE=must-not-run \
  bash "$STARTUP_REPO/script/build_and_run.sh" --verify-isolated
[[ "$(cat "$STARTUP_EVENTS")" == $'stop\nbuild\nopen\nstop\nforget' ]]
assert_contains "$TMP/isolated-startup.out" 'verify ok: isolated visible main window'

: >"$STARTUP_EVENTS"
assert_fail isolated-no-window-api env NMH_STARTUP_TEST_EVENTS="$STARTUP_EVENTS" \
  NMH_STARTUP_TEST_PROBE_STATUS=2 bash "$STARTUP_REPO/script/build_and_run.sh" --verify-isolated
assert_contains "$TMP/isolated-no-window-api.err" 'no verified visible window'
[[ "$(tail -n 2 "$STARTUP_EVENTS" | tr '\n' ' ')" == "stop forget " ]]

: >"$STARTUP_EVENTS"
assert_fail isolated-open-fails env NMH_STARTUP_TEST_EVENTS="$STARTUP_EVENTS" \
  NMH_STARTUP_TEST_OPEN_STATUS=8 bash "$STARTUP_REPO/script/build_and_run.sh" --verify-isolated
[[ "$(tail -n 2 "$STARTUP_EVENTS" | tr '\n' ' ')" == "stop forget " ]]

: >"$STARTUP_EVENTS"
assert_fail startup-invalid-mode env NMH_STARTUP_TEST_EVENTS="$STARTUP_EVENTS" \
  bash "$STARTUP_REPO/script/build_and_run.sh" --not-a-mode
[[ ! -s "$STARTUP_EVENTS" ]] # Invalid commands must not stop or rebuild an app.

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
PUBLIC_TREE="$TMP/public-tree"
mkdir -p "$PUBLIC_TREE/script" "$PUBLIC_TREE/.planning" "$PUBLIC_TREE/docs"
cp "$ROOT/script/public-tree-hygiene.sh" "$PUBLIC_TREE/script/public-tree-hygiene.sh"
chmod +x "$PUBLIC_TREE/script/public-tree-hygiene.sh"
git -C "$PUBLIC_TREE" init -q
git -C "$PUBLIC_TREE" config user.name "Release Test"
git -C "$PUBLIC_TREE" config user.email "release-test@example.invalid"
printf 'local proof: /Users/private-user/Music/project.cpr\n' >"$PUBLIC_TREE/docs/uat.md"
printf 'private planning state\n' >"$PUBLIC_TREE/.planning/STATE.md"
git -C "$PUBLIC_TREE" add .planning/STATE.md docs/uat.md
git -C "$PUBLIC_TREE" commit -qm initial
assert_fail hygiene-public-private-state "$PUBLIC_TREE/script/public-tree-hygiene.sh" --public-release
assert_contains "$TMP/hygiene-public-private-state.err" "private planning or agent state"
assert_contains "$TMP/hygiene-public-private-state.err" "real home-directory path"

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
assert_contains "$ROOT/script/release-all.sh" 'run hygiene "$ROOT/script/public-tree-hygiene.sh" --public-release'
assert_contains "$ROOT/script/release-all.sh" 'require_clean_release_worktree'
assert_contains "$ROOT/script/release-all.sh" 'use ./script/dev.sh run for dirty local development builds'

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
assert_contains "$ROOT/script/lib/app_lifecycle.sh" 'NMH_BUILD_CONFIGURATION="${NMH_BUILD_CONFIGURATION:-debug}"'
assert_contains "$ROOT/script/lib/app_lifecycle.sh" 'swift build -c "$NMH_BUILD_CONFIGURATION" --product "$NMH_APP_NAME"'
assert_contains "$ROOT/script/lib/app_lifecycle.sh" 'nmh_running_dist_app_pids'
assert_contains "$ROOT/script/lib/app_lifecycle.sh" 'nmh_stop_app_binary()'
assert_contains "$ROOT/script/lib/app_lifecycle.sh" 'refusing to signal unrelated installed copies'
assert_contains "$ROOT/script/release-all.sh" 'RELEASE_BUILD_CONFIGURATION="release"'
assert_contains "$ROOT/script/release-all.sh" 'export NMH_BUILD_CONFIGURATION="$RELEASE_BUILD_CONFIGURATION"'
assert_contains "$ROOT/script/validate-release-artifact.sh" 'artifact build configuration mismatch'
assert_contains "$ROOT/script/release-all.sh" 'run_candidate_install_smoke "$DMG" "candidate" "$APP"'
assert_contains "$ROOT/script/release-all.sh" 'run_candidate_install_smoke "$HOSTED_DIR/$(basename "$DMG")" "hosted" "$APP"'
assert_contains "$ROOT/script/release-all.sh" 'NMH_EXPECTED_SOURCE_COMMIT="$COMMIT"'
assert_contains "$ROOT/script/release-all.sh" 'NMH_EXPECTED_BUILD_CONFIGURATION="$RELEASE_BUILD_CONFIGURATION"'
assert_contains "$ROOT/script/verify-installed-release.sh" 'installed source commit mismatch'
assert_contains "$ROOT/script/verify-installed-release.sh" 'installed build configuration mismatch'
assert_contains "$ROOT/script/install-local.sh" 'NMH_EXPECTED_SOURCE_COMMIT="$NMH_SOURCE_COMMIT"'
assert_contains "$ROOT/script/install-local.sh" 'TARGET_APP_BINARY="$APP_PATH/Contents/MacOS/$NMH_APP_NAME"'
assert_contains "$ROOT/script/install-local.sh" 'nmh_stop_app_binary "$TARGET_APP_BINARY" true'
assert_not_contains "$ROOT/script/install-local.sh" 'nmh_stop_app true'
assert_order 'nmh_stop_app_binary "$TARGET_APP_BINARY" true' 'mv "$APP_PATH" "$BACKUP_PATH"' "$ROOT/script/install-local.sh"

echo "== remote publication integrity stays fail-closed =="
assert_contains "$ROOT/script/release-all.sh" 'git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}"'
assert_contains "$ROOT/script/release-all.sh" 'remote tag $TAG on origin to resolve exactly to local release commit $COMMIT'
assert_contains "$ROOT/script/release-all.sh" 'run gh-release-create gh release create "$TAG"'
assert_contains "$ROOT/script/release-all.sh" '--verify-tag'
assert_contains "$ROOT/script/release-all.sh" 'verify_hosted_release_contract'
assert_contains "$ROOT/script/release-all.sh" 'actual_name_set != expected_names'
assert_contains "$ROOT/script/release-all.sh" 'asset.get("state") != "uploaded"'
assert_contains "$ROOT/script/release-all.sh" 'cmp -s "$source" "$hosted"'
assert_not_contains "$ROOT/script/release-all.sh" 'gh release view "$TAG" >/dev/null 2>&1 ||'
assert_not_contains "$ROOT/script/release-all.sh" 'gh release upload "$TAG"'
assert_not_contains "$ROOT/script/release-all.sh" '--clobber'
assert_order 'run remote-tag-before-create verify_remote_release_tag' 'run gh-release-create gh release create "$TAG"' "$ROOT/script/release-all.sh"
assert_order 'run gh-release-create gh release create "$TAG"' 'run remote-tag-after-create verify_remote_release_tag' "$ROOT/script/release-all.sh"
assert_order 'run remote-tag-after-create verify_remote_release_tag' 'run hosted-release-contract verify_hosted_release_contract' "$ROOT/script/release-all.sh"
assert_order 'run hosted-release-contract verify_hosted_release_contract' 'run hosted-asset-byte-equality verify_hosted_release_asset_bytes' "$ROOT/script/release-all.sh"

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
assert_fail release-output-outside-repo env NMH_RELEASE_DIR="$TMP" "$ROOT/script/release-all.sh" --local-only --skip-tests
assert_contains "$TMP/release-output-outside-repo.err" "release output must be a child"
printf 'intentional dirty-worktree probe\n' >"$DIRTY_PROBE"
assert_fail local-dirty-worktree env NMH_RELEASE_DIR="$ROOT/dist/release-script-test-dirty-$$" "$ROOT/script/release-all.sh" --local-only --skip-tests
assert_contains "$TMP/local-dirty-worktree.err" "release artifacts require a completely clean working tree"
rm -f "$DIRTY_PROBE"

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
rm -f "$PREFLIGHT_REPO/untracked.txt"

echo "== throwaway settings suites are forgotten completely, the real domain never =="
SUITE_PROBE="NikoMusicHubE2E.release-script-test.$(uuidgen)"
defaults write "$SUITE_PROBE" probe -int 1
bash -c "source '$LIFECYCLE'; nmh_forget_settings_suite '$SUITE_PROBE'"
if [[ -e "$HOME/Library/Preferences/$SUITE_PROBE.plist" ]]; then
  echo "nmh_forget_settings_suite left $SUITE_PROBE.plist behind" >&2
  exit 1
fi
assert_fail forget-real-domain bash -c "source '$LIFECYCLE'; nmh_forget_settings_suite com.niko96.NikoMusicHub"
assert_contains "$TMP/forget-real-domain.err" "refusing to forget settings suite"

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

# Both markers are derived from CHANGELOG.md rather than hard-coded, so this
# keeps proving the boundary behavior after every version bump instead of
# pinning one release's wording and silently going stale at the next bump.
NOTES_VERSION="$(nmh_release_version)"
CURRENT_SECTION="$(awk -v version="$NOTES_VERSION" '
  $0 ~ "^## " version " - " { active = 1; next }
  active && /^## / { exit }
  active { print }
' "$ROOT/CHANGELOG.md")"
CURRENT_BULLET="$(printf '%s\n' "$CURRENT_SECTION" | grep -E '^- ' | head -n 1)"
# The last bullet in the file belongs to the oldest section, so it is the entry
# furthest from the current release that extraction must never reach.
OLDER_BULLET="$(grep -E '^- ' "$ROOT/CHANGELOG.md" | tail -n 1)"

if [[ -z "$CURRENT_BULLET" ]]; then
  echo "CHANGELOG.md has no bullet for $NOTES_VERSION; release-note extraction cannot be verified" >&2
  exit 1
fi
if [[ -z "$OLDER_BULLET" ]] || printf '%s\n' "$CURRENT_SECTION" | grep -Fq -- "$OLDER_BULLET"; then
  echo "CHANGELOG.md needs an older release section whose wording differs from $NOTES_VERSION" >&2
  exit 1
fi

# Present: the current section was extracted, and the notes are not empty.
assert_contains "$NOTES" "$CURRENT_BULLET"
# Absent: extraction stopped at the section boundary. An extractor that stripped
# headings but kept reading past them would still leak this older bullet.
assert_not_contains "$NOTES" "$OLDER_BULLET"
if grep -Eq '^## ' "$NOTES"; then
  echo "release notes unexpectedly contain a version heading" >&2
  exit 1
fi
if grep -Fq '# Changelog' "$NOTES"; then
  echo "release notes unexpectedly contain the whole changelog" >&2
  exit 1
fi

echo "release script regression tests passed."
