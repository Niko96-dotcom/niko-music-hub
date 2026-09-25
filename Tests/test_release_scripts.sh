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
# The parent runner's output belongs to its checkout, not these nested fixtures.
# Each output-path test below supplies its own override explicitly.
unset NMH_RELEASE_DIR NMH_RELEASE_LOG

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
  # Anchored ^...$ targets the actual invocation line (trimmed exact match),
  # not the function definition (which carries '() {'). Plain needles keep
  # the historical substring behavior for all other order checks.
  case "$needle" in
    ^*\$)
      local inner="${needle#^}"
      inner="${inner%$}"
      awk -v needle="$inner" '{ line=$0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line); if (line == needle) { print NR; exit } }' "$file"
      ;;
    *)
      awk -v needle="$needle" 'index($0, needle) { print NR; exit }' "$file"
      ;;
  esac
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
assert_order 'notarize dmg "$DMG"' 'log "checksums and manifest"' "$ROOT/script/release-all.sh"
assert_order 'run secure-timestamps require_secure_timestamps' 'notarize app "$APP_ZIP"' "$ROOT/script/release-all.sh"
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

echo "== public mode fails closed without credentials (clean-prerequisite aware) =="
# The candidate checkout carries uncommitted test edits during development, so the
# pinning clean prerequisite fires before credential checks. Both are fail-closed;
# the clean-fixture credential contract (exact NMH_DEVELOPER_ID_APPLICATION) is
# proven hermetically by Tests/test_release_pipeline_provenance.py orchestration.
if [[ -n "$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)" ]]; then
  assert_fail public-dirty-blocks-creds "$ROOT/script/release-all.sh" --public --dry-run-publish
  assert_contains "$TMP/public-dirty-blocks-creds.err" "release artifacts require a completely clean working tree"
else
  assert_fail public-missing-creds "$ROOT/script/release-all.sh" --public --dry-run-publish
  assert_contains "$TMP/public-missing-creds.err" "NMH_DEVELOPER_ID_APPLICATION"
fi
# Pinning order stays fail-closed: overrides rejected before pinning, clean
# prerequisite before snapshot, snapshot before gates/build/metadata.
assert_order 'nmh_snapshot_reject_public_overrides "$MODE"' '^require_clean_release_worktree$' "$ROOT/script/release-all.sh"
assert_order '^require_clean_release_worktree$' 'nmh_snapshot_init_run_dir' "$ROOT/script/release-all.sh"
assert_order 'nmh_snapshot_create_pinned_source' 'ROOT="$SNAPSHOT_SRC"' "$ROOT/script/release-all.sh"
assert_order 'ROOT="$SNAPSHOT_SRC"' 'run ci "$ROOT/script/ci.sh"' "$ROOT/script/release-all.sh"
assert_contains "$ROOT/script/release-all.sh" 'running release-all.sh differs from pinned commit'
assert_contains "$ROOT/script/release-all.sh" 'frozen UAT evidence changed after validation'
assert_contains "$ROOT/script/release-all.sh" 'FROZEN_UAT_SHA="$(shasum -a 256 "$FROZEN_UAT"'
assert_contains "$ROOT/script/release-all.sh" '!= "$FROZEN_UAT_SHA"'
assert_contains "$ROOT/script/lib/release_snapshot.sh" 'public release refuses NMH_RELEASE_TEST_MODE'

echo "== public mode refuses the test stub bundle hook =="
assert_contains "$ROOT/script/release-all.sh" 'public release refuses NMH_RELEASE_TEST_MODE'
assert_fail public-test-mode env NMH_DEVELOPER_ID_APPLICATION=test NMH_NOTARY_PROFILE=test NMH_RELEASE_UAT_EVIDENCE=/dev/null NMH_RELEASE_TEST_MODE=1 "$ROOT/script/release-all.sh" --public --dry-run-publish
assert_contains "$TMP/public-test-mode.err" "NMH_RELEASE_TEST_MODE"

echo "== isolated product build writes snapshot dist, stages release build =="
assert_contains "$ROOT/script/release-all.sh" 'SNAPSHOT_BUILD_DIST="$SNAPSHOT_SRC/dist/release-build"'
assert_contains "$ROOT/script/release-all.sh" 'export NMH_DIST_DIR="$SNAPSHOT_BUILD_DIST"'
assert_contains "$ROOT/script/release-all.sh" '/usr/bin/ditto "$SNAPSHOT_APP" "$APP"'
assert_not_contains "$ROOT/script/release-all.sh" 'export NMH_DIST_DIR="$BUILD_DIST"'
assert_not_contains "$ROOT/script/release-all.sh" 'NMH_ROOT_DIR="$SNAPSHOT_SRC"'

echo "== post-pin preflight reads pinned snapshot, not live checkout =="
assert_contains "$ROOT/script/release-all.sh" '"$ROOT/script/release-preflight.sh" --root "$ROOT"'
assert_not_contains "$ROOT/script/release-all.sh" '--root "$INVOKING_ROOT"'
assert_contains "$ROOT/script/release-all.sh" 'if [[ "${NMH_RELEASE_TEST_MODE:-}" == "1" ]]; then'

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
# The preflight compares local release tags against origin; give the fixture a
# bare origin that already carries an older release tag at the same object.
PREFLIGHT_ORIGIN="$TMP/preflight-origin.git"
git init -q --bare "$PREFLIGHT_ORIGIN"
git -C "$PREFLIGHT_REPO" remote add origin "$PREFLIGHT_ORIGIN"
git -C "$PREFLIGHT_REPO" tag v0.0.1
git -C "$PREFLIGHT_REPO" push -q origin v0.0.1
git -C "$PREFLIGHT_REPO" tag "v$(cat "$ROOT/VERSION")"
assert_pass preflight-clean "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO"
printf 'dirty\n' >"$PREFLIGHT_REPO/untracked.txt"
assert_fail preflight-dirty "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO"
assert_contains "$TMP/preflight-dirty.err" "completely clean working tree"
rm -f "$PREFLIGHT_REPO/untracked.txt"

echo "== local release tags must mirror origin =="
# A local-only tag anchors history that never went through the public filter.
git -C "$PREFLIGHT_REPO" tag v0.0.2
assert_fail preflight-stray-tag "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO"
assert_contains "$TMP/preflight-stray-tag.err" "local tag v0.0.2"
assert_contains "$TMP/preflight-stray-tag.err" "does not match origin (missing)"
git -C "$PREFLIGHT_REPO" tag -d v0.0.2 >/dev/null
# A tag that exists on both sides but at different objects is just as wrong.
git -C "$PREFLIGHT_REPO" commit -q --allow-empty -m "moves v0.0.1 locally"
git -C "$PREFLIGHT_REPO" tag -f v0.0.1 >/dev/null
assert_fail preflight-moved-tag "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO"
assert_contains "$TMP/preflight-moved-tag.err" "local tag v0.0.1"
git -C "$PREFLIGHT_REPO" tag -f v0.0.1 HEAD~1 >/dev/null
git -C "$PREFLIGHT_REPO" reset -q --hard HEAD~1
git -C "$PREFLIGHT_REPO" tag -f "v$(cat "$ROOT/VERSION")" >/dev/null
assert_pass preflight-mirrored-tags "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO"
# Without an origin nothing can be mirrored, so the preflight must not guess.
git -C "$PREFLIGHT_REPO" remote remove origin
assert_fail preflight-no-origin "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO"
assert_contains "$TMP/preflight-no-origin.err" "could not list release tags on origin"
git -C "$PREFLIGHT_REPO" remote add origin "$PREFLIGHT_ORIGIN"

echo "== publish rehearsal may run before the tag exists, publishing may not =="
git -C "$PREFLIGHT_REPO" tag -d "v$(cat "$ROOT/VERSION")" >/dev/null
assert_fail preflight-untagged "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO"
assert_contains "$TMP/preflight-untagged.err" "to resolve exactly to HEAD"
assert_pass preflight-rehearsal "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO" --allow-missing-tag
assert_contains "$TMP/preflight-rehearsal.out" "not created yet; rehearsal"
git -C "$PREFLIGHT_REPO" tag "v$(cat "$ROOT/VERSION")" HEAD~0 2>/dev/null || true
git -C "$PREFLIGHT_REPO" commit -q --allow-empty -m "moves head past the tag"
assert_fail preflight-stale-tag-rehearsal "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO" --allow-missing-tag
assert_contains "$TMP/preflight-stale-tag-rehearsal.err" "to resolve exactly to HEAD"
grep -Fq -- '--allow-missing-tag' "$ROOT/script/release-all.sh" || {
  echo "release-all.sh must run the preflight in rehearsal mode for --dry-run-publish" >&2
  exit 1
}
if grep -A1 -F 'if [[ "$PUBLISH" == true ]]; then' "$ROOT/script/release-all.sh" | grep -Fq -- '--allow-missing-tag'; then
  echo "release-all.sh must never allow a missing tag when publishing" >&2
  exit 1
fi

echo "== every Developer ID signature carries a secure timestamp =="
LIFECYCLE="$ROOT/script/lib/app_lifecycle.sh"
grep -Fq -- '--options runtime --timestamp' "$LIFECYCLE" || {
  echo "nmh_sign_bundle must request a secure timestamp for real identities" >&2
  exit 1
}
if [[ "$(grep -c -- '--timestamp=none' "$LIFECYCLE")" != "1" ]]; then
  echo "--timestamp=none may only appear once, in the ad-hoc branch of nmh_sign_bundle" >&2
  exit 1
fi
grep -Fq 'require_secure_timestamps "$APP"' "$ROOT/script/release-all.sh" || {
  echo "public release must assert nested secure timestamps before notarization" >&2
  exit 1
}
grep -Fq 'notarize app "$APP_ZIP"' "$ROOT/script/release-all.sh" || {
  echo "app notarization must go through the retrying notarize helper" >&2
  exit 1
}
grep -Fq 'notarize dmg "$DMG"' "$ROOT/script/release-all.sh" || {
  echo "dmg notarization must go through the retrying notarize helper" >&2
  exit 1
}
grep -Fq 'nmh_console_locked' "$ROOT/script/release-all.sh" || {
  echo "public release must fail fast on a locked console" >&2
  exit 1
}
grep -Fq 'nmh_notary_upload_endpoint_reachable' "$ROOT/script/release-all.sh" || {
  echo "public release must fail fast when the notary upload endpoint is unreachable" >&2
  exit 1
}

echo "== nested code is proven hardened, same-team and entitlement-free before upload =="
SIGNATURE_GATE="$(awk '/^require_secure_timestamps\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$ROOT/script/release-all.sh")"
for needle in 'runtime' 'TeamIdentifier=' '<key>'; do
  grep -Fq -- "$needle" <<<"$SIGNATURE_GATE" || {
    echo "require_secure_timestamps must check '$needle' on every nested component" >&2
    exit 1
  }
done
assert_contains "$ROOT/script/release-all.sh" 'NMH_EXPECTED_APP_ENTITLEMENTS='"'"'{"com.apple.security.device.audio-input":true}'"'"
assert_contains "$ROOT/script/release-all.sh" 'run app-entitlements require_expected_entitlements "$APP"'
assert_order 'run secure-timestamps require_secure_timestamps' 'run app-entitlements require_expected_entitlements' "$ROOT/script/release-all.sh"
assert_order 'run app-entitlements require_expected_entitlements' 'notarize app "$APP_ZIP"' "$ROOT/script/release-all.sh"
assert_contains "$ROOT/script/release-all.sh" 'codesign --force --timestamp --identifier "$BUNDLE_ID.dmg" --sign "$NMH_DEVELOPER_ID_APPLICATION" "$DMG"'
# The recorder's Core Audio tap is the only entitlement the app carries; the
# helpers are signed without --entitlements and without preserved metadata.
if [[ "$(grep -c -- '--entitlements "$NMH_ENTITLEMENTS_PLIST"' "$LIFECYCLE")" != "1" ]]; then
  echo "exactly one codesign call (the app wrapper) may pass --entitlements" >&2
  exit 1
fi
if grep -v '^ *#' "$LIFECYCLE" | grep -Fq -- '--preserve-metadata'; then
  echo "nmh_sign_bundle must not preserve upstream Sparkle metadata (its ad-hoc application-identifier fails notarization)" >&2
  exit 1
fi
for key in com.apple.security.cs.disable-library-validation com.apple.security.cs.allow-unsigned-executable-memory com.apple.security.cs.allow-jit com.apple.security.get-task-allow com.apple.security.app-sandbox; do
  assert_not_contains "$LIFECYCLE" "$key"
done
for key in NSDocumentsFolderUsageDescription NSDesktopFolderUsageDescription NSDownloadsFolderUsageDescription NSRemovableVolumesUsageDescription NSNetworkVolumesUsageDescription NSAudioCaptureUsageDescription NSMicrophoneUsageDescription; do
  assert_contains "$LIFECYCLE" "<key>$key</key>"
done

echo "== the build number must advance the live update feed =="
assert_contains "$ROOT/script/release-all.sh" 'LIVE_BUILD_NUMBER="$(nmh_live_feed_max_build_number)"'
assert_contains "$ROOT/script/release-all.sh" 'if (( BUILD_NUMBER <= LIVE_BUILD_NUMBER )); then'
assert_order 'LIVE_BUILD_NUMBER="$(nmh_live_feed_max_build_number)"' 'log "release identity"' "$ROOT/script/release-all.sh"
CURL_STUB="$TMP/curl-stub"
mkdir -p "$CURL_STUB"
cat >"$CURL_STUB/curl" <<'STUB'
#!/usr/bin/env bash
[[ "${CURL_STUB_FAIL:-}" == 1 ]] && exit 22
cat <<'FEED'
<?xml version="1.0" standalone="yes"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel><title>NikoMusicHub</title>
<item><title>0.0.2</title><sparkle:version>368</sparkle:version><sparkle:shortVersionString>0.0.2</sparkle:shortVersionString></item>
<item><title>0.0.1</title><sparkle:version>1201</sparkle:version><sparkle:shortVersionString>0.0.1</sparkle:shortVersionString></item>
</channel></rss>
FEED
STUB
chmod +x "$CURL_STUB/curl"
LIVE_MAX="$(PATH="$CURL_STUB:$PATH" bash -c "source '$ROOT/script/release-env.sh'; nmh_live_feed_max_build_number")"
[[ "$LIVE_MAX" == "1201" ]] || {
  echo "nmh_live_feed_max_build_number must return the highest sparkle:version, got '$LIVE_MAX'" >&2
  exit 1
}
if CURL_STUB_FAIL=1 PATH="$CURL_STUB:$PATH" bash -c "set -o pipefail; source '$ROOT/script/release-env.sh'; nmh_live_feed_max_build_number" >/dev/null 2>&1; then
  echo "nmh_live_feed_max_build_number must fail when the feed cannot be fetched" >&2
  exit 1
fi
assert_fail public-test-feed env NMH_DEVELOPER_ID_APPLICATION=test NMH_NOTARY_PROFILE=test NMH_RELEASE_UAT_EVIDENCE=/dev/null NMH_UPDATE_FEED_URL=https://example.invalid/appcast.xml "$ROOT/script/release-all.sh" --public --dry-run-publish
assert_contains "$TMP/public-test-feed.err" "public release refuses NMH_UPDATE_FEED_URL"

echo "== notary verdicts are read without pipe races =="
# A `writer | grep -q` pipeline under pipefail can fail with SIGPIPE when grep exits
# early; that turned an Accepted verdict into a failed rehearsal once.
for fn in notarize require_secure_timestamps require_expected_entitlements; do
  if awk "/^$fn\\(\\) \\{/{p=1} p{print} p&&/^}/{exit}" "$ROOT/script/release-all.sh" | grep -v '^ *#' | grep -Eq '\| *grep +-[a-zA-Z]*q'; then
    echo "$fn must not pipe into grep -q (pipefail + SIGPIPE race)" >&2
    exit 1
  fi
done
NOTARY_STUB="$TMP/notary-stub"
mkdir -p "$NOTARY_STUB"
cat >"$NOTARY_STUB/xcrun" <<'STUB'
#!/usr/bin/env bash
# Mimics `notarytool submit --wait` with a verbose Accepted transcript.
for i in $(seq 1 400); do echo "  progress line $i"; done
echo "  id: 00000000-0000-0000-0000-000000000000"
echo "  status: Accepted"
STUB
chmod +x "$NOTARY_STUB/xcrun"
NOTARIZE_FN="$(awk '/^notarize\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$ROOT/script/release-all.sh")"
for i in $(seq 1 25); do
  if ! PATH="$NOTARY_STUB:$PATH" bash -c "set -euo pipefail; LOG_FILE=/dev/null; RELEASE_DIR='$TMP'; NMH_NOTARY_PROFILE=stub; $NOTARIZE_FN; notarize app /dev/null" >/dev/null 2>&1; then
    echo "notarize helper rejected an Accepted verdict on run $i" >&2
    exit 1
  fi
done

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

echo "== shared release gate contract is the single source of truth =="
# shellcheck source=../script/lib/release_gates.sh
source "$ROOT/script/lib/release_gates.sh"
[[ "${#NMH_REQUIRED_RELEASE_GATES[@]}" == "12" ]] || { echo "shared contract must define exactly 12 required gates" >&2; exit 1; }
[[ "${#NMH_EMERGENCY_OVERRIDABLE_GATES[@]}" == "4" ]] || { echo "shared contract must define exactly 4 emergency-overridable gates" >&2; exit 1; }
[[ "${#NMH_REQUIRED_UAT_CHECKS[@]}" == "10" ]] || { echo "shared contract must define exactly 10 required UAT checks" >&2; exit 1; }
assert_contains "$ROOT/script/release-all.sh" 'for _nmh_gate in "${NMH_REQUIRED_RELEASE_GATES[@]}"; do'
assert_contains "$ROOT/script/release-all.sh" 'APPROVAL_ARGS+=(--gate "$_nmh_gate|$_nmh_cmd|$_nmh_res|$GATE_TIME")'
for gate in "${NMH_REQUIRED_RELEASE_GATES[@]}"; do
  assert_contains "$ROOT/script/release-all.sh" "$gate) _nmh_cmd="
done
for gate in clean-tagged-checkout consolidated-mac-uat debug-ci user-e2e release-configuration thread-sanitizer release-identity release-platform-contract public-tree-hygiene sign-notarize-staple artifact-validation update-feed; do
  grep -Fqx -- "$gate" <(printf '%s\n' "${NMH_REQUIRED_RELEASE_GATES[@]}") || { echo "shared contract missing required gate $gate" >&2; exit 1; }
done
for gate in debug-ci user-e2e release-configuration thread-sanitizer; do
  grep -Fqx -- "$gate" <(printf '%s\n' "${NMH_EMERGENCY_OVERRIDABLE_GATES[@]}") || { echo "shared contract missing overridable gate $gate" >&2; exit 1; }
done
assert_contains "$ROOT/script/validate-release-uat.sh" 'source "$ROOT/script/lib/release_gates.sh"'
assert_contains "$ROOT/script/validate-release-approval.sh" 'source "$ROOT/script/lib/release_gates.sh"'
assert_contains "$ROOT/script/lib/release_gates.sh" 'Single source of truth'

echo "== consolidated exact-commit UAT evidence =="
UAT="$TMP/uat.json"
CURRENT_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
EXPECTED_SHORT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
EXPECTED_BUILD_ID="$(cat "$ROOT/VERSION")+$EXPECTED_SHORT_COMMIT"
TEST_SIGNING_IDENTITY="Developer ID Application: Release Test (TEAM)"
OTHER_SIGNING_IDENTITY="Developer ID Application: Release Test (OTHER)"
write_valid_uat() {
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
  "tested_build": {
    "build_id": "$EXPECTED_BUILD_ID",
    "build_configuration": "release",
    "signing_identity": "$TEST_SIGNING_IDENTITY",
    "hardened_runtime": true
  },
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
}
write_valid_uat
assert_pass uat-valid "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_pass uat-valid-explicit-identity "$ROOT/script/validate-release-uat.sh" --evidence "$UAT" --commit "$CURRENT_COMMIT" --expected-signing-identity "$TEST_SIGNING_IDENTITY" --expected-build-id "$EXPECTED_BUILD_ID"
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["checks"]["privacy_permissions"] = "pending"
path.write_text(json.dumps(payload))
PY
assert_fail uat-pending "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-pending.err" "privacy_permissions"

echo "== UAT rejects changed status, commit, and checks =="
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["status"] = "pending"
path.write_text(json.dumps(payload))
PY
assert_fail uat-status-not-approved "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-status-not-approved.err" "must be approved"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["commit"] = "0" * 40
path.write_text(json.dumps(payload))
PY
assert_fail uat-commit-changed "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-commit-changed.err" "commit does not match"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["checks"]["e2e_user_smoke"] = "failed"
path.write_text(json.dumps(payload))
PY
assert_fail uat-check-failed "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-check-failed.err" "e2e_user_smoke"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["checks"]["evil_extra_check"] = "passed"
path.write_text(json.dumps(payload))
PY
assert_fail uat-unknown-check "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-unknown-check.err" "unknown checks"

echo "== UAT binds the exact tested commit build =="
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["tested_build"]["build_id"] = payload["version"] + "+000000000000"
path.write_text(json.dumps(payload))
PY
assert_fail uat-stale-build-id "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-stale-build-id.err" "exactly"
assert_contains "$TMP/uat-stale-build-id.err" "stale"
write_valid_uat
assert_fail uat-signing-team-mismatch "$ROOT/script/validate-release-uat.sh" --evidence "$UAT" --expected-signing-identity "$OTHER_SIGNING_IDENTITY"
assert_contains "$TMP/uat-signing-team-mismatch.err" "exactly"
assert_contains "$TMP/uat-signing-team-mismatch.err" "$OTHER_SIGNING_IDENTITY"
write_valid_uat
assert_fail uat-inconsistent-expected-build-id "$ROOT/script/validate-release-uat.sh" --evidence "$UAT" --commit "$CURRENT_COMMIT" --expected-build-id "$(cat "$ROOT/VERSION")+000000000000"
assert_contains "$TMP/uat-inconsistent-expected-build-id.err" "does not match canonical"
write_valid_uat
assert_fail uat-adhoc-expected-identity "$ROOT/script/validate-release-uat.sh" --evidence "$UAT" --commit "$CURRENT_COMMIT" --expected-signing-identity "ad-hoc"
assert_contains "$TMP/uat-adhoc-expected-identity.err" "must be a Developer ID"

echo "== UAT must be run on the build shape that ships =="
# An ad-hoc debug install has a per-build TCC identity and no hardened runtime;
# its privacy and recorder results say nothing about the Developer ID artifact.
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["tested_build"]["signing_identity"] = "ad-hoc"
path.write_text(json.dumps(payload))
PY
assert_fail uat-adhoc-build "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-adhoc-build.err" "Developer ID signed build"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["tested_build"]["build_configuration"] = "debug"
path.write_text(json.dumps(payload))
PY
assert_fail uat-debug-build "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-debug-build.err" "release-configuration build"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
del payload["tested_build"]
path.write_text(json.dumps(payload))
PY
assert_fail uat-untracked-build "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-untracked-build.err" "tested_build.build_id"
write_valid_uat
assert_pass uat-valid-again "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"

echo "== UAT rejects template sentinels, placeholders, blanks, and lax types =="
TEMPLATE_APPROVER="$(/usr/bin/python3 -c 'import json; print(json.load(open("'"$ROOT"'/docs/release-uat-evidence.template.json"))["approved_by"])')"
TEMPLATE_MACHINE="$(/usr/bin/python3 -c 'import json; print(json.load(open("'"$ROOT"'/docs/release-uat-evidence.template.json"))["machine"])')"
[[ "$TEMPLATE_APPROVER" == TODO* ]] || { echo "template approved_by sentinel must stay a clear TODO (got '$TEMPLATE_APPROVER')" >&2; exit 1; }
[[ "$TEMPLATE_MACHINE" == TODO* ]] || { echo "template machine sentinel must stay a clear TODO (got '$TEMPLATE_MACHINE')" >&2; exit 1; }
write_valid_uat
/usr/bin/python3 - "$UAT" "$TEMPLATE_APPROVER" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["approved_by"] = sys.argv[2]
path.write_text(json.dumps(payload))
PY
assert_fail uat-template-approver "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-template-approver.err" "real approved_by"
write_valid_uat
/usr/bin/python3 - "$UAT" "$TEMPLATE_MACHINE" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["machine"] = sys.argv[2]
path.write_text(json.dumps(payload))
PY
assert_fail uat-template-machine "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-template-machine.err" "tested machine description"
for placeholder in "TODO" "TODO_REAL_NAME_REQUIRED" "" "   " "REPLACE_WITH_SOMEONE"; do
  write_valid_uat
  /usr/bin/python3 - "$UAT" "$placeholder" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["approved_by"] = sys.argv[2]
path.write_text(json.dumps(payload))
PY
  assert_fail "uat-placeholder-approver" "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
  assert_contains "$TMP/uat-placeholder-approver.err" "real approved_by"
done
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["schema_version"] = "1"
path.write_text(json.dumps(payload))
PY
assert_fail uat-lax-schema-string "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-lax-schema-string.err" "schema_version"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["tested_build"]["hardened_runtime"] = "true"
path.write_text(json.dumps(payload))
PY
assert_fail uat-lax-hardened-string "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-lax-hardened-string.err" "hardened"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["schema_version"] = 1.0
path.write_text(json.dumps(payload))
PY
assert_fail uat-lax-schema-float "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-lax-schema-float.err" "schema_version"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["schema_version"] = True
path.write_text(json.dumps(payload))
PY
assert_fail uat-lax-schema-bool "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-lax-schema-bool.err" "schema_version"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["tested_build"]["hardened_runtime"] = 1
path.write_text(json.dumps(payload))
PY
assert_fail uat-lax-hardened-int "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
assert_contains "$TMP/uat-lax-hardened-int.err" "hardened"
write_valid_uat
assert_pass uat-valid-after-placeholder "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"

echo "== approval record binds exact artifact, manifest, UAT, and gates =="
write_valid_uat
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
  --build-id "$EXPECTED_BUILD_ID" \
  --build-number 1 \
  --architectures "$EXPECTED_ARCHITECTURES" \
  --minimum-macos "$EXPECTED_MIN_MACOS" \
  --artifact "$(basename "$APPROVAL_ARTIFACT")" \
  --artifact-size "$(stat -f%z "$APPROVAL_ARTIFACT")" \
  --artifact-sha256 "$APPROVAL_ARTIFACT_SHA" \
  --created-utc 2026-07-13T12:00:00Z \
  --signing-identity "$TEST_SIGNING_IDENTITY" \
  --validation-status passed \
  --public-release
build_valid_approval() {
  _bva_out="$1"
  _bva_uat_sha="$(shasum -a 256 "$UAT" | awk '{print $1}')"
  _bva_manifest_sha="$(shasum -a 256 "$APPROVAL_MANIFEST" | awk '{print $1}')"
  _bva_args=(
    approval
    --output "$_bva_out"
    --version "$(cat "$ROOT/VERSION")"
    --bundle-id "$EXPECTED_BUNDLE_ID"
    --tag "v$(cat "$ROOT/VERSION")"
    --commit "$CURRENT_COMMIT"
    --artifact "$(basename "$APPROVAL_ARTIFACT")"
    --artifact-sha256 "$APPROVAL_ARTIFACT_SHA"
    --manifest "$(basename "$APPROVAL_MANIFEST")"
    --manifest-sha256 "$_bva_manifest_sha"
    --machine "arm64 macOS test machine"
    --created-utc 2026-07-13T12:00:00Z
    --uat-file "$(basename "$UAT")"
    --uat-sha256 "$_bva_uat_sha"
    --uat-approved-by "Release Test"
    --uat-approved-at-utc 2026-07-13T12:00:00Z
  )
  for _bva_gate in "${NMH_REQUIRED_RELEASE_GATES[@]}"; do
    case "$_bva_gate" in
      clean-tagged-checkout) _bva_args+=(--gate "$_bva_gate|./script/release-preflight.sh|passed|2026-07-13T12:00:00Z") ;;
      consolidated-mac-uat) _bva_args+=(--gate "$_bva_gate|./script/validate-release-uat.sh|passed|2026-07-13T12:00:00Z") ;;
      debug-ci) _bva_args+=(--gate "$_bva_gate|./script/ci.sh|passed|2026-07-13T12:00:00Z") ;;
      user-e2e) _bva_args+=(--gate "$_bva_gate|NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh|passed|2026-07-13T12:00:00Z") ;;
      release-configuration) _bva_args+=(--gate "$_bva_gate|./script/ci-release.sh|passed|2026-07-13T12:00:00Z") ;;
      thread-sanitizer) _bva_args+=(--gate "$_bva_gate|./script/ci-tsan.sh|passed|2026-07-13T12:00:00Z") ;;
      release-identity) _bva_args+=(--gate "$_bva_gate|./script/release-version-verify.sh|passed|2026-07-13T12:00:00Z") ;;
      release-platform-contract) _bva_args+=(--gate "$_bva_gate|RELEASE_ARCHITECTURES,Package.swift minimum macOS|passed|2026-07-13T12:00:00Z") ;;
      public-tree-hygiene) _bva_args+=(--gate "$_bva_gate|./script/public-tree-hygiene.sh --public-release|passed|2026-07-13T12:00:00Z") ;;
      sign-notarize-staple) _bva_args+=(--gate "$_bva_gate|codesign, notarytool, stapler, spctl|passed|2026-07-13T12:00:00Z") ;;
      artifact-validation) _bva_args+=(--gate "$_bva_gate|./script/validate-release-artifact.sh|passed|2026-07-13T12:00:00Z") ;;
      update-feed) _bva_args+=(--gate "$_bva_gate|./script/validate-update-feed.py|passed|2026-07-13T12:00:00Z") ;;
    esac
  done
  "$ROOT/script/generate-release-record.py" "${_bva_args[@]}"
}
APPROVAL="$TMP/NikoMusicHub-$(cat "$ROOT/VERSION")-release-approval.json"
build_valid_approval "$APPROVAL"
assert_pass approval-valid "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_pass approval-valid-explicit-binding "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT" \
  --commit "$CURRENT_COMMIT" --expected-build-id "$EXPECTED_BUILD_ID" --expected-signing-identity "$TEST_SIGNING_IDENTITY"
printf 'tampered\n' >>"$APPROVAL_ARTIFACT"
assert_fail approval-tampered "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-tampered.err" "artifact_sha256 mismatch"
printf 'release-artifact-test\n' >"$APPROVAL_ARTIFACT"

echo "== approval binds manifest artifact identity and tag (semantic, rehashed) =="
# Each case mutates the inner manifest then rebuilds (rehashes) the approval so
# the outer manifest_sha256 matches: the validator must still reject for the
# semantic mismatch, not the outer hash.
write_valid_uat
/usr/bin/python3 - "$APPROVAL_MANIFEST" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["artifact"] = "evil-renamed.dmg"
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
build_valid_approval "$APPROVAL"
assert_fail approval-manifest-artifact-name "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-manifest-artifact-name.err" "manifest artifact mismatch"
"$ROOT/script/generate-release-record.py" manifest \
  --output "$APPROVAL_MANIFEST" \
  --version "$(cat "$ROOT/VERSION")" \
  --bundle-id "$EXPECTED_BUNDLE_ID" \
  --tag "v$(cat "$ROOT/VERSION")" \
  --commit "$CURRENT_COMMIT" \
  --build-id "$EXPECTED_BUILD_ID" \
  --build-number 1 \
  --architectures "$EXPECTED_ARCHITECTURES" \
  --minimum-macos "$EXPECTED_MIN_MACOS" \
  --artifact "$(basename "$APPROVAL_ARTIFACT")" \
  --artifact-size "$(stat -f%z "$APPROVAL_ARTIFACT")" \
  --artifact-sha256 "$APPROVAL_ARTIFACT_SHA" \
  --created-utc 2026-07-13T12:00:00Z \
  --signing-identity "$TEST_SIGNING_IDENTITY" \
  --validation-status passed \
  --public-release
/usr/bin/python3 - "$APPROVAL_MANIFEST" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["artifact_sha256"] = "0" * 64
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
build_valid_approval "$APPROVAL"
assert_fail approval-manifest-artifact-hash "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-manifest-artifact-hash.err" "manifest artifact_sha256 mismatch"
"$ROOT/script/generate-release-record.py" manifest \
  --output "$APPROVAL_MANIFEST" \
  --version "$(cat "$ROOT/VERSION")" \
  --bundle-id "$EXPECTED_BUNDLE_ID" \
  --tag "v$(cat "$ROOT/VERSION")" \
  --commit "$CURRENT_COMMIT" \
  --build-id "$EXPECTED_BUILD_ID" \
  --build-number 1 \
  --architectures "$EXPECTED_ARCHITECTURES" \
  --minimum-macos "$EXPECTED_MIN_MACOS" \
  --artifact "$(basename "$APPROVAL_ARTIFACT")" \
  --artifact-size "$(stat -f%z "$APPROVAL_ARTIFACT")" \
  --artifact-sha256 "$APPROVAL_ARTIFACT_SHA" \
  --created-utc 2026-07-13T12:00:00Z \
  --signing-identity "$TEST_SIGNING_IDENTITY" \
  --validation-status passed \
  --public-release
/usr/bin/python3 - "$APPROVAL_MANIFEST" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["tag"] = "v0.0.0-evil"
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
build_valid_approval "$APPROVAL"
assert_fail approval-manifest-tag "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-manifest-tag.err" "manifest tag mismatch"
"$ROOT/script/generate-release-record.py" manifest \
  --output "$APPROVAL_MANIFEST" \
  --version "$(cat "$ROOT/VERSION")" \
  --bundle-id "$EXPECTED_BUNDLE_ID" \
  --tag "v$(cat "$ROOT/VERSION")" \
  --commit "$CURRENT_COMMIT" \
  --build-id "$EXPECTED_BUILD_ID" \
  --build-number 1 \
  --architectures "$EXPECTED_ARCHITECTURES" \
  --minimum-macos "$EXPECTED_MIN_MACOS" \
  --artifact "$(basename "$APPROVAL_ARTIFACT")" \
  --artifact-size "$(stat -f%z "$APPROVAL_ARTIFACT")" \
  --artifact-sha256 "$APPROVAL_ARTIFACT_SHA" \
  --created-utc 2026-07-13T12:00:00Z \
  --signing-identity "$TEST_SIGNING_IDENTITY" \
  --validation-status passed \
  --public-release
build_valid_approval "$APPROVAL"
assert_pass approval-manifest-restored "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"

echo "== final validator rejects template sentinels with rehashed approval =="
write_valid_uat
/usr/bin/python3 - "$UAT" "$TEMPLATE_MACHINE" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["machine"] = sys.argv[2]
path.write_text(json.dumps(payload))
PY
build_valid_approval "$APPROVAL"
assert_fail approval-template-machine "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-template-machine.err" "tested machine description"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["tested_build"]["hardened_runtime"] = "true"
path.write_text(json.dumps(payload))
PY
build_valid_approval "$APPROVAL"
assert_fail approval-lax-hardened-string "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-lax-hardened-string.err" "hardened"
write_valid_uat
build_valid_approval "$APPROVAL"

echo "== final validator rejects coerced schema/approved types (strict) =="
# schema_version True (bool) must not coerce to 1; rehash outer approval so
# only the strict type gate can fail.
write_valid_uat
build_valid_approval "$APPROVAL"
/usr/bin/python3 - "$APPROVAL" <<'PY'
import hashlib, json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["schema_version"] = True
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
assert_fail approval-lax-schema-bool "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-lax-schema-bool.err" "schema_version"
write_valid_uat
build_valid_approval "$APPROVAL"
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["schema_version"] = 1.0
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
assert_fail approval-lax-schema-float "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-lax-schema-float.err" "schema_version"
write_valid_uat
build_valid_approval "$APPROVAL"
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["release_approved"] = 1
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
assert_fail approval-lax-approved-int "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-lax-approved-int.err" "release_approved"
write_valid_uat
build_valid_approval "$APPROVAL"
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["release_approved"] = 1.0
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
assert_fail approval-lax-approved-float "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-lax-approved-float.err" "release_approved"
write_valid_uat
build_valid_approval "$APPROVAL"
/usr/bin/python3 - "$APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["release_approval"]["emergency_override"] = 1
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
assert_fail approval-lax-emergency-int "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-lax-emergency-int.err" "emergency_override"
write_valid_uat
build_valid_approval "$APPROVAL"
# UAT float schema through the final validator (same bytes hashed + checked).
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["schema_version"] = 1.0
path.write_text(json.dumps(payload))
PY
build_valid_approval "$APPROVAL"
assert_fail approval-rejects-uat-float-schema "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-rejects-uat-float-schema.err" "schema_version"
write_valid_uat
build_valid_approval "$APPROVAL"

echo "== final validator hashes and enforces the same UAT bytes =="
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["checks"]["privacy_permissions"] = "pending"
path.write_text(json.dumps(payload))
PY
assert_fail approval-uat-pending-bytes "$ROOT/script/validate-release-uat.sh" --evidence "$UAT"
build_valid_approval "$APPROVAL"
assert_fail approval-rejects-pending-uat "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-rejects-pending-uat.err" "must be passed"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["status"] = "pending"
path.write_text(json.dumps(payload))
PY
build_valid_approval "$APPROVAL"
assert_fail approval-rejects-status-change "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-rejects-status-change.err" "must be approved"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["commit"] = "1" * 40
path.write_text(json.dumps(payload))
PY
assert_fail approval-rejects-commit-change "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-rejects-commit-change.err" "identity mismatch"
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["commit"] = "0" * 40
path.write_text(json.dumps(payload))
PY
build_valid_approval "$APPROVAL"
assert_fail approval-rejects-commit-semantics "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-rejects-commit-semantics.err" "UAT commit mismatch"
write_valid_uat
/usr/bin/python3 - "$UAT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["tested_build"]["build_id"] = payload["version"] + "+000000000000"
path.write_text(json.dumps(payload))
PY
build_valid_approval "$APPROVAL"
assert_fail approval-rejects-stale-build "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-rejects-stale-build.err" "exactly"

echo "== final validator enforces one signing team =="
write_valid_uat
"$ROOT/script/generate-release-record.py" manifest \
  --output "$APPROVAL_MANIFEST" \
  --version "$(cat "$ROOT/VERSION")" \
  --bundle-id "$EXPECTED_BUNDLE_ID" \
  --tag "v$(cat "$ROOT/VERSION")" \
  --commit "$CURRENT_COMMIT" \
  --build-id "$EXPECTED_BUILD_ID" \
  --build-number 1 \
  --architectures "$EXPECTED_ARCHITECTURES" \
  --minimum-macos "$EXPECTED_MIN_MACOS" \
  --artifact "$(basename "$APPROVAL_ARTIFACT")" \
  --artifact-size "$(stat -f%z "$APPROVAL_ARTIFACT")" \
  --artifact-sha256 "$APPROVAL_ARTIFACT_SHA" \
  --created-utc 2026-07-13T12:00:00Z \
  --signing-identity "$OTHER_SIGNING_IDENTITY" \
  --validation-status passed \
  --public-release
build_valid_approval "$APPROVAL"
assert_fail approval-signing-team-mismatch "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-signing-team-mismatch.err" "different signing team"
"$ROOT/script/generate-release-record.py" manifest \
  --output "$APPROVAL_MANIFEST" \
  --version "$(cat "$ROOT/VERSION")" \
  --bundle-id "$EXPECTED_BUNDLE_ID" \
  --tag "v$(cat "$ROOT/VERSION")" \
  --commit "$CURRENT_COMMIT" \
  --build-id "$EXPECTED_BUILD_ID" \
  --build-number 1 \
  --architectures "$EXPECTED_ARCHITECTURES" \
  --minimum-macos "$EXPECTED_MIN_MACOS" \
  --artifact "$(basename "$APPROVAL_ARTIFACT")" \
  --artifact-size "$(stat -f%z "$APPROVAL_ARTIFACT")" \
  --artifact-sha256 "$APPROVAL_ARTIFACT_SHA" \
  --created-utc 2026-07-13T12:00:00Z \
  --signing-identity "$TEST_SIGNING_IDENTITY" \
  --validation-status passed \
  --public-release
build_valid_approval "$APPROVAL"
assert_fail approval-expected-signing-mismatch "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT" \
  --expected-signing-identity "$OTHER_SIGNING_IDENTITY"
assert_contains "$TMP/approval-expected-signing-mismatch.err" "signing.identity mismatch"
assert_fail approval-inconsistent-expected-build-id "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT" \
  --commit "$CURRENT_COMMIT" --expected-build-id "$(cat "$ROOT/VERSION")+000000000000"
assert_contains "$TMP/approval-inconsistent-expected-build-id.err" "does not match canonical"
assert_fail approval-adhoc-expected-identity "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT" \
  --commit "$CURRENT_COMMIT" --expected-signing-identity "ad-hoc"
assert_contains "$TMP/approval-adhoc-expected-identity.err" "must be a Developer ID"

echo "== final validator requires the exact gate set =="
mutate_gates() {
  /usr/bin/python3 - "$APPROVAL" <<PY
import json, pathlib
path = pathlib.Path("$APPROVAL")
payload = json.loads(path.read_text())
gates = payload["gates"]
mode = "$1"
if mode == "duplicate":
    gates.append(dict(gates[0]))
elif mode == "missing":
    payload["gates"] = [g for g in gates if g["name"] != "update-feed"]
elif mode == "unknown":
    gates[0]["name"] = "evil-gate"
    gates[0]["command"] = "evil-command"
elif mode == "disallowed-override":
    for g in gates:
        if g["name"] == "sign-notarize-staple":
            g["result"] = "emergency-override"
    payload["release_approval"]["emergency_override"] = True
    payload["release_approval"]["emergency_reason"] = "test disallowed override"
elif mode == "bad-timestamp":
    gates[0]["completed_utc"] = "not-a-timestamp"
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}
mutate_gates duplicate
assert_fail approval-duplicate-gate "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-duplicate-gate.err" "duplicates"
build_valid_approval "$APPROVAL"
mutate_gates missing
assert_fail approval-missing-gate "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-missing-gate.err" "missing"
build_valid_approval "$APPROVAL"
mutate_gates unknown
assert_fail approval-unknown-gate "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-unknown-gate.err" "unknown"
build_valid_approval "$APPROVAL"
mutate_gates disallowed-override
assert_fail approval-disallowed-override "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-disallowed-override.err" "not emergency-overridable"
build_valid_approval "$APPROVAL"
mutate_gates bad-timestamp
assert_fail approval-bad-timestamp "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-bad-timestamp.err" "ISO-8601"

echo "== narrowly allowed emergency overrides still pass =="
OVERRIDE_APPROVAL="$TMP/override-approval.json"
OVERRIDE_UAT_SHA="$(shasum -a 256 "$UAT" | awk '{print $1}')"
OVERRIDE_MANIFEST_SHA="$(shasum -a 256 "$APPROVAL_MANIFEST" | awk '{print $1}')"
OVERRIDE_ARGS=(
  approval
  --output "$OVERRIDE_APPROVAL"
  --version "$(cat "$ROOT/VERSION")"
  --bundle-id "$EXPECTED_BUNDLE_ID"
  --tag "v$(cat "$ROOT/VERSION")"
  --commit "$CURRENT_COMMIT"
  --artifact "$(basename "$APPROVAL_ARTIFACT")"
  --artifact-sha256 "$APPROVAL_ARTIFACT_SHA"
  --manifest "$(basename "$APPROVAL_MANIFEST")"
  --manifest-sha256 "$OVERRIDE_MANIFEST_SHA"
  --machine "arm64 macOS test machine"
  --created-utc 2026-07-13T12:00:00Z
  --uat-file "$(basename "$UAT")"
  --uat-sha256 "$OVERRIDE_UAT_SHA"
  --uat-approved-by "Release Test"
  --uat-approved-at-utc 2026-07-13T12:00:00Z
  --emergency-reason "test emergency: hardware lab offline"
  --gate "clean-tagged-checkout|./script/release-preflight.sh|passed|2026-07-13T12:00:00Z"
  --gate "consolidated-mac-uat|./script/validate-release-uat.sh|passed|2026-07-13T12:00:00Z"
  --gate "debug-ci|./script/ci.sh|emergency-override|2026-07-13T12:00:00Z"
  --gate "user-e2e|NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh|emergency-override|2026-07-13T12:00:00Z"
  --gate "release-configuration|./script/ci-release.sh|emergency-override|2026-07-13T12:00:00Z"
  --gate "thread-sanitizer|./script/ci-tsan.sh|emergency-override|2026-07-13T12:00:00Z"
  --gate "release-identity|./script/release-version-verify.sh|passed|2026-07-13T12:00:00Z"
  --gate "release-platform-contract|RELEASE_ARCHITECTURES,Package.swift minimum macOS|passed|2026-07-13T12:00:00Z"
  --gate "public-tree-hygiene|./script/public-tree-hygiene.sh --public-release|passed|2026-07-13T12:00:00Z"
  --gate "sign-notarize-staple|codesign, notarytool, stapler, spctl|passed|2026-07-13T12:00:00Z"
  --gate "artifact-validation|./script/validate-release-artifact.sh|passed|2026-07-13T12:00:00Z"
  --gate "update-feed|./script/validate-update-feed.py|passed|2026-07-13T12:00:00Z"
)
"$ROOT/script/generate-release-record.py" "${OVERRIDE_ARGS[@]}"
assert_pass approval-allowed-override "$ROOT/script/validate-release-approval.sh" \
  --approval "$OVERRIDE_APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
/usr/bin/python3 - "$OVERRIDE_APPROVAL" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["release_approval"]["emergency_override"] = False
payload["release_approval"]["emergency_reason"] = None
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
assert_fail approval-override-flag-mismatch "$ROOT/script/validate-release-approval.sh" \
  --approval "$OVERRIDE_APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT"
assert_contains "$TMP/approval-override-flag-mismatch.err" "emergency_override flag does not match"
build_valid_approval "$APPROVAL"


echo "== validators reject unresolved and non-commit objects =="
MISSING_COMMIT="0000000000000000000000000000000000000000"
MISSING_SHORT="000000000000"
MISSING_BUILD_ID="$(cat "$ROOT/VERSION")+$MISSING_SHORT"
TREE_SHA="$(git -C "$ROOT" rev-parse HEAD^{tree})"
TREE_SHORT="$(git -C "$ROOT" rev-parse --short=12 "$TREE_SHA")"
TREE_BUILD_ID="$(cat "$ROOT/VERSION")+$TREE_SHORT"
BLOB_SHA="$(git -C "$ROOT" rev-parse HEAD:VERSION)"
BLOB_SHORT="$(git -C "$ROOT" rev-parse --short=12 "$BLOB_SHA")"
BLOB_BUILD_ID="$(cat "$ROOT/VERSION")+$BLOB_SHORT"
write_missing_uat() {
  _wmu_commit="$1"
  _wmu_build="$2"
  write_valid_uat
  /usr/bin/python3 - "$UAT" "$_wmu_commit" "$_wmu_build" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["commit"] = sys.argv[2]
payload["tested_build"]["build_id"] = sys.argv[3]
path.write_text(json.dumps(payload))
PY
}
write_missing_uat "$MISSING_COMMIT" "$MISSING_BUILD_ID"
assert_fail uat-missing-commit "$ROOT/script/validate-release-uat.sh" --evidence "$UAT" --commit "$MISSING_COMMIT" --expected-build-id "$MISSING_BUILD_ID" --expected-signing-identity "$TEST_SIGNING_IDENTITY"
assert_contains "$TMP/uat-missing-commit.err" "unknown commit object"
write_missing_uat "$TREE_SHA" "$TREE_BUILD_ID"
assert_fail uat-tree-not-commit "$ROOT/script/validate-release-uat.sh" --evidence "$UAT" --commit "$TREE_SHA" --expected-build-id "$TREE_BUILD_ID" --expected-signing-identity "$TEST_SIGNING_IDENTITY"
assert_contains "$TMP/uat-tree-not-commit.err" "unknown commit object"
write_missing_uat "$BLOB_SHA" "$BLOB_BUILD_ID"
assert_fail uat-blob-not-commit "$ROOT/script/validate-release-uat.sh" --evidence "$UAT" --commit "$BLOB_SHA" --expected-build-id "$BLOB_BUILD_ID" --expected-signing-identity "$TEST_SIGNING_IDENTITY"
assert_contains "$TMP/uat-blob-not-commit.err" "unknown commit object"
write_valid_uat
build_valid_approval "$APPROVAL"
build_missing_approval() {
  _bma_commit="$1"
  _bma_build="$2"
  write_missing_uat "$_bma_commit" "$_bma_build"
  "$ROOT/script/generate-release-record.py" manifest \
    --output "$APPROVAL_MANIFEST" \
    --version "$(cat "$ROOT/VERSION")" \
    --bundle-id "$EXPECTED_BUNDLE_ID" \
    --tag "v$(cat "$ROOT/VERSION")" \
    --commit "$_bma_commit" \
    --build-id "$_bma_build" \
    --build-number 1 \
    --architectures "$EXPECTED_ARCHITECTURES" \
    --minimum-macos "$EXPECTED_MIN_MACOS" \
    --artifact "$(basename "$APPROVAL_ARTIFACT")" \
    --artifact-size "$(stat -f%z "$APPROVAL_ARTIFACT")" \
    --artifact-sha256 "$APPROVAL_ARTIFACT_SHA" \
    --created-utc 2026-07-13T12:00:00Z \
    --signing-identity "$TEST_SIGNING_IDENTITY" \
    --validation-status passed \
    --public-release
  build_valid_approval "$APPROVAL"
  /usr/bin/python3 - "$APPROVAL_MANIFEST" "$APPROVAL" "$UAT" "$_bma_commit" <<'PY'
import hashlib, json, pathlib, sys
manifest_path = pathlib.Path(sys.argv[1])
approval_path = pathlib.Path(sys.argv[2])
uat_path = pathlib.Path(sys.argv[3])
commit = sys.argv[4]
manifest = json.loads(manifest_path.read_text())
manifest["commit"] = commit
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
approval = json.loads(approval_path.read_text())
approval["commit"] = commit
approval["manifest_sha256"] = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
approval["uat_evidence"]["sha256"] = hashlib.sha256(uat_path.read_bytes()).hexdigest()
approval_path.write_text(json.dumps(approval, indent=2, sort_keys=True) + "\n")
PY
}
# Note: build_valid_approval hardcodes CURRENT_COMMIT; the python fixup above
# rebinds manifest+approval to the missing/non-commit with rehashed outer
# hashes so the only failure is the commit-object gate.
build_missing_approval "$MISSING_COMMIT" "$MISSING_BUILD_ID"
assert_fail approval-missing-commit "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT" \
  --commit "$MISSING_COMMIT" --expected-build-id "$MISSING_BUILD_ID" --expected-signing-identity "$TEST_SIGNING_IDENTITY"
assert_contains "$TMP/approval-missing-commit.err" "unknown commit object"
build_missing_approval "$TREE_SHA" "$TREE_BUILD_ID"
assert_fail approval-tree-not-commit "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT" \
  --commit "$TREE_SHA" --expected-build-id "$TREE_BUILD_ID" --expected-signing-identity "$TEST_SIGNING_IDENTITY"
assert_contains "$TMP/approval-tree-not-commit.err" "unknown commit object"
build_missing_approval "$BLOB_SHA" "$BLOB_BUILD_ID"
assert_fail approval-blob-not-commit "$ROOT/script/validate-release-approval.sh" \
  --approval "$APPROVAL" --artifact "$APPROVAL_ARTIFACT" --manifest "$APPROVAL_MANIFEST" --uat "$UAT" \
  --commit "$BLOB_SHA" --expected-build-id "$BLOB_BUILD_ID" --expected-signing-identity "$TEST_SIGNING_IDENTITY"
assert_contains "$TMP/approval-blob-not-commit.err" "unknown commit object"
write_valid_uat
"$ROOT/script/generate-release-record.py" manifest \
  --output "$APPROVAL_MANIFEST" \
  --version "$(cat "$ROOT/VERSION")" \
  --bundle-id "$EXPECTED_BUNDLE_ID" \
  --tag "v$(cat "$ROOT/VERSION")" \
  --commit "$CURRENT_COMMIT" \
  --build-id "$EXPECTED_BUILD_ID" \
  --build-number 1 \
  --architectures "$EXPECTED_ARCHITECTURES" \
  --minimum-macos "$EXPECTED_MIN_MACOS" \
  --artifact "$(basename "$APPROVAL_ARTIFACT")" \
  --artifact-size "$(stat -f%z "$APPROVAL_ARTIFACT")" \
  --artifact-sha256 "$APPROVAL_ARTIFACT_SHA" \
  --created-utc 2026-07-13T12:00:00Z \
  --signing-identity "$TEST_SIGNING_IDENTITY" \
  --validation-status passed \
  --public-release
build_valid_approval "$APPROVAL"
ARTIFACT_COMMIT_DIR="$TMP/artifact-commit-fixture"
mkdir -p "$ARTIFACT_COMMIT_DIR"
printf 'dummy-artifact-bytes' >"$ARTIFACT_COMMIT_DIR/NikoMusicHub-$(cat "$ROOT/VERSION").dmg"
printf '{"schema_version":1}' >"$ARTIFACT_COMMIT_DIR/manifest.json"
assert_fail artifact-missing-commit "$ROOT/script/validate-release-artifact.sh" \
  --artifact "$ARTIFACT_COMMIT_DIR/NikoMusicHub-$(cat "$ROOT/VERSION").dmg" --manifest "$ARTIFACT_COMMIT_DIR/manifest.json" \
  --commit "$MISSING_COMMIT" --expected-build-id "$MISSING_BUILD_ID"
assert_contains "$TMP/artifact-missing-commit.err" "unknown commit object"
assert_fail artifact-tree-not-commit "$ROOT/script/validate-release-artifact.sh" \
  --artifact "$ARTIFACT_COMMIT_DIR/NikoMusicHub-$(cat "$ROOT/VERSION").dmg" --manifest "$ARTIFACT_COMMIT_DIR/manifest.json" \
  --commit "$TREE_SHA" --expected-build-id "$TREE_BUILD_ID"
assert_contains "$TMP/artifact-tree-not-commit.err" "unknown commit object"
assert_fail artifact-blob-not-commit "$ROOT/script/validate-release-artifact.sh" \
  --artifact "$ARTIFACT_COMMIT_DIR/NikoMusicHub-$(cat "$ROOT/VERSION").dmg" --manifest "$ARTIFACT_COMMIT_DIR/manifest.json" \
  --commit "$BLOB_SHA" --expected-build-id "$BLOB_BUILD_ID"
assert_contains "$TMP/artifact-blob-not-commit.err" "unknown commit object"

echo "== install-local destination guard stays fail-closed =="
assert_fail install-nonapp "$ROOT/script/install-local.sh" --app-path "$TMP/not-an-app-dir"
assert_contains "$TMP/install-nonapp.err" ".app"
assert_fail install-relative-app "$ROOT/script/install-local.sh" --app-path "relative/Name.app"
assert_contains "$TMP/install-relative-app.err" "must be absolute"
LINK_TARGET="$TMP/link-target"
mkdir -p "$LINK_TARGET"
ln -sfn "$LINK_TARGET" "$TMP/Link.app"
assert_fail install-symlink-dest "$ROOT/script/install-local.sh" --app-path "$TMP/Link.app"
assert_contains "$TMP/install-symlink-dest.err" "symlink"
WRONG_BUNDLE_DIR="$TMP/Wrong.app"
mkdir -p "$WRONG_BUNDLE_DIR/Contents"
cat >"$WRONG_BUNDLE_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.example.Wrong</string>
</dict></plist>
PLIST
assert_fail install-wrong-bundle "$ROOT/script/install-local.sh" --app-path "$WRONG_BUNDLE_DIR"
assert_contains "$TMP/install-wrong-bundle.err" "does not match canonical"
assert_contains "$ROOT/script/install-local.sh" 'mktemp -d'
assert_not_contains "$ROOT/script/install-local.sh" '.installing.$$'
assert_not_contains "$ROOT/script/install-local.sh" '.previous.$$'
assert_contains "$ROOT/script/install-local.sh" 'must be a .app bundle'
assert_contains "$ROOT/script/install-local.sh" 'must not be a symlink'
assert_contains "$ROOT/script/install-local.sh" 'does not match canonical'
assert_contains "$ROOT/script/install-local.sh" 'INSTALL_SUCCESS'
assert_contains "$ROOT/script/install-local.sh" 'MOVED_ORIGINAL'
assert_contains "$ROOT/script/install-local.sh" 'INSTALLED_CANDIDATE'
assert_contains "$ROOT/script/install-local.sh" 'rollback restore failed'
assert_contains "$ROOT/script/install-local.sh" 'temp dir retained'
assert_contains "$ROOT/script/install-local.sh" 'rollback blocked; candidate cleanup failed'
assert_contains "$ROOT/script/install-local.sh" 'candidate cleanup failed; candidate preserved'
assert_contains "$ROOT/script/install-local.sh" 'nmh_check_existing_destination() {'
assert_contains "$ROOT/script/install-local.sh" 'nmh_check_existing_destination || exit 1'
assert_order 'nmh_check_existing_destination || exit 1' 'nmh_build_bundle' "$ROOT/script/install-local.sh"
assert_order 'nmh_check_existing_destination || exit 1' 'mv "$APP_PATH" "$BACKUP_PATH"' "$ROOT/script/install-local.sh"
# The pre-replace (second) destination check must run after the stop and before
# the first mv. line_number/assert_order above select the FIRST (prebuild) call,
# so assert the second call structurally here; production invokes the helper
# twice (prebuild and pre-replace).
/usr/bin/python3 - "$ROOT/script/install-local.sh" <<'PY'
import pathlib
import sys
lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
def find_all(needle):
    return [i + 1 for i, line in enumerate(lines) if needle in line]
stop = find_all('nmh_stop_app_binary "$TARGET_APP_BINARY" true')
checks = find_all('nmh_check_existing_destination || exit 1')
mvs = find_all('mv "$APP_PATH" "$BACKUP_PATH"')
assert len(checks) == 2, f"expected exactly 2 destination checks, got {checks}"
assert len(stop) == 1, f"expected exactly 1 stop call, got {stop}"
assert mvs, "expected at least 1 mv of APP_PATH to BACKUP_PATH"
assert checks[0] < stop[0] < checks[1] < mvs[0], (
    f"expected prebuild check {checks[0]} < stop {stop[0]} < "
    f"pre-replace check {checks[1]} < mv {mvs[0]}"
)
PY

echo "== install-local rollback preserves originals (fixture) =="
CLEANUP_FN="$(awk '/^cleanup\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$ROOT/script/install-local.sh")"
[[ -n "$CLEANUP_FN" ]] || {
  echo "could not extract cleanup() from install-local.sh" >&2
  exit 1
}
ROLLBACK_FIX="$TMP/install-rollback-fail"
ROLLBACK_APP="$ROLLBACK_FIX/Candidate.app"
ROLLBACK_TMP="$ROLLBACK_FIX/.nmh-install.test"
ROLLBACK_BACKUP="$ROLLBACK_TMP/backup.app"
ROLLBACK_STAGING="$ROLLBACK_TMP/staging.app"
mkdir -p "$ROLLBACK_BACKUP/Contents" "$ROLLBACK_APP/Contents" "$ROLLBACK_STAGING"
printf 'original' >"$ROLLBACK_BACKUP/Contents/marker"
printf 'bad-candidate' >"$ROLLBACK_APP/Contents/marker"
(
  set +e
  eval "$CLEANUP_FN"
  mv() {
    echo "stub mv failure" >&2
    return 1
  }
  APP_PATH="$ROLLBACK_APP"
  INSTALL_TMP="$ROLLBACK_TMP"
  BACKUP_PATH="$ROLLBACK_BACKUP"
  STAGING_PATH="$ROLLBACK_STAGING"
  INSTALL_SUCCESS=false
  MOVED_ORIGINAL=true
  INSTALLED_CANDIDATE=true
  (exit 3)
  cleanup >"$TMP/rollback-restore-fail.out" 2>"$TMP/rollback-restore-fail.err"
  echo "$?" >"$TMP/rollback-restore-fail.status"
)
[[ "$(cat "$TMP/rollback-restore-fail.status")" == "3" ]] || {
  echo "rollback restore failure must preserve exit 3" >&2
  exit 1
}
[[ -d "$ROLLBACK_BACKUP" ]] || {
  echo "failed rollback must retain the surviving original bundle" >&2
  exit 1
}
[[ "$(cat "$ROLLBACK_BACKUP/Contents/marker")" == "original" ]] || {
  echo "failed rollback must not mutate the surviving original" >&2
  exit 1
}
[[ -d "$ROLLBACK_TMP" ]] || {
  echo "failed rollback must retain the temp dir for recovery" >&2
  exit 1
}
[[ ! -e "$ROLLBACK_STAGING" ]] || {
  echo "failed rollback must still clear staging" >&2
  exit 1
}
assert_contains "$TMP/rollback-restore-fail.err" "rollback restore failed"
assert_contains "$TMP/rollback-restore-fail.err" "$ROLLBACK_BACKUP"

echo "== install-local rm failure never nests backup inside leftover candidate =="
NEST_FIX="$TMP/install-rollback-nest"
NEST_APP="$NEST_FIX/Candidate.app"
NEST_TMP="$NEST_FIX/.nmh-install.test"
NEST_BACKUP="$NEST_TMP/backup.app"
NEST_STAGING="$NEST_FIX/.nmh-install.test/staging.app"
mkdir -p "$NEST_BACKUP/Contents" "$NEST_APP/Contents" "$NEST_TMP"
printf 'original' >"$NEST_BACKUP/Contents/marker"
printf 'leftover-candidate' >"$NEST_APP/Contents/marker"
MV_CALLED="$TMP/nest-mv-called"
rm -f "$MV_CALLED"
(
  set +e
  eval "$CLEANUP_FN"
  # Local stub rm failure: refuse to remove the candidate directory so the
  # leftover remains. A real BSD mv would then nest backup.app inside it and
  # return 0; cleanup must NOT call mv at all in this state.
  rm() {
    case "$*" in
      *"$NEST_APP"*) echo "stub rm failure (leaving $NEST_APP)" >&2; return 1 ;;
    esac
    command rm "$@"
  }
  mv() {
    touch "$MV_CALLED"
    echo "MUST NOT CALL mv when APP_PATH still exists (would nest backup)" >&2
    # Emulate the dangerous BSD success so the test would catch a nest.
    mkdir -p "$NEST_APP/backup.app"
    return 0
  }
  APP_PATH="$NEST_APP"
  INSTALL_TMP="$NEST_TMP"
  BACKUP_PATH="$NEST_BACKUP"
  STAGING_PATH="$NEST_STAGING"
  mkdir -p "$STAGING_PATH"
  INSTALL_SUCCESS=false
  MOVED_ORIGINAL=true
  INSTALLED_CANDIDATE=true
  (exit 3)
  cleanup >"$TMP/rollback-nest.out" 2>"$TMP/rollback-nest.err"
  echo "$?" >"$TMP/rollback-nest.status"
  unset -f rm mv
)
[[ "$(cat "$TMP/rollback-nest.status")" == "3" ]] || {
  echo "rm-failure rollback must preserve exit 3" >&2
  exit 1
}
[[ ! -e "$MV_CALLED" ]] || {
  echo "cleanup called mv while APP_PATH still existed (would nest backup.app)" >&2
  exit 1
}
[[ -d "$NEST_BACKUP" ]] || {
  echo "rm-failure rollback must leave the backup untouched at $NEST_BACKUP" >&2
  exit 1
}
[[ "$(cat "$NEST_BACKUP/Contents/marker")" == "original" ]] || {
  echo "rm-failure rollback must not mutate the backup" >&2
  exit 1
}
[[ -d "$NEST_APP" ]] || {
  echo "rm-failure rollback must not auto-delete the orphan candidate" >&2
  exit 1
}
[[ -d "$NEST_TMP" ]] || {
  echo "rm-failure rollback must retain the temp dir for recovery" >&2
  exit 1
}
[[ ! -e "$NEST_APP/backup.app" ]] || {
  echo "backup was nested inside the leftover candidate" >&2
  exit 1
}
assert_contains "$TMP/rollback-nest.err" "rollback blocked"
assert_contains "$TMP/rollback-nest.err" "$NEST_APP"
assert_contains "$TMP/rollback-nest.err" "$NEST_BACKUP"

echo "== install-local first-install failure removes only the candidate =="
FIRST_FIX="$TMP/install-first-fail"
FIRST_APP="$FIRST_FIX/New.app"
FIRST_TMP="$FIRST_FIX/.nmh-install.test"
FIRST_BACKUP="$FIRST_TMP/backup.app"
FIRST_STAGING="$FIRST_TMP/staging.app"
mkdir -p "$FIRST_APP/Contents" "$FIRST_TMP" "$FIRST_STAGING"
printf 'candidate' >"$FIRST_APP/Contents/marker"
(
  set +e
  eval "$CLEANUP_FN"
  APP_PATH="$FIRST_APP"
  INSTALL_TMP="$FIRST_TMP"
  BACKUP_PATH="$FIRST_BACKUP"
  STAGING_PATH="$FIRST_STAGING"
  INSTALL_SUCCESS=false
  MOVED_ORIGINAL=false
  INSTALLED_CANDIDATE=true
  (exit 5)
  cleanup >"$TMP/first-install-fail.out" 2>"$TMP/first-install-fail.err"
  echo "$?" >"$TMP/first-install-fail.status"
)
[[ "$(cat "$TMP/first-install-fail.status")" == "5" ]] || {
  echo "first-install failure must preserve exit 5" >&2
  exit 1
}
[[ ! -e "$FIRST_APP" ]] || {
  echo "first-install failure must remove the candidate it installed" >&2
  exit 1
}
[[ ! -e "$FIRST_TMP" ]] || {
  echo "first-install failure must clean its temp dir" >&2
  exit 1
}

echo "== install-local first-install rm failure preserves candidate (fixture) =="
FIRST_STUCK_FIX="$TMP/install-first-stuck"
FIRST_STUCK_APP="$FIRST_STUCK_FIX/New.app"
FIRST_STUCK_TMP="$FIRST_STUCK_FIX/.nmh-install.test"
FIRST_STUCK_BACKUP="$FIRST_STUCK_TMP/backup.app"
FIRST_STUCK_STAGING="$FIRST_STUCK_TMP/staging.app"
mkdir -p "$FIRST_STUCK_APP/Contents" "$FIRST_STUCK_TMP" "$FIRST_STUCK_STAGING"
printf 'stuck-candidate' >"$FIRST_STUCK_APP/Contents/marker"
(
  set +e
  eval "$CLEANUP_FN"
  rm() {
    case "$*" in
      *"$FIRST_STUCK_APP"*) echo "stub rm failure (leaving $FIRST_STUCK_APP)" >&2; return 1 ;;
    esac
    command rm "$@"
  }
  APP_PATH="$FIRST_STUCK_APP"
  INSTALL_TMP="$FIRST_STUCK_TMP"
  BACKUP_PATH="$FIRST_STUCK_BACKUP"
  STAGING_PATH="$FIRST_STUCK_STAGING"
  INSTALL_SUCCESS=false
  MOVED_ORIGINAL=false
  INSTALLED_CANDIDATE=true
  (exit 5)
  cleanup >"$TMP/first-stuck.out" 2>"$TMP/first-stuck.err"
  echo "$?" >"$TMP/first-stuck.status"
  unset -f rm
)
[[ "$(cat "$TMP/first-stuck.status")" == "5" ]] || {
  echo "stuck first-install failure must preserve exit 5 (not claim cleanup success)" >&2
  exit 1
}
[[ -d "$FIRST_STUCK_APP" ]] || {
  echo "stuck first-install must preserve the leftover candidate path" >&2
  exit 1
}
assert_contains "$TMP/first-stuck.err" "candidate cleanup failed"
assert_contains "$TMP/first-stuck.err" "$FIRST_STUCK_APP"
[[ -d "$FIRST_STUCK_TMP" ]] || {
  echo "stuck first-install must retain the temp dir for recovery" >&2
  exit 1
}

echo "== install-local staging failure never deletes an uninstalled destination =="
NOINSTALL_FIX="$TMP/install-no-install"
NOINSTALL_APP="$NOINSTALL_FIX/Existing.app"
NOINSTALL_TMP="$NOINSTALL_FIX/.nmh-install.test"
NOINSTALL_BACKUP="$NOINSTALL_TMP/backup.app"
NOINSTALL_STAGING="$NOINSTALL_TMP/staging.app"
mkdir -p "$NOINSTALL_APP/Contents" "$NOINSTALL_TMP" "$NOINSTALL_STAGING"
printf 'original' >"$NOINSTALL_APP/Contents/marker"
(
  set +e
  eval "$CLEANUP_FN"
  APP_PATH="$NOINSTALL_APP"
  INSTALL_TMP="$NOINSTALL_TMP"
  BACKUP_PATH="$NOINSTALL_BACKUP"
  STAGING_PATH="$NOINSTALL_STAGING"
  INSTALL_SUCCESS=false
  MOVED_ORIGINAL=false
  INSTALLED_CANDIDATE=false
  (exit 7)
  cleanup >"$TMP/no-install.out" 2>"$TMP/no-install.err"
  echo "$?" >"$TMP/no-install.status"
)
[[ "$(cat "$TMP/no-install.status")" == "7" ]] || {
  echo "staging failure must preserve exit 7" >&2
  exit 1
}
[[ -d "$NOINSTALL_APP" ]] || {
  echo "cleanup must not delete a destination it never installed" >&2
  exit 1
}
[[ "$(cat "$NOINSTALL_APP/Contents/marker")" == "original" ]] || {
  echo "cleanup must not mutate an uninstalled destination" >&2
  exit 1
}

echo "== install-local pre-replace identity re-check (fixture) =="
DEST_FN="$(awk '/^nmh_check_existing_destination\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$ROOT/script/install-local.sh")"
[[ -n "$DEST_FN" ]] || {
  echo "could not extract nmh_check_existing_destination() from install-local.sh" >&2
  exit 1
}
# Helper is the small shared check called both prebuild and pre-replace; the
# script must call it twice (before the long build and immediately before the
# first mv), with no bypass flag.
[[ "$(grep -c 'nmh_check_existing_destination || exit 1' "$ROOT/script/install-local.sh")" == "2" ]] || {
  echo "install-local.sh must call nmh_check_existing_destination both prebuild and pre-replace" >&2
  exit 1
}
assert_not_contains "$ROOT/script/install-local.sh" "NMH_SKIP_DESTINATION_CHECK"
assert_not_contains "$ROOT/script/install-local.sh" "--skip-destination-check"
# Simulate a destination swapped to a foreign bundle between phases: the
# re-check must fail and leave the tree unchanged.
SWAP_FIX="$TMP/install-swap"
SWAP_APP="$SWAP_FIX/Swapped.app"
mkdir -p "$SWAP_APP/Contents"
cat >"$SWAP_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.example.Evil</string>
</dict></plist>
PLIST
printf 'evil' >"$SWAP_APP/Contents/marker"
(
  set +e
  eval "$DEST_FN"
  APP_PATH="$SWAP_APP"
  NMH_CANONICAL_BUNDLE_ID="$EXPECTED_BUNDLE_ID"
  nmh_check_existing_destination >"$TMP/swap-foreign.out" 2>"$TMP/swap-foreign.err"
  echo "$?" >"$TMP/swap-foreign.status"
)
[[ "$(cat "$TMP/swap-foreign.status")" != "0" ]] || {
  echo "swapped foreign bundle must be rejected by the pre-replace check" >&2
  exit 1
}
assert_contains "$TMP/swap-foreign.err" "does not match canonical"
[[ "$(cat "$SWAP_APP/Contents/marker")" == "evil" ]] || {
  echo "failed identity check must leave the swapped tree unchanged" >&2
  exit 1
}
# Simulate a destination swapped to a symlink between phases.
SYMLINK_FIX="$TMP/install-swap-symlink"
SYMLINK_TARGET="$SYMLINK_FIX/target"
SYMLINK_APP="$SYMLINK_FIX/Swapped.app"
mkdir -p "$SYMLINK_TARGET"
ln -sfn "$SYMLINK_TARGET" "$SYMLINK_APP"
(
  set +e
  eval "$DEST_FN"
  APP_PATH="$SYMLINK_APP"
  NMH_CANONICAL_BUNDLE_ID="$EXPECTED_BUNDLE_ID"
  nmh_check_existing_destination >"$TMP/swap-symlink.out" 2>"$TMP/swap-symlink.err"
  echo "$?" >"$TMP/swap-symlink.status"
)
[[ "$(cat "$TMP/swap-symlink.status")" != "0" ]] || {
  echo "swapped symlink destination must be rejected by the pre-replace check" >&2
  exit 1
}
assert_contains "$TMP/swap-symlink.err" "must be a .app directory"
[[ -L "$SYMLINK_APP" ]] || {
  echo "failed symlink check must leave the symlink unchanged" >&2
  exit 1
}

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

echo "== update feed binds the candidate bundle =="
assert_contains "$ROOT/script/validate-update-feed.py" "CFBundleShortVersionString"
assert_contains "$ROOT/script/validate-update-feed.py" "CFBundleVersion"
assert_contains "$ROOT/script/validate-update-feed.py" "exactly one arm64"
assert_contains "$ROOT/script/validate-update-feed.py" "exactly one full enclosure"
assert_contains "$ROOT/script/validate-update-feed.py" "deltaFrom"
assert_not_contains "$ROOT/script/validate-update-feed.py" 'if len(expected_architectures) == 1:'
FEED_DIR="$TMP/feed"
FEED_GOOD="$TMP/feed-good"
FEED_VERSION="9.9.9"
FEED_BUILD="4242"
FEED_MIN_MACOS="14.2"
FEED_URL="https://example.invalid/NikoMusicHub-$FEED_VERSION.dmg"
/usr/bin/python3 - "$FEED_DIR" "$FEED_VERSION" "$FEED_BUILD" "$FEED_MIN_MACOS" "$FEED_URL" <<'PY'
import base64
import plistlib
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ed25519

feed_dir, version, build, minimum_macos, enclosure_url = sys.argv[1:6]
root = Path(feed_dir)
root.mkdir(parents=True, exist_ok=True)

private_key = ed25519.Ed25519PrivateKey.generate()
public_key = base64.b64encode(
    private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw, format=serialization.PublicFormat.Raw
    )
).decode("ascii")

artifact = root / "update.bin"
artifact.write_bytes(b"feed-fixture-artifact-bytes")
signature = base64.b64encode(private_key.sign(artifact.read_bytes())).decode("ascii")

app = root / "Fixture.app"
(app / "Contents").mkdir(parents=True, exist_ok=True)
with (app / "Contents" / "Info.plist").open("wb") as handle:
    plistlib.dump(
        {
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "SUFeedURL": "https://example.invalid/appcast.xml",
            "SUPublicEDKey": public_key,
        },
        handle,
    )

ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ElementTree.register_namespace("sparkle", ns)
rss = ElementTree.Element("rss", {"version": "2.0"})
channel = ElementTree.SubElement(rss, "channel")
ElementTree.SubElement(channel, "title").text = "Fixture"
item = ElementTree.SubElement(channel, "item")
ElementTree.SubElement(item, "title").text = version
ElementTree.SubElement(item, "description").text = "Fixture notes."
ElementTree.SubElement(item, f"{{{ns}}}shortVersionString").text = version
ElementTree.SubElement(item, f"{{{ns}}}version").text = build
ElementTree.SubElement(item, f"{{{ns}}}minimumSystemVersion").text = minimum_macos
ElementTree.SubElement(item, f"{{{ns}}}hardwareRequirements").text = "arm64"
enclosure = ElementTree.SubElement(item, "enclosure")
enclosure.set("url", enclosure_url)
enclosure.set("length", str(len(artifact.read_bytes())))
enclosure.set(f"{{{ns}}}edSignature", signature)
ElementTree.ElementTree(rss).write(root / "appcast.xml", xml_declaration=True)
PY
rm -rf "$FEED_GOOD"
cp -r "$FEED_DIR" "$FEED_GOOD"
restore_feed() {
  rm -rf "$FEED_DIR"
  cp -r "$FEED_GOOD" "$FEED_DIR"
}
feed_args() {
  printf '%s\n' "$ROOT/script/validate-update-feed.py" \
    --appcast "$FEED_DIR/appcast.xml" \
    --artifact "$FEED_DIR/update.bin" \
    --app "$FEED_DIR/Fixture.app" \
    --version "$FEED_VERSION" \
    --build-number "$FEED_BUILD" \
    --minimum-macos "$FEED_MIN_MACOS" \
    --architectures "arm64" \
    --expected-enclosure-url "$FEED_URL"
}
assert_pass feed-valid /usr/bin/python3 $(feed_args)
/usr/bin/python3 - "$FEED_DIR/Fixture.app/Contents/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path
path = Path(sys.argv[1])
with path.open("rb") as handle:
    info = plistlib.load(handle)
info["CFBundleVersion"] = "4241"
with path.open("wb") as handle:
    plistlib.dump(info, handle)
PY
assert_fail feed-stale-bundle-build /usr/bin/python3 $(feed_args)
assert_contains "$TMP/feed-stale-bundle-build.err" "CFBundleVersion"
restore_feed
/usr/bin/python3 - "$FEED_DIR/Fixture.app/Contents/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path
path = Path(sys.argv[1])
with path.open("rb") as handle:
    info = plistlib.load(handle)
info["CFBundleShortVersionString"] = "9.9.8"
with path.open("wb") as handle:
    plistlib.dump(info, handle)
PY
assert_fail feed-bundle-short-mismatch /usr/bin/python3 $(feed_args)
assert_contains "$TMP/feed-bundle-short-mismatch.err" "CFBundleShortVersionString"
restore_feed
/usr/bin/python3 - "$FEED_DIR/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path
path = Path(sys.argv[1])
ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ElementTree.register_namespace("sparkle", ns)
tree = ElementTree.parse(path)
item = tree.getroot().find("./channel/item")
item.find(f"{{{ns}}}version").text = "4241"
tree.write(path, xml_declaration=True)
PY
assert_fail feed-stale-sparkle-version /usr/bin/python3 $(feed_args)
assert_contains "$TMP/feed-stale-sparkle-version.err" "sparkle:version"
restore_feed
assert_fail feed-zero-architectures /usr/bin/python3 "$ROOT/script/validate-update-feed.py" \
  --appcast "$FEED_DIR/appcast.xml" \
  --artifact "$FEED_DIR/update.bin" \
  --app "$FEED_DIR/Fixture.app" \
  --version "$FEED_VERSION" \
  --build-number "$FEED_BUILD" \
  --minimum-macos "$FEED_MIN_MACOS" \
  --architectures "" \
  --expected-enclosure-url "$FEED_URL"
assert_contains "$TMP/feed-zero-architectures.err" "exactly one arm64"
assert_fail feed-multiple-architectures /usr/bin/python3 "$ROOT/script/validate-update-feed.py" \
  --appcast "$FEED_DIR/appcast.xml" \
  --artifact "$FEED_DIR/update.bin" \
  --app "$FEED_DIR/Fixture.app" \
  --version "$FEED_VERSION" \
  --build-number "$FEED_BUILD" \
  --minimum-macos "$FEED_MIN_MACOS" \
  --architectures "arm64 x86_64" \
  --expected-enclosure-url "$FEED_URL"
assert_contains "$TMP/feed-multiple-architectures.err" "exactly one arm64"
/usr/bin/python3 - "$FEED_DIR/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path
path = Path(sys.argv[1])
ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ElementTree.register_namespace("sparkle", ns)
tree = ElementTree.parse(path)
item = tree.getroot().find("./channel/item")
item.find(f"{{{ns}}}hardwareRequirements").text = "x86_64"
tree.write(path, xml_declaration=True)
PY
assert_fail feed-wrong-hardware /usr/bin/python3 $(feed_args)
assert_contains "$TMP/feed-wrong-hardware.err" "hardwareRequirements"
restore_feed
/usr/bin/python3 - "$FEED_DIR/appcast.xml" <<'PY'
import copy
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path
path = Path(sys.argv[1])
ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ElementTree.register_namespace("sparkle", ns)
tree = ElementTree.parse(path)
item = tree.getroot().find("./channel/item")
item.append(copy.deepcopy(item.find("enclosure")))
tree.write(path, xml_declaration=True)
PY
assert_fail feed-extra-enclosure /usr/bin/python3 $(feed_args)
assert_contains "$TMP/feed-extra-enclosure.err" "exactly one full enclosure"
restore_feed
/usr/bin/python3 - "$FEED_DIR/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path
path = Path(sys.argv[1])
ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ElementTree.register_namespace("sparkle", ns)
tree = ElementTree.parse(path)
item = tree.getroot().find("./channel/item")
item.find("enclosure").set(f"{{{ns}}}deltaFrom", "4241")
tree.write(path, xml_declaration=True)
PY
assert_fail feed-delta-enclosure /usr/bin/python3 $(feed_args)
assert_contains "$TMP/feed-delta-enclosure.err" "deltaFrom"
restore_feed

echo "== release metadata validator =="
assert_contains "$ROOT/script/release-version-verify.sh" "validate-release-metadata.py"
assert_pass metadata-valid /usr/bin/python3 "$ROOT/script/validate-release-metadata.py" --root "$ROOT"
META="$TMP/metadata"
mkdir -p "$META"
cp "$ROOT/SBOM.spdx.json" "$META/SBOM.spdx.json"
cp "$ROOT/Package.resolved" "$META/Package.resolved"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$META/THIRD_PARTY_NOTICES.md"
cp "$ROOT/SOURCE_PROVENANCE.md" "$META/SOURCE_PROVENANCE.md"
cp "$ROOT/VERSION" "$META/VERSION"
assert_pass metadata-fixture-valid /usr/bin/python3 "$ROOT/script/validate-release-metadata.py" --root "$META"
/usr/bin/python3 - "$META/SBOM.spdx.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = json.loads(path.read_text())
for package in payload["packages"]:
    if str(package.get("name", "")).lower() == "sparkle":
        package["versionInfo"] = "2.9.5"
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
assert_fail metadata-stale-sbom-version /usr/bin/python3 "$ROOT/script/validate-release-metadata.py" --root "$META"
assert_contains "$TMP/metadata-stale-sbom-version.err" "versionInfo"
cp "$ROOT/SBOM.spdx.json" "$META/SBOM.spdx.json"
/usr/bin/python3 - "$META/SBOM.spdx.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = json.loads(path.read_text())
for package in payload["packages"]:
    if str(package.get("name", "")).lower() == "sparkle":
        package["downloadLocation"] = package["downloadLocation"].split("@")[0] + "@" + "0" * 40
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
assert_fail metadata-stale-sbom-revision /usr/bin/python3 "$ROOT/script/validate-release-metadata.py" --root "$META"
assert_contains "$TMP/metadata-stale-sbom-revision.err" "resolved revision"
cp "$ROOT/SBOM.spdx.json" "$META/SBOM.spdx.json"
/usr/bin/python3 - "$META/SBOM.spdx.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = json.loads(path.read_text())
kept = []
removed_id = None
for package in payload["packages"]:
    if str(package.get("name", "")).lower() == "sparkle":
        removed_id = package.get("SPDXID")
        continue
    kept.append(package)
payload["packages"] = kept
payload["relationships"] = [
    relationship for relationship in payload.get("relationships", [])
    if relationship.get("relatedSpdxElement") != removed_id
]
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
assert_fail metadata-missing-package /usr/bin/python3 "$ROOT/script/validate-release-metadata.py" --root "$META"
assert_contains "$TMP/metadata-missing-package.err" "missing a package"
cp "$ROOT/SBOM.spdx.json" "$META/SBOM.spdx.json"
/usr/bin/python3 - "$META/SBOM.spdx.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["packages"].append(
    {
        "SPDXID": "SPDXRef-Package-Evil",
        "name": "EvilLib",
        "versionInfo": "1.0",
        "downloadLocation": "https://example.invalid/evil",
        "filesAnalyzed": False,
        "licenseConcluded": "NOASSERTION",
        "licenseDeclared": "NOASSERTION",
        "copyrightText": "NOASSERTION",
    }
)
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
assert_fail metadata-extra-package /usr/bin/python3 "$ROOT/script/validate-release-metadata.py" --root "$META"
assert_contains "$TMP/metadata-extra-package.err" "extra package"
cp "$ROOT/SBOM.spdx.json" "$META/SBOM.spdx.json"
/usr/bin/python3 - "$META/SBOM.spdx.json" <<'PY'
import copy
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = json.loads(path.read_text())
for package in list(payload["packages"]):
    if str(package.get("name", "")).lower() == "sparkle":
        duplicate = copy.deepcopy(package)
        duplicate["SPDXID"] = "SPDXRef-Package-Sparkle-Duplicate"
        payload["packages"].append(duplicate)
        break
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
assert_fail metadata-duplicate-package /usr/bin/python3 "$ROOT/script/validate-release-metadata.py" --root "$META"
assert_contains "$TMP/metadata-duplicate-package.err" "duplicate"
cp "$ROOT/SBOM.spdx.json" "$META/SBOM.spdx.json"
sed 's/2\.9\.6/2.9.5/g' "$ROOT/THIRD_PARTY_NOTICES.md" >"$META/THIRD_PARTY_NOTICES.md"
assert_fail metadata-notices-stale /usr/bin/python3 "$ROOT/script/validate-release-metadata.py" --root "$META"
assert_contains "$TMP/metadata-notices-stale.err" "resolved version"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$META/THIRD_PARTY_NOTICES.md"
sed 's/Sparkle/Redacted/g' "$ROOT/SOURCE_PROVENANCE.md" >"$META/SOURCE_PROVENANCE.md"
assert_fail metadata-provenance-missing /usr/bin/python3 "$ROOT/script/validate-release-metadata.py" --root "$META"
assert_contains "$TMP/metadata-provenance-missing.err" "no coverage"
cp "$ROOT/SOURCE_PROVENANCE.md" "$META/SOURCE_PROVENANCE.md"
assert_pass metadata-fixture-restored /usr/bin/python3 "$ROOT/script/validate-release-metadata.py" --root "$META"

echo "== public preflight proves its tools before lengthy gates =="
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool rg"
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool swift"
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool xcrun"
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool codesign"
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool hdiutil"
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool plutil"
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool spctl"
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool ditto"
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool curl"
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool shasum"
assert_contains "$ROOT/script/release-preflight.sh" "require_public_tool lipo"
assert_contains "$ROOT/script/release-preflight.sh" "/usr/libexec/PlistBuddy"
assert_contains "$ROOT/script/release-preflight.sh" "xcrun --find notarytool"
assert_contains "$ROOT/script/release-preflight.sh" "xcrun --find stapler"
assert_contains "$ROOT/script/release-preflight.sh" "swift --version"
assert_contains "$ROOT/script/release-preflight.sh" "Swift 6"
assert_contains "$ROOT/script/release-preflight.sh" 'if [[ -n "${DEVELOPER_DIR:-}" ]]'
assert_contains "$ROOT/script/release-preflight.sh" 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift --version'
assert_contains "$ROOT/script/lib/app_lifecycle.sh" 'DEVELOPER_DIR="$DEVELOPER_DIR" swift "$@"'
assert_contains "$ROOT/script/lib/app_lifecycle.sh" 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift "$@"'
assert_contains "$ROOT/script/release-preflight.sh" "cryptography"
assert_not_contains "$ROOT/script/release-preflight.sh" "command -v gh"
assert_not_contains "$ROOT/script/release-preflight.sh" "generate_appcast"
assert_not_contains "$ROOT/script/release-preflight.sh" ".build/artifacts"
SWIFT_SELECT_FN="$(awk '/^release_swift_version\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$ROOT/script/release-preflight.sh")"
SWIFT_STUB_BIN="$TMP/preflight-swift-bin"
SWIFT_STUB_RECORD="$TMP/preflight-swift-developer-dir"
mkdir -p "$SWIFT_STUB_BIN"
cat >"$SWIFT_STUB_BIN/swift" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${DEVELOPER_DIR:-}" >"$NMH_SWIFT_STUB_RECORD"
echo "Swift version 6.99.0"
STUB
chmod +x "$SWIFT_STUB_BIN/swift"
PATH="$SWIFT_STUB_BIN:$PATH" DEVELOPER_DIR="$TMP/SelectedDeveloper" NMH_SWIFT_STUB_RECORD="$SWIFT_STUB_RECORD" \
  bash -c "set -euo pipefail; $SWIFT_SELECT_FN; release_swift_version" >"$TMP/preflight-swift.out"
[[ "$(cat "$SWIFT_STUB_RECORD")" == "$TMP/SelectedDeveloper" ]] || {
  echo "release preflight did not propagate DEVELOPER_DIR to the selected Swift compiler" >&2
  exit 1
}
assert_contains "$TMP/preflight-swift.out" "Swift version 6.99.0"
NO_RG_BIN="$TMP/preflight-no-rg-bin"
mkdir -p "$NO_RG_BIN"
ln -sf "$(command -v git)" "$NO_RG_BIN/git"
ln -sf "$(command -v awk)" "$NO_RG_BIN/awk"
ln -sf "$(command -v bash)" "$NO_RG_BIN/bash"
assert_fail preflight-missing-rg env PATH="$NO_RG_BIN" "$ROOT/script/release-preflight.sh" --root "$PREFLIGHT_REPO"
assert_contains "$TMP/preflight-missing-rg.err" "missing required tool 'rg'"

echo "== public release refuses test-feed key files =="
assert_contains "$ROOT/script/release-all.sh" "NMH_SPARKLE_PRIVATE_KEY_FILE"
assert_contains "$ROOT/script/release-all.sh" "test feeds only"
assert_contains "$ROOT/script/release-all.sh" '--ed-key-file "$NMH_SPARKLE_PRIVATE_KEY_FILE"'
assert_fail public-private-key-file env NMH_DEVELOPER_ID_APPLICATION=test NMH_NOTARY_PROFILE=test NMH_RELEASE_UAT_EVIDENCE=/dev/null NMH_SPARKLE_PRIVATE_KEY_FILE=/tmp/nmh-test-key-file "$ROOT/script/release-all.sh" --public --dry-run-publish
assert_contains "$TMP/public-private-key-file.err" "NMH_SPARKLE_PRIVATE_KEY_FILE"

echo "== local-only feeds never fall back to Keychain signing =="
assert_contains "$ROOT/script/release-all.sh" 'elif [[ "$MODE" == "local-only" && -z "${NMH_SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then'
assert_contains "$ROOT/script/release-all.sh" "update feed skipped; set NMH_SPARKLE_PRIVATE_KEY_FILE to a throwaway private key"
assert_contains "$ROOT/script/release-all.sh" 'key_options=(--account "${NMH_SPARKLE_KEY_ACCOUNT:-ed25519}")'
assert_order 'elif [[ "$MODE" == "local-only" && -z "${NMH_SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then' 'run update-feed generate_update_feed "$DMG" "$RELEASE_NOTES" "$APP"' "$ROOT/script/release-all.sh"
GENERATE_UPDATE_FEED_FN="$(awk '/^generate_update_feed\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$ROOT/script/release-all.sh")"
KEYCHAIN_PROBE="$TMP/local-feed-keychain-probe"
assert_fail local-feed-missing-test-key bash -c "set -euo pipefail
$GENERATE_UPDATE_FEED_FN
find_generate_appcast() { touch '$KEYCHAIN_PROBE'; return 1; }
MODE=local-only
RELEASE_DIR='$TMP'
unset NMH_SPARKLE_PRIVATE_KEY_FILE
generate_update_feed /dev/null /dev/null /dev/null"
assert_contains "$TMP/local-feed-missing-test-key.err" "local-only update feed generation requires NMH_SPARKLE_PRIVATE_KEY_FILE"
[[ ! -e "$KEYCHAIN_PROBE" ]] || {
  echo "local-only feed attempted to resolve the signing tool without an explicit test key" >&2
  exit 1
}

echo "release script regression tests passed."
