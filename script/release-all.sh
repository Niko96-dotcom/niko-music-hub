#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-env.sh
source "$ROOT/script/release-env.sh"

MODE=""
PUBLISH=false
DRY_RUN_PUBLISH=false
SKIP_TESTS=false
EMERGENCY_SKIP_TESTS=false
EMERGENCY_REASON=""
INSTALL_SMOKE=false
RELEASE_DIR="${NMH_RELEASE_DIR:-$ROOT/dist/release}"
LOG_FILE="${NMH_RELEASE_LOG:-}"

validate_release_output_directory() {
  /usr/bin/python3 - "$ROOT/dist" "$RELEASE_DIR" <<'PY'
import os
import sys

root = os.path.realpath(sys.argv[1])
candidate = os.path.abspath(sys.argv[2])
if candidate == root or os.path.commonpath([root, candidate]) != root:
    raise SystemExit(f"release output must be a child of {root}: {candidate}")

current = os.path.sep
for component in candidate.strip(os.path.sep).split(os.path.sep):
    current = os.path.join(current, component)
    if os.path.lexists(current) and os.path.islink(current):
        raise SystemExit(f"release output must not traverse a symlink: {current}")

resolved = os.path.realpath(candidate)
if os.path.commonpath([root, resolved]) != root:
    raise SystemExit(f"release output resolves outside {root}: {resolved}")
print(resolved)
PY
}

require_clean_release_worktree() {
  local status
  status="$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)"
  if [[ -n "$status" ]]; then
    echo "release artifacts require a completely clean working tree, including untracked files; use ./script/dev.sh run for dirty local development builds" >&2
    printf '%s\n' "$status" >&2
    return 1
  fi
}

usage() {
  cat >&2 <<'USAGE'
usage:
  script/release-all.sh --local-only [--skip-tests] [--install-smoke]
  script/release-all.sh --public (--publish|--dry-run-publish) [--install-smoke]
  script/release-all.sh --public (--publish|--dry-run-publish) --emergency-skip-tests --reason "..."

Public mode requires:
  NMH_DEVELOPER_ID_APPLICATION
  NMH_NOTARY_PROFILE
  NMH_RELEASE_UAT_EVIDENCE (approved JSON matching the exact version and commit)
  Git tag v<VERSION> pointing at HEAD
  Completely clean working tree, including untracked files
  gh auth when --publish is used

All release artifacts require a completely clean working tree, including untracked files.
Local-only mode is explicitly unsigned/unnotarized and cannot publish; use `./script/dev.sh run` for dirty local development builds.
USAGE
}

log() {
  printf '== %s ==\n' "$*"
  if [[ -n "$LOG_FILE" ]]; then
    printf '== %s ==\n' "$*" >>"$LOG_FILE"
  fi
}

run() {
  if [[ -n "$LOG_FILE" ]]; then
    printf '+ %q' "$1" >>"$LOG_FILE"
    shift
    printf ' %q' "$@" >>"$LOG_FILE"
    printf '\n' >>"$LOG_FILE"
    "$@" 2>&1 | tee -a "$LOG_FILE"
  else
    "$@"
  fi
}

# Submit to the notary service, retrying only transport failures. A verdict of
# Invalid is final: fetch Apple's log next to the release output so the reason is
# in the record instead of buried in a browser session.
notarize() {
  local label="$1" file="$2" attempt output submission_id
  for attempt in 1 2 3; do
    # Never pipe into `grep -q` under pipefail: grep can exit before the writer
    # finishes and the SIGPIPE turns a verdict into a false failure (that
    # aborted a rehearsal right after "status: Accepted"). Grep here-strings.
    output="$(xcrun notarytool submit "$file" --keychain-profile "$NMH_NOTARY_PROFILE" --wait 2>&1)" || true
    printf '%s\n' "$output" >>"$LOG_FILE"
    printf '%s\n' "$output"
    if grep -q 'status: Accepted' <<<"$output"; then
      return 0
    fi
    if grep -q 'status: Invalid' <<<"$output"; then
      submission_id="$(grep -m1 -E '^ *id: ' <<<"$output" | awk '{print $2}')"
      if [[ -n "$submission_id" ]]; then
        xcrun notarytool log "$submission_id" --keychain-profile "$NMH_NOTARY_PROFILE" \
          >"$RELEASE_DIR/notary-$label-$submission_id.json" 2>&1 || true
        echo "notarization of $label rejected; Apple's log: $RELEASE_DIR/notary-$label-$submission_id.json" >&2
      fi
      return 1
    fi
    if grep -Eq 'deadlineExceeded|HTTPClientError|connection|timed out' <<<"$output"; then
      echo "notary upload of $label failed on attempt $attempt (transport); retrying in 30s" | tee -a "$LOG_FILE" >&2
      sleep 30
      continue
    fi
    return 1
  done
  echo "notarization of $label failed after 3 upload attempts" >&2
  return 1
}

# Notarization rejects any Developer ID signature without a secure timestamp or
# hardened runtime, and it checks every nested binary, not just the app wrapper
# (the first public release was refused for Sparkle's helpers). dyld additionally
# refuses to load a framework signed by another team under library validation,
# and the app's entitlements must not leak onto Sparkle's helpers. Prove all of
# it locally before uploading instead of after eight minutes of gates.
require_secure_timestamps() {
  local app="$1" nested signature entitlements team
  team="$(codesign -dvv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true)"
  if [[ -z "$team" || "$team" == "not set" ]]; then
    echo "app signature has no TeamIdentifier (not a Developer ID signature): $app" >&2
    return 1
  fi
  for nested in \
    "$app" \
    "$app/Contents/Frameworks/Sparkle.framework/Versions/B" \
    "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
    "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
    "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/"*.xpc; do
    [[ -e "$nested" ]] || continue
    # Capture first: under `set -o pipefail` a `codesign | grep -q` pipeline can
    # fail with SIGPIPE when grep exits early, which read as "no timestamp" for
    # the app wrapper in an earlier release rehearsal.
    signature="$(codesign -dvv "$nested" 2>&1 || true)"
    if ! grep -q '^Timestamp=' <<<"$signature"; then
      echo "signature without a secure timestamp (notarization would reject it): $nested" >&2
      return 1
    fi
    if ! grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<<"$signature"; then
      echo "signature without hardened runtime (notarization would reject it): $nested" >&2
      return 1
    fi
    if ! grep -q "^TeamIdentifier=$team\$" <<<"$signature"; then
      echo "nested code signed by another team (library validation would refuse to load it): $nested" >&2
      return 1
    fi
    entitlements="$(codesign -d --entitlements - --xml "$nested" 2>/dev/null || true)"
    if [[ "$nested" != "$app" && "$entitlements" == *'<key>'* ]]; then
      echo "Sparkle helper carries entitlements; nmh_sign_bundle must sign helpers without --entitlements: $nested" >&2
      return 1
    fi
  done
}

# The entitlement set is part of the release contract: audio-input is what the
# recorder's Core Audio tap needs under hardened runtime, and nothing else
# (get-task-allow, disable-library-validation, ...) may ride along.
NMH_EXPECTED_APP_ENTITLEMENTS='{"com.apple.security.device.audio-input":true}'
require_expected_entitlements() {
  local app="$1" actual
  actual="$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || true)"
  if [[ "$actual" != "$NMH_EXPECTED_APP_ENTITLEMENTS" ]]; then
    echo "app entitlements drifted: got '$actual', expected '$NMH_EXPECTED_APP_ENTITLEMENTS'" >&2
    return 1
  fi
}

verify_remote_release_tag() {
  local remote_refs remote_tag_ref="" remote_tag_peeled="" remote_tag_commit="" object ref

  if ! remote_refs="$(git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}")"; then
    echo "public publish could not inspect remote tag $TAG on origin" >&2
    return 1
  fi

  while IFS=$'\t' read -r object ref; do
    case "$ref" in
      "refs/tags/$TAG") remote_tag_ref="$object" ;;
      "refs/tags/$TAG^{}") remote_tag_peeled="$object" ;;
    esac
  done <<<"$remote_refs"

  # An annotated tag has a peeled commit ref; a lightweight tag points directly
  # to its commit. Either form must resolve to the exact local release commit.
  remote_tag_commit="${remote_tag_peeled:-$remote_tag_ref}"
  if [[ -z "$remote_tag_ref" || "$remote_tag_commit" != "$COMMIT" ]]; then
    echo "public publish requires remote tag $TAG on origin to resolve exactly to local release commit $COMMIT; got ${remote_tag_commit:-missing}" >&2
    return 1
  fi

  printf 'remote tag verified: %s -> %s\n' "$TAG" "$remote_tag_commit"
}

verify_hosted_release_contract() {
  local record="$1"
  shift

  if [[ "$#" -eq 0 ]]; then
    echo "hosted release contract requires expected asset names" >&2
    return 2
  fi

  gh release view "$TAG" --json tagName,targetCommitish,isDraft,isPrerelease,assets >"$record"
  /usr/bin/python3 - "$record" "$TAG" "$@" <<'PY'
import json
import pathlib
import sys

record_path = pathlib.Path(sys.argv[1])
tag = sys.argv[2]
expected_name_list = sys.argv[3:]
expected_names = set(expected_name_list)
if len(expected_names) != len(expected_name_list):
    raise SystemExit("hosted GitHub Release contract received duplicate expected asset names")

try:
    payload = json.loads(record_path.read_text())
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"could not parse hosted GitHub Release response: {error}")

failures = []
if payload.get("tagName") != tag:
    failures.append(f"tagName is {payload.get('tagName')!r}, expected {tag!r}")
if payload.get("isDraft") is not False:
    failures.append("release is a draft")
if payload.get("isPrerelease") is not False:
    failures.append("release is a prerelease")

assets = payload.get("assets")
if not isinstance(assets, list):
    failures.append("release assets are missing or malformed")
    assets = []

actual_names = []
for asset in assets:
    if not isinstance(asset, dict):
        failures.append("release contains a malformed asset record")
        continue
    name = asset.get("name")
    if not isinstance(name, str) or not name:
        failures.append("release contains an asset without a valid name")
        continue
    actual_names.append(name)
    if asset.get("state") != "uploaded":
        failures.append(f"asset {name!r} is not uploaded")
    size = asset.get("size")
    if not isinstance(size, int) or size <= 0:
        failures.append(f"asset {name!r} has invalid size {size!r}")

actual_name_set = set(actual_names)
if actual_name_set != expected_names:
    failures.append(
        "asset set mismatch; "
        f"missing={sorted(expected_names - actual_name_set)!r} "
        f"unexpected={sorted(actual_name_set - expected_names)!r}"
    )
if len(actual_names) != len(actual_name_set):
    failures.append("release contains duplicate asset names")

if failures:
    raise SystemExit("hosted GitHub Release contract failed:\n" + "\n".join(f"- {failure}" for failure in failures))

# GitHub may return a branch name for targetCommitish. The remote Git tag is
# checked before and after publication as the authoritative commit binding.
print(f"hosted GitHub Release contract verified for {tag}: {len(actual_names)} exact assets")
PY
}

# Locate Sparkle's appcast generator inside the resolved SPM artifacts.
find_generate_appcast() {
  local candidate
  candidate="$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  # Fall back to a search: the artifact path is an SPM implementation detail.
  candidate="$(find "$ROOT/.build/artifacts" -type f -name generate_appcast -perm +111 2>/dev/null | head -n 1)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  echo "Sparkle generate_appcast not found under $ROOT/.build/artifacts; run swift package resolve" >&2
  return 1
}

# Build and validate the signed update feed for this release.
#
# Runs against the finalized DMG only: the enclosure signature covers the exact
# published bytes, so this must happen after signing, notarization and stapling.
generate_update_feed() {
  local dmg="${1:?missing dmg}"
  local notes="${2:?missing release notes}"
  local app="${3:?missing candidate app}"
  local workspace="$RELEASE_DIR/appcast-workspace"
  local tool download_prefix
  local -a key_options=()

  if [[ "$MODE" == "local-only" ]]; then
    [[ -n "${NMH_SPARKLE_PRIVATE_KEY_FILE:-}" ]] || {
      echo "local-only update feed generation requires NMH_SPARKLE_PRIVATE_KEY_FILE" >&2
      return 1
    }
    [[ -f "$NMH_SPARKLE_PRIVATE_KEY_FILE" ]] || {
      echo "NMH_SPARKLE_PRIVATE_KEY_FILE does not exist: $NMH_SPARKLE_PRIVATE_KEY_FILE" >&2
      return 1
    }
    key_options=(--ed-key-file "$NMH_SPARKLE_PRIVATE_KEY_FILE")
  elif [[ "$MODE" == "public" ]]; then
    [[ -z "${NMH_SPARKLE_PRIVATE_KEY_FILE:-}" ]] || {
      echo "public update feed generation refuses NMH_SPARKLE_PRIVATE_KEY_FILE" >&2
      return 1
    }
    key_options=(--account "${NMH_SPARKLE_KEY_ACCOUNT:-ed25519}")
  else
    echo "unsupported release mode for update feed generation: $MODE" >&2
    return 1
  fi

  tool="$(find_generate_appcast)" || return 1
  download_prefix="$(nmh_release_download_url_prefix "$TAG")" || return 1

  # An isolated workspace: generate_appcast rewrites its input directory and
  # relocates anything it considers an old update.
  rm -rf "$workspace"
  mkdir -p "$workspace"
  cp "$dmg" "$workspace/$ARTIFACT_NAME"
  # Release notes are matched to an archive by basename.
  cp "$notes" "$workspace/${ARTIFACT_NAME%.dmg}.md"

  "$tool" \
    "${key_options[@]}" \
    --download-url-prefix "$download_prefix" \
    --link "$(nmh_release_repository_url)" \
    --embed-release-notes \
    -o "$workspace/appcast.xml" \
    "$workspace"

  cp "$workspace/appcast.xml" "$APPCAST"

  "$ROOT/script/validate-update-feed.py" \
    --appcast "$APPCAST" \
    --artifact "$dmg" \
    --app "$app" \
    --version "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --minimum-macos "$MIN_MACOS_VERSION" \
    --architectures "$RELEASE_ARCHITECTURES" \
    --expected-enclosure-url "$download_prefix$ARTIFACT_NAME"
}

verify_hosted_release_asset_bytes() {
  local hosted_dir="$1"
  shift
  local source hosted

  for source in "$@"; do
    hosted="$hosted_dir/$(basename "$source")"
    if [[ ! -f "$source" || ! -f "$hosted" ]]; then
      echo "hosted asset byte check missing file: source=$source hosted=$hosted" >&2
      return 1
    fi
    if ! cmp -s "$source" "$hosted"; then
      echo "hosted asset differs from candidate: $(basename "$source")" >&2
      return 1
    fi
  done
}

run_candidate_install_smoke() {
  local artifact="$1"
  local label="$2"
  local source_app="$3"
  local smoke_root mount_point mounted_app installed_app expected_binary expected_binary_sha

  case "$label" in
    candidate|hosted) ;;
    *)
      echo "unsupported install-smoke label: $label" >&2
      return 2
      ;;
  esac

  smoke_root="$RELEASE_DIR/install-smoke-$label"
  mount_point="$smoke_root/mount"
  mounted_app="$mount_point/NikoMusicHub.app"
  installed_app="$smoke_root/NikoMusicHub.app"
  expected_binary="$source_app/Contents/MacOS/NikoMusicHub"

  if [[ ! -f "$artifact" || ! -x "$expected_binary" ]]; then
    echo "install smoke input missing: artifact=$artifact source_binary=$expected_binary" >&2
    return 1
  fi
  if [[ -e "$smoke_root" ]]; then
    echo "install smoke directory already exists: $smoke_root" >&2
    return 1
  fi
  expected_binary_sha="$(shasum -a 256 "$expected_binary" | awk '{print $1}')"
  mkdir -p "$mount_point"

  log "install smoke ($label): mount candidate artifact"
  if ! run install-smoke-attach hdiutil attach -readonly -nobrowse -mountpoint "$mount_point" "$artifact"; then
    return 1
  fi
  if [[ ! -d "$mounted_app" ]]; then
    echo "install smoke mounted artifact has no NikoMusicHub.app: $artifact" >&2
    hdiutil detach "$mount_point" >/dev/null 2>&1 || hdiutil detach -force "$mount_point" >/dev/null 2>&1 || true
    return 1
  fi
  if ! /usr/bin/ditto "$mounted_app" "$installed_app"; then
    hdiutil detach "$mount_point" >/dev/null 2>&1 || hdiutil detach -force "$mount_point" >/dev/null 2>&1 || true
    return 1
  fi
  if ! run install-smoke-detach hdiutil detach "$mount_point"; then
    return 1
  fi

  NMH_EXPECTED_BUILD_ID="$BUILD_ID" \
  NMH_EXPECTED_BUILD_CONFIGURATION="$RELEASE_BUILD_CONFIGURATION" \
  NMH_EXPECTED_SOURCE_COMMIT="$COMMIT" \
  NMH_EXPECTED_BINARY_SHA256="$expected_binary_sha" \
    "$ROOT/script/verify-installed-release.sh" "$installed_app"
  run install-smoke-codesign codesign --verify --deep --strict --verbose=2 "$installed_app"
  log "install smoke ($label): exact candidate installation verified"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-only) MODE="local-only"; shift ;;
    --public) MODE="public"; shift ;;
    --publish) PUBLISH=true; shift ;;
    --dry-run-publish) DRY_RUN_PUBLISH=true; shift ;;
    --skip-tests) SKIP_TESTS=true; shift ;;
    --emergency-skip-tests) EMERGENCY_SKIP_TESTS=true; shift ;;
    --reason) EMERGENCY_REASON="${2:-}"; shift 2 ;;
    --install-smoke) INSTALL_SMOKE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "$MODE" ]] || { usage; exit 2; }
if [[ "$MODE" == "local-only" && ( "$PUBLISH" == true || "$DRY_RUN_PUBLISH" == true ) ]]; then
  echo "local-only release cannot publish or dry-run hosted publication" >&2
  exit 2
fi
if [[ "$MODE" == "public" && "$PUBLISH" == "$DRY_RUN_PUBLISH" ]]; then
  echo "public release requires exactly one of --publish or --dry-run-publish" >&2
  exit 2
fi
if [[ "$MODE" == "public" && "$SKIP_TESTS" == true ]]; then
  echo "public release rejects --skip-tests; use --emergency-skip-tests --reason \"...\" for an auditable override" >&2
  exit 2
fi
if [[ "$EMERGENCY_SKIP_TESTS" == true && -z "${EMERGENCY_REASON//[[:space:]]/}" ]]; then
  echo "--emergency-skip-tests requires a non-empty --reason" >&2
  exit 2
fi
if [[ -n "$EMERGENCY_REASON" && "$EMERGENCY_SKIP_TESTS" != true ]]; then
  echo "--reason is valid only with --emergency-skip-tests" >&2
  exit 2
fi
if [[ "$MODE" == "local-only" && "$EMERGENCY_SKIP_TESTS" == true ]]; then
  echo "local-only mode uses --skip-tests; emergency overrides are public-release records" >&2
  exit 2
fi

RELEASE_DIR="$(validate_release_output_directory)" || exit 2
if [[ -n "$LOG_FILE" ]]; then
  LOG_FILE="$(/usr/bin/python3 - "$RELEASE_DIR" "$LOG_FILE" <<'PY'
import os
import sys

release_dir = os.path.realpath(sys.argv[1])
candidate = os.path.realpath(sys.argv[2])
if os.path.commonpath([release_dir, candidate]) != release_dir:
    raise SystemExit(f"release log must stay beneath {release_dir}: {candidate}")
print(candidate)
PY
)" || exit 2
fi

VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"
TAG="v$VERSION"
COMMIT="$(nmh_git_commit)"
SHORT_COMMIT="$(nmh_git_short_commit)"
BUILD_NUMBER="$(nmh_git_build_number)"
BUILD_ID="$VERSION+$SHORT_COMMIT"
RELEASE_BUILD_CONFIGURATION="release"
RELEASE_ARCHITECTURES="$(nmh_release_architectures)"
MIN_MACOS_VERSION="$(nmh_release_min_macos_version)"
nmh_validate_release_host_architecture
ARTIFACT_LABEL="$VERSION"
if [[ "$MODE" == "local-only" ]]; then
  ARTIFACT_LABEL="$VERSION+$SHORT_COMMIT.LOCAL-ONLY-UNSIGNED"
fi
ARTIFACT_NAME="NikoMusicHub-$ARTIFACT_LABEL.dmg"
SIGNING_IDENTITY_RECORD="ad-hoc"

# Assigned before any mode-specific work so a malformed key fails the run under
# `set -e` instead of collapsing to an empty string inside a later test.
SPARKLE_PUBLIC_KEY="$(nmh_sparkle_public_ed_key)"

if [[ "$MODE" == "public" ]]; then
  : "${NMH_DEVELOPER_ID_APPLICATION:?public release requires NMH_DEVELOPER_ID_APPLICATION}"
  : "${NMH_NOTARY_PROFILE:?public release requires NMH_NOTARY_PROFILE}"
  : "${NMH_RELEASE_UAT_EVIDENCE:?public release requires NMH_RELEASE_UAT_EVIDENCE}"
  if [[ -z "$SPARKLE_PUBLIC_KEY" ]]; then
    echo "public release requires SPARKLE_PUBLIC_ED_KEY so the published feed matches the shipped app" >&2
    exit 1
  fi
  # The feed URL is compiled into the bundle for good; a test feed must never
  # reach a public build.
  if [[ -n "${NMH_UPDATE_FEED_URL:-}" ]]; then
    echo "public release refuses NMH_UPDATE_FEED_URL; every public build must poll the canonical feed" >&2
    exit 1
  fi
  # The private-key file override exists only for local test feeds (see
  # docs/update-feed.md); public releases sign through the Keychain account so
  # the key never travels on a command line or in the environment.
  if [[ -n "${NMH_SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    echo "public release refuses NMH_SPARKLE_PRIVATE_KEY_FILE; it is for test feeds only and public releases use the Keychain account" >&2
    exit 1
  fi
  if [[ "$PUBLISH" == true ]]; then
    "$ROOT/script/release-preflight.sh"
  else
    "$ROOT/script/release-preflight.sh" --allow-missing-tag
  fi
  "$ROOT/script/validate-release-uat.sh" --evidence "$NMH_RELEASE_UAT_EVIDENCE" --commit "$COMMIT"
  if [[ "$PUBLISH" == true ]]; then
    command -v gh >/dev/null || { echo "public publish requires gh CLI" >&2; exit 1; }
    gh auth status >/dev/null
    verify_remote_release_tag
  fi
  # Fail on environment problems now, not after eight minutes of gates.
  if [[ "$SKIP_TESTS" != true && "$EMERGENCY_SKIP_TESTS" != true ]] && nmh_console_locked; then
    echo "public release gates drive the app's UI; unlock the screen first (macOS hides window content from accessibility while the console is locked)" >&2
    exit 1
  fi
  if ! nmh_notary_upload_endpoint_reachable; then
    echo "notary upload endpoint $NMH_NOTARY_UPLOAD_HOST is unreachable over IPv4; notarytool would time out after the gates" >&2
    exit 1
  fi
  xcrun notarytool history --keychain-profile "$NMH_NOTARY_PROFILE" >/dev/null 2>&1 || {
    echo "notary credentials for keychain profile $NMH_NOTARY_PROFILE do not work" >&2
    exit 1
  }
  # Sparkle offers an update only when sparkle:version (CFBundleVersion, the
  # commit count of HEAD) grows. Compare against the feed installed apps
  # actually poll, not against git: a release cut from another clone or a
  # side branch would otherwise ship a build number nobody is ever offered.
  if ! LIVE_BUILD_NUMBER="$(nmh_live_feed_max_build_number)"; then
    echo "could not read the live update feed to prove the build number advances" >&2
    exit 1
  fi
  if (( BUILD_NUMBER <= LIVE_BUILD_NUMBER )); then
    echo "CFBundleVersion $BUILD_NUMBER does not exceed the published sparkle:version $LIVE_BUILD_NUMBER; installed apps would never be offered this release (build from the public history, see docs/release.md)" >&2
    exit 1
  fi
  printf 'build number %s advances the live feed (%s)\n' "$BUILD_NUMBER" "$LIVE_BUILD_NUMBER"
fi

# A release artifact records an exact source commit. Never package a dirty
# worktree and then misrepresent the resulting binary as that commit.
require_clean_release_worktree

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
LOG_FILE="${LOG_FILE:-$RELEASE_DIR/release.log}"
: >"$LOG_FILE"

log "release identity"
if [[ "$MODE" == "public" ]]; then
  SIGNING_IDENTITY_RECORD="$NMH_DEVELOPER_ID_APPLICATION"
fi
printf 'version=%s\nbundle_id=%s\ncommit=%s\ntag=%s\nbuild_id=%s\narchitectures=%s\nminimum_macos=%s\nsigning_identity=%s\nmode=%s\n' \
  "$VERSION" "$BUNDLE_ID" "$COMMIT" "$TAG" "$BUILD_ID" "$RELEASE_ARCHITECTURES" "$MIN_MACOS_VERSION" "$SIGNING_IDENTITY_RECORD" "$MODE" | tee -a "$LOG_FILE"

if [[ "$SKIP_TESTS" != true && "$EMERGENCY_SKIP_TESTS" != true ]]; then
  log "local gates"
  run ci "$ROOT/script/ci.sh"
  if [[ "$MODE" == "public" ]]; then
    run e2e env NMH_STRICT_UI_E2E=1 "$ROOT/script/e2e_user_smoke.sh"
    run release-config "$ROOT/script/ci-release.sh"
    run thread-sanitizer "$ROOT/script/ci-tsan.sh"
  else
    run e2e "$ROOT/script/e2e_user_smoke.sh"
  fi
elif [[ "$EMERGENCY_SKIP_TESTS" == true ]]; then
  log "emergency test override"
  printf 'EMERGENCY OVERRIDE: automated test gates skipped; reason=%s\n' "$EMERGENCY_REASON" | tee -a "$LOG_FILE"
fi

log "version and public-tree hygiene"
run version-verify "$ROOT/script/release-version-verify.sh"
if [[ "$MODE" == "public" ]]; then
  run hygiene "$ROOT/script/public-tree-hygiene.sh" --public-release
else
  run hygiene "$ROOT/script/public-tree-hygiene.sh"
fi

BUILD_DIST="$RELEASE_DIR/build"
APP="$BUILD_DIST/NikoMusicHub.app"
mkdir -p "$BUILD_DIST"

log "build app bundle"
if [[ "${NMH_RELEASE_TEST_MODE:-}" == "1" ]]; then
  mkdir -p "$APP/Contents/MacOS"
  printf '#!/usr/bin/env bash\necho NikoMusicHub %s\n' "$BUILD_ID" >"$APP/Contents/MacOS/NikoMusicHub"
  chmod +x "$APP/Contents/MacOS/NikoMusicHub"
  cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>NikoMusicHub</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Niko Music Hub</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>NMHBuildID</key><string>$BUILD_ID</string>
  <key>NMHBuildConfiguration</key><string>$RELEASE_BUILD_CONFIGURATION</string>
  <key>NMHSourceCommit</key><string>$COMMIT</string>
</dict></plist>
PLIST
else
  export NMH_DIST_DIR="$BUILD_DIST"
  export NMH_MARKETING_VERSION="$VERSION"
  export NMH_BUILD_VERSION="$BUILD_NUMBER"
  export NMH_BUILD_ID="$BUILD_ID"
  export NMH_BUILD_CONFIGURATION="$RELEASE_BUILD_CONFIGURATION"
  export NMH_SOURCE_COMMIT="$COMMIT"
  if [[ "$MODE" == "public" ]]; then
    export NMH_SIGNING_IDENTITY="$NMH_DEVELOPER_ID_APPLICATION"
  else
    export NMH_SIGNING_IDENTITY="-"
  fi
  # shellcheck source=lib/app_lifecycle.sh
  source "$ROOT/script/lib/app_lifecycle.sh"
  nmh_build_bundle
fi

run version-verify-bundle "$ROOT/script/release-version-verify.sh" --bundle "$APP"

if [[ "$MODE" == "public" ]]; then
  log "public app signature validation"
  run codesign-verify codesign --verify --deep --strict --verbose=2 "$APP"
  SIGN_OUTPUT="$(codesign -dv "$APP" 2>&1 || true)"
  if [[ ! "$SIGN_OUTPUT" =~ Runtime\ Version && ! "$SIGN_OUTPUT" =~ flags=.*runtime ]]; then
    echo "public release app is missing hardened runtime" >&2
    exit 1
  fi

  run secure-timestamps require_secure_timestamps "$APP"
  run app-entitlements require_expected_entitlements "$APP"

  APP_ZIP="$RELEASE_DIR/NikoMusicHub-$VERSION-app-notary.zip"
  run ditto ditto -c -k --keepParent "$APP" "$APP_ZIP"
  log "notarize and staple app"
  notarize app "$APP_ZIP"
  run staple-app xcrun stapler staple "$APP"
  run validate-staple-app xcrun stapler validate "$APP"
  run spctl-app spctl --assess --type execute --verbose "$APP"
else
  log "local-only app signature"
  echo "LOCAL-ONLY: app is ad-hoc signed and intentionally not notarized" | tee -a "$LOG_FILE"
fi

log "package dmg"
DMG="$RELEASE_DIR/$ARTIFACT_NAME"
run hdiutil-create hdiutil create -volname "Niko Music Hub $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG"

if [[ "$MODE" == "public" ]]; then
  # Without an explicit identifier codesign derives one from the file name and
  # truncates it at the first dot ("NikoMusicHub-1").
  run sign-dmg codesign --force --timestamp --identifier "$BUNDLE_ID.dmg" --sign "$NMH_DEVELOPER_ID_APPLICATION" "$DMG"
  log "notarize and staple dmg"
  notarize dmg "$DMG"
  run staple-dmg xcrun stapler staple "$DMG"
fi

log "checksums and manifest"
(cd "$RELEASE_DIR" && shasum -a 256 "$ARTIFACT_NAME" >"$ARTIFACT_NAME.sha256")
if rg -n '/' "$DMG.sha256" >/dev/null; then
  echo "checksum generation failure: checksum file contains path separators" >&2
  exit 1
fi
ARTIFACT_SHA="$(awk '{print $1}' "$DMG.sha256")"
ARTIFACT_SIZE="$(stat -f%z "$DMG")"
MANIFEST="$RELEASE_DIR/NikoMusicHub-$ARTIFACT_LABEL-manifest.json"
MANIFEST_ARGS=(
  manifest
  --output "$MANIFEST"
  --version "$VERSION"
  --bundle-id "$BUNDLE_ID"
  --tag "$TAG"
  --commit "$COMMIT"
  --build-id "$BUILD_ID"
  --build-number "$BUILD_NUMBER"
  --architectures "$RELEASE_ARCHITECTURES"
  --minimum-macos "$MIN_MACOS_VERSION"
  --artifact "$ARTIFACT_NAME"
  --artifact-size "$ARTIFACT_SIZE"
  --artifact-sha256 "$ARTIFACT_SHA"
  --created-utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  --signing-identity "$SIGNING_IDENTITY_RECORD"
)
if [[ "$MODE" == "public" ]]; then
  MANIFEST_ARGS+=(--public-release)
fi
"$ROOT/script/generate-release-record.py" "${MANIFEST_ARGS[@]}" --validation-status pending
run validate-artifact-candidate "$ROOT/script/validate-release-artifact.sh" --artifact "$DMG" --manifest "$MANIFEST" --mode "$MODE" --allow-pending
"$ROOT/script/generate-release-record.py" "${MANIFEST_ARGS[@]}" --validation-status passed
run validate-artifact-final "$ROOT/script/validate-release-artifact.sh" --artifact "$DMG" --manifest "$MANIFEST" --mode "$MODE"
if [[ "$INSTALL_SMOKE" == true ]]; then
  run_candidate_install_smoke "$DMG" "candidate" "$APP"
fi

RELEASE_NOTES="$RELEASE_DIR/NikoMusicHub-$ARTIFACT_LABEL-release-notes.md"
run release-notes "$ROOT/script/extract-release-notes.sh" "$RELEASE_NOTES"

# The asset name is fixed: SUFeedURL points at
# releases/latest/download/appcast.xml, so it must be published under exactly
# that basename or every installed app stops seeing updates.
APPCAST="$RELEASE_DIR/appcast.xml"
APPCAST_STATUS="appcast.xml"
log "update feed"
if [[ -z "$SPARKLE_PUBLIC_KEY" ]]; then
  # Public mode already refused above; only local-only reaches this.
  APPCAST=""
  APPCAST_STATUS="not generated (no SPARKLE_PUBLIC_ED_KEY)"
  echo "LOCAL-ONLY: update feed skipped because no SPARKLE_PUBLIC_ED_KEY is configured" | tee -a "$LOG_FILE"
elif [[ "$MODE" == "local-only" && -z "${NMH_SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  APPCAST=""
  APPCAST_STATUS="not generated (local-only test key file not configured)"
  echo "LOCAL-ONLY: update feed skipped; set NMH_SPARKLE_PRIVATE_KEY_FILE to a throwaway private key and configure its matching SPARKLE_PUBLIC_ED_KEY to generate a test feed" | tee -a "$LOG_FILE"
else
  run update-feed generate_update_feed "$DMG" "$RELEASE_NOTES" "$APP"
fi

APPROVAL=""
if [[ "$MODE" == "public" ]]; then
  MANIFEST_SHA="$(shasum -a 256 "$MANIFEST" | awk '{print $1}')"
  UAT_SHA="$(shasum -a 256 "$NMH_RELEASE_UAT_EVIDENCE" | awk '{print $1}')"
  UAT_APPROVER="$(nmh_json_value "$NMH_RELEASE_UAT_EVIDENCE" approved_by)"
  UAT_APPROVED_AT="$(nmh_json_value "$NMH_RELEASE_UAT_EVIDENCE" approved_at_utc)"
  APPROVAL="$RELEASE_DIR/NikoMusicHub-$VERSION-release-approval.json"
  GATE_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  TEST_RESULT="passed"
  if [[ "$EMERGENCY_SKIP_TESTS" == true ]]; then TEST_RESULT="emergency-override"; fi
  APPROVAL_ARGS=(
    approval
    --output "$APPROVAL"
    --version "$VERSION"
    --bundle-id "$BUNDLE_ID"
    --tag "$TAG"
    --commit "$COMMIT"
    --artifact "$ARTIFACT_NAME"
    --artifact-sha256 "$ARTIFACT_SHA"
    --manifest "$(basename "$MANIFEST")"
    --manifest-sha256 "$MANIFEST_SHA"
    --machine "$(uname -m) macOS $(sw_vers -productVersion)"
    --created-utc "$GATE_TIME"
    --uat-file "$(basename "$NMH_RELEASE_UAT_EVIDENCE")"
    --uat-sha256 "$UAT_SHA"
    --uat-approved-by "$UAT_APPROVER"
    --uat-approved-at-utc "$UAT_APPROVED_AT"
    --gate "clean-tagged-checkout|./script/release-preflight.sh|passed|$GATE_TIME"
    --gate "consolidated-mac-uat|./script/validate-release-uat.sh|passed|$GATE_TIME"
    --gate "debug-ci|./script/ci.sh|$TEST_RESULT|$GATE_TIME"
    --gate "user-e2e|NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh|$TEST_RESULT|$GATE_TIME"
    --gate "release-configuration|./script/ci-release.sh|$TEST_RESULT|$GATE_TIME"
    --gate "thread-sanitizer|./script/ci-tsan.sh|$TEST_RESULT|$GATE_TIME"
    --gate "release-identity|./script/release-version-verify.sh|passed|$GATE_TIME"
    --gate "release-platform-contract|RELEASE_ARCHITECTURES,Package.swift minimum macOS|passed|$GATE_TIME"
    --gate "public-tree-hygiene|./script/public-tree-hygiene.sh --public-release|passed|$GATE_TIME"
    --gate "sign-notarize-staple|codesign, notarytool, stapler, spctl|passed|$GATE_TIME"
    --gate "artifact-validation|./script/validate-release-artifact.sh|passed|$GATE_TIME"
    --gate "update-feed|./script/validate-update-feed.py|passed|$GATE_TIME"
  )
  if [[ "$EMERGENCY_SKIP_TESTS" == true ]]; then
    APPROVAL_ARGS+=(--emergency-reason "$EMERGENCY_REASON")
  fi
  "$ROOT/script/generate-release-record.py" "${APPROVAL_ARGS[@]}"
  run validate-approval "$ROOT/script/validate-release-approval.sh" --approval "$APPROVAL" --artifact "$DMG" --manifest "$MANIFEST" --uat "$NMH_RELEASE_UAT_EVIDENCE"
fi

log "installed truth"
if [[ "$INSTALL_SMOKE" != true ]]; then
  echo "candidate installation smoke skipped; consolidated exact-commit UAT remains mandatory for public mode" | tee -a "$LOG_FILE"
fi

log "publication"
if [[ "$PUBLISH" == true ]]; then
  run remote-tag-before-create verify_remote_release_tag
  run gh-release-create gh release create "$TAG" "$DMG" "$DMG.sha256" "$MANIFEST" "$APPROVAL" "$RELEASE_NOTES" "$APPCAST" --verify-tag --title "Niko Music Hub $VERSION" --notes-file "$RELEASE_NOTES"
  run remote-tag-after-create verify_remote_release_tag
  HOSTED_RELEASE_RECORD="$RELEASE_DIR/NikoMusicHub-$ARTIFACT_LABEL-hosted-release.json"
  run hosted-release-contract verify_hosted_release_contract "$HOSTED_RELEASE_RECORD" "$(basename "$DMG")" "$(basename "$DMG.sha256")" "$(basename "$MANIFEST")" "$(basename "$APPROVAL")" "$(basename "$RELEASE_NOTES")" "$(basename "$APPCAST")"
  HOSTED_DIR="$RELEASE_DIR/hosted-download"
  mkdir -p "$HOSTED_DIR"
  gh release download "$TAG" --dir "$HOSTED_DIR" --pattern "$(basename "$DMG")" --pattern "$(basename "$DMG.sha256")" --pattern "$(basename "$MANIFEST")" --pattern "$(basename "$APPROVAL")" --pattern "$(basename "$RELEASE_NOTES")" --pattern "$(basename "$APPCAST")"
  run hosted-asset-byte-equality verify_hosted_release_asset_bytes "$HOSTED_DIR" "$DMG" "$DMG.sha256" "$MANIFEST" "$APPROVAL" "$RELEASE_NOTES" "$APPCAST"
  # The hosted feed is what users actually poll, so re-verify it where it landed.
  run validate-hosted-update-feed "$ROOT/script/validate-update-feed.py" \
    --appcast "$HOSTED_DIR/$(basename "$APPCAST")" \
    --artifact "$HOSTED_DIR/$(basename "$DMG")" \
    --app "$APP" \
    --version "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --minimum-macos "$MIN_MACOS_VERSION" \
    --architectures "$RELEASE_ARCHITECTURES" \
    --expected-enclosure-url "$(nmh_release_download_url_prefix "$TAG")$ARTIFACT_NAME"
  run validate-hosted "$ROOT/script/validate-release-artifact.sh" --artifact "$HOSTED_DIR/$(basename "$DMG")" --manifest "$HOSTED_DIR/$(basename "$MANIFEST")" --mode "$MODE"
  run validate-hosted-approval "$ROOT/script/validate-release-approval.sh" --approval "$HOSTED_DIR/$(basename "$APPROVAL")" --artifact "$HOSTED_DIR/$(basename "$DMG")" --manifest "$HOSTED_DIR/$(basename "$MANIFEST")" --uat "$NMH_RELEASE_UAT_EVIDENCE"
  if [[ "$INSTALL_SMOKE" == true ]]; then
    run_candidate_install_smoke "$HOSTED_DIR/$(basename "$DMG")" "hosted" "$APP"
  fi
elif [[ "$DRY_RUN_PUBLISH" == true ]]; then
  echo "DRY-RUN: publication skipped after full local public artifact validation" | tee -a "$LOG_FILE"
else
  echo "LOCAL-ONLY: hosted artifact verification skipped because this mode cannot publish" | tee -a "$LOG_FILE"
fi

REPORT="$RELEASE_DIR/NikoMusicHub-$ARTIFACT_LABEL-release-report.md"
cat >"$REPORT" <<REPORT
# Niko Music Hub $VERSION Release Report

- Mode: $MODE
- Tag: $TAG
- Commit: $COMMIT
- Build ID: $BUILD_ID
- Bundle ID: $BUNDLE_ID
- Architectures: $RELEASE_ARCHITECTURES
- Minimum macOS: $MIN_MACOS_VERSION
- Artifact: $ARTIFACT_NAME
- Artifact size: $ARTIFACT_SIZE bytes
- SHA-256: $ARTIFACT_SHA
- Manifest: $(basename "$MANIFEST")
- Update feed: $APPCAST_STATUS
- Approval: $([[ -n "$APPROVAL" ]] && basename "$APPROVAL" || echo "not generated for local-only mode")
- Publish: $([[ "$PUBLISH" == true ]] && echo "GitHub release uploaded and downloaded for validation" || ([[ "$DRY_RUN_PUBLISH" == true ]] && echo "dry-run publication" || echo "skipped local-only"))
- Install smoke: $([[ "$INSTALL_SMOKE" == true ]] && echo "ran" || echo "skipped")

## Caveats

$([[ "$MODE" == "local-only" ]] && echo "- Local-only artifacts are ad-hoc signed, unnotarized, and not public release candidates." || echo "- Public artifact signing/notarization validation ran before checksum generation.")
$([[ "$INSTALL_SMOKE" != true ]] && echo "- Exact candidate installation smoke was not run; public mode still required consolidated exact-commit UAT evidence." || echo "- Mounted candidate DMG was copied to an isolated install location and matched the exact build ID, release configuration, source commit, and executable SHA-256.")
REPORT

echo "release finished: $REPORT"
