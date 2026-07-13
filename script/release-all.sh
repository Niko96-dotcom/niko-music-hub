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

Local-only mode is explicitly unsigned/unnotarized and cannot publish.
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

VERSION="$(nmh_release_version)"
BUNDLE_ID="$(nmh_bundle_id)"
TAG="v$VERSION"
COMMIT="$(nmh_git_commit)"
SHORT_COMMIT="$(nmh_git_short_commit)"
BUILD_NUMBER="$(nmh_git_build_number)"
BUILD_ID="$VERSION+$SHORT_COMMIT"
ARTIFACT_LABEL="$VERSION"
if [[ "$MODE" == "local-only" ]]; then
  ARTIFACT_LABEL="$VERSION+$SHORT_COMMIT.LOCAL-ONLY-UNSIGNED"
fi
ARTIFACT_NAME="NikoMusicHub-$ARTIFACT_LABEL.dmg"

if [[ "$MODE" == "public" ]]; then
  : "${NMH_DEVELOPER_ID_APPLICATION:?public release requires NMH_DEVELOPER_ID_APPLICATION}"
  : "${NMH_NOTARY_PROFILE:?public release requires NMH_NOTARY_PROFILE}"
  : "${NMH_RELEASE_UAT_EVIDENCE:?public release requires NMH_RELEASE_UAT_EVIDENCE}"
  "$ROOT/script/release-preflight.sh"
  "$ROOT/script/validate-release-uat.sh" --evidence "$NMH_RELEASE_UAT_EVIDENCE" --commit "$COMMIT"
  if [[ "$PUBLISH" == true ]]; then
    command -v gh >/dev/null || { echo "public publish requires gh CLI" >&2; exit 1; }
    gh auth status >/dev/null
  fi
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
LOG_FILE="${LOG_FILE:-$RELEASE_DIR/release.log}"
: >"$LOG_FILE"

log "release identity"
printf 'version=%s\nbundle_id=%s\ncommit=%s\ntag=%s\nbuild_id=%s\nmode=%s\n' "$VERSION" "$BUNDLE_ID" "$COMMIT" "$TAG" "$BUILD_ID" "$MODE" | tee -a "$LOG_FILE"

if [[ "$SKIP_TESTS" != true && "$EMERGENCY_SKIP_TESTS" != true ]]; then
  log "local gates"
  run ci "$ROOT/script/ci.sh"
  run e2e "$ROOT/script/e2e_user_smoke.sh"
  if [[ "$MODE" == "public" ]]; then
    run release-config "$ROOT/script/ci-release.sh"
    run thread-sanitizer "$ROOT/script/ci-tsan.sh"
  fi
elif [[ "$EMERGENCY_SKIP_TESTS" == true ]]; then
  log "emergency test override"
  printf 'EMERGENCY OVERRIDE: automated test gates skipped; reason=%s\n' "$EMERGENCY_REASON" | tee -a "$LOG_FILE"
fi

log "version and public-tree hygiene"
run version-verify "$ROOT/script/release-version-verify.sh"
run hygiene "$ROOT/script/public-tree-hygiene.sh"

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
  <key>NMHSourceCommit</key><string>$COMMIT</string>
</dict></plist>
PLIST
else
  export NMH_DIST_DIR="$BUILD_DIST"
  export NMH_MARKETING_VERSION="$VERSION"
  export NMH_BUILD_VERSION="$BUILD_NUMBER"
  export NMH_BUILD_ID="$BUILD_ID"
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

  APP_ZIP="$RELEASE_DIR/NikoMusicHub-$VERSION-app-notary.zip"
  run ditto ditto -c -k --keepParent "$APP" "$APP_ZIP"
  log "notarize and staple app"
  run notary-app xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NMH_NOTARY_PROFILE" --wait
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
  run sign-dmg codesign --force --timestamp --sign "$NMH_DEVELOPER_ID_APPLICATION" "$DMG"
  log "notarize and staple dmg"
  run notary-dmg xcrun notarytool submit "$DMG" --keychain-profile "$NMH_NOTARY_PROFILE" --wait
  run staple-dmg xcrun stapler staple "$DMG"
fi

log "checksums and manifest"
(cd "$RELEASE_DIR" && shasum -a 256 "$ARTIFACT_NAME" >"$ARTIFACT_NAME.sha256")
if rg -n '/' "$DMG.sha256" >/dev/null; then
  echo "checksum generation failure: checksum file contains path separators" >&2
  exit 1
fi
ARTIFACT_SHA="$(awk '{print $1}' "$DMG.sha256")"
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
  --artifact "$ARTIFACT_NAME"
  --artifact-sha256 "$ARTIFACT_SHA"
  --created-utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
)
if [[ "$MODE" == "public" ]]; then
  MANIFEST_ARGS+=(--public-release)
fi
"$ROOT/script/generate-release-record.py" "${MANIFEST_ARGS[@]}" --validation-status pending
run validate-artifact-candidate "$ROOT/script/validate-release-artifact.sh" --artifact "$DMG" --manifest "$MANIFEST" --mode "$MODE" --allow-pending
"$ROOT/script/generate-release-record.py" "${MANIFEST_ARGS[@]}" --validation-status passed
run validate-artifact-final "$ROOT/script/validate-release-artifact.sh" --artifact "$DMG" --manifest "$MANIFEST" --mode "$MODE"

RELEASE_NOTES="$RELEASE_DIR/NikoMusicHub-$ARTIFACT_LABEL-release-notes.md"
run release-notes "$ROOT/script/extract-release-notes.sh" "$RELEASE_NOTES"

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
    --gate "user-e2e|./script/e2e_user_smoke.sh|$TEST_RESULT|$GATE_TIME"
    --gate "release-configuration|./script/ci-release.sh|$TEST_RESULT|$GATE_TIME"
    --gate "thread-sanitizer|./script/ci-tsan.sh|$TEST_RESULT|$GATE_TIME"
    --gate "release-identity|./script/release-version-verify.sh|passed|$GATE_TIME"
    --gate "public-tree-hygiene|./script/public-tree-hygiene.sh|passed|$GATE_TIME"
    --gate "sign-notarize-staple|codesign, notarytool, stapler, spctl|passed|$GATE_TIME"
    --gate "artifact-validation|./script/validate-release-artifact.sh|passed|$GATE_TIME"
  )
  if [[ "$EMERGENCY_SKIP_TESTS" == true ]]; then
    APPROVAL_ARGS+=(--emergency-reason "$EMERGENCY_REASON")
  fi
  "$ROOT/script/generate-release-record.py" "${APPROVAL_ARGS[@]}"
  run validate-approval "$ROOT/script/validate-release-approval.sh" --approval "$APPROVAL" --artifact "$DMG" --manifest "$MANIFEST" --uat "$NMH_RELEASE_UAT_EVIDENCE"
fi

log "installed truth"
if [[ "$INSTALL_SMOKE" == true ]]; then
  "$ROOT/script/verify-installed-release.sh"
else
  echo "installed bundle smoke skipped; consolidated exact-commit UAT remains mandatory for public mode" | tee -a "$LOG_FILE"
fi

log "publication"
if [[ "$PUBLISH" == true ]]; then
  gh release view "$TAG" >/dev/null 2>&1 || gh release create "$TAG" --title "Niko Music Hub $VERSION" --notes-file "$RELEASE_NOTES"
  gh release upload "$TAG" "$DMG" "$DMG.sha256" "$MANIFEST" "$APPROVAL" "$RELEASE_NOTES" --clobber
  HOSTED_DIR="$RELEASE_DIR/hosted-download"
  mkdir -p "$HOSTED_DIR"
  gh release download "$TAG" --dir "$HOSTED_DIR" --pattern "$(basename "$DMG")" --pattern "$(basename "$DMG.sha256")" --pattern "$(basename "$MANIFEST")" --pattern "$(basename "$APPROVAL")" --pattern "$(basename "$RELEASE_NOTES")"
  run validate-hosted "$ROOT/script/validate-release-artifact.sh" --artifact "$HOSTED_DIR/$(basename "$DMG")" --manifest "$HOSTED_DIR/$(basename "$MANIFEST")" --mode "$MODE"
  run validate-hosted-approval "$ROOT/script/validate-release-approval.sh" --approval "$HOSTED_DIR/$(basename "$APPROVAL")" --artifact "$HOSTED_DIR/$(basename "$DMG")" --manifest "$HOSTED_DIR/$(basename "$MANIFEST")" --uat "$NMH_RELEASE_UAT_EVIDENCE"
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
- Artifact: $ARTIFACT_NAME
- SHA-256: $ARTIFACT_SHA
- Manifest: $(basename "$MANIFEST")
- Approval: $([[ -n "$APPROVAL" ]] && basename "$APPROVAL" || echo "not generated for local-only mode")
- Publish: $([[ "$PUBLISH" == true ]] && echo "GitHub release uploaded and downloaded for validation" || ([[ "$DRY_RUN_PUBLISH" == true ]] && echo "dry-run publication" || echo "skipped local-only"))
- Install smoke: $([[ "$INSTALL_SMOKE" == true ]] && echo "ran" || echo "skipped")

## Caveats

$([[ "$MODE" == "local-only" ]] && echo "- Local-only artifacts are ad-hoc signed, unnotarized, and not public release candidates." || echo "- Public artifact signing/notarization validation ran before checksum generation.")
$([[ "$INSTALL_SMOKE" != true ]] && echo "- Installed /Applications metadata was not checked in this run; public mode still required consolidated exact-commit UAT evidence." || echo "- Installed bundle metadata matched VERSION and BUNDLE_ID.")
REPORT

echo "release finished: $REPORT"
