#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="/Applications/NikoMusicHub.app"

if [[ "${1:-}" == "--app-path" ]]; then
  [[ -n "${2:-}" ]] || { echo "usage: $0 [--app-path PATH]" >&2; exit 2; }
  APP_PATH="$2"
  shift 2
fi
[[ $# -eq 0 ]] || { echo "usage: $0 [--app-path PATH]" >&2; exit 2; }
[[ "$APP_PATH" = /* ]] || { echo "--app-path must be absolute: $APP_PATH" >&2; exit 2; }
[[ "$APP_PATH" == *.app ]] || { echo "--app-path must be a .app bundle: $APP_PATH" >&2; exit 2; }
[[ ! -L "$APP_PATH" ]] || { echo "--app-path must not be a symlink: $APP_PATH" >&2; exit 2; }

EXPECTED_BUILD_ID="$("$ROOT/script/local-build-identity.sh")"
export NMH_BUILD_ID="$EXPECTED_BUILD_ID"
export NMH_SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"

# shellcheck source=lib/app_lifecycle.sh
source "$ROOT/script/lib/app_lifecycle.sh"

TARGET_APP_BINARY="$APP_PATH/Contents/MacOS/$NMH_APP_NAME"
# Reject existing destinations that are not our fixed bundle identity.
# Alternate .app names stay allowed for isolated candidate installs; only the
# bundle identifier must match. The check reads the fixed BUNDLE_ID file (via
# nmh_bundle_id) and never inspects credentials. Never deletes; returns
# non-zero on mismatch. Manual authorized install only; never removes another
# bundle. Called before the long build AND again immediately before the first
# mv, so a destination swapped between phases is never replaced.
nmh_check_existing_destination() {
  if [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
    [[ -d "$APP_PATH" && ! -L "$APP_PATH" ]] || { echo "--app-path existing destination must be a .app directory (not symlink/file): $APP_PATH" >&2; return 1; }
    local _nmh_existing_info="$APP_PATH/Contents/Info.plist"
    local _nmh_existing_id
    _nmh_existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$_nmh_existing_info" 2>/dev/null || true)"
    if [[ "$_nmh_existing_id" != "$NMH_CANONICAL_BUNDLE_ID" ]]; then
      echo "refusing to replace existing directory at $APP_PATH (bundle identifier '${_nmh_existing_id:-missing}' does not match canonical '$NMH_CANONICAL_BUNDLE_ID')" >&2
      return 1
    fi
  fi
}
nmh_check_existing_destination || exit 1
nmh_build_bundle

SOURCE_BINARY_SHA256="$(shasum -a 256 "$NMH_APP_BINARY" | awk '{print $1}')"
mkdir -p "$(dirname "$APP_PATH")"
INSTALL_TMP="$(mktemp -d "$(dirname "$APP_PATH")/.nmh-install.XXXXXX")"
STAGING_PATH="$INSTALL_TMP/staging.app"
BACKUP_PATH="$INSTALL_TMP/backup.app"
INSTALL_SUCCESS=false
MOVED_ORIGINAL=false
INSTALLED_CANDIDATE=false

cleanup() {
  local _cleanup_status=$?
  set +e
  if [[ "$INSTALL_SUCCESS" == true ]]; then
    rm -rf "$INSTALL_TMP"
    return "$_cleanup_status"
  fi
  rm -rf "$STAGING_PATH"
  if [[ "$MOVED_ORIGINAL" == true ]]; then
    # Remove only the candidate this install placed at APP_PATH; never a
    # preexisting or unrelated path.
    if [[ "$INSTALLED_CANDIDATE" == true && -d "$APP_PATH" && ! -L "$APP_PATH" ]]; then
      rm -rf "$APP_PATH"
    fi
    # BSD mv nests backup.app inside a leftover candidate directory and
    # returns success. Require APP_PATH absent (including dangling symlinks)
    # after candidate removal; never mv over a leftover, never auto-delete
    # orphans. Preserve backup + temp dir and return the original failure.
    if [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
      echo "install-local: rollback blocked; candidate cleanup failed, destination still present at $APP_PATH; original bundle preserved at $BACKUP_PATH (temp dir retained: $INSTALL_TMP)" >&2
      if [[ "$_cleanup_status" -eq 0 ]]; then
        return 1
      fi
      return "$_cleanup_status"
    fi
    if [[ -d "$BACKUP_PATH" && ! -L "$BACKUP_PATH" && "$BACKUP_PATH" == "$INSTALL_TMP/"* ]]; then
      if mv "$BACKUP_PATH" "$APP_PATH"; then
        rm -rf "$INSTALL_TMP"
      else
        echo "install-local: rollback restore failed; original bundle preserved at $BACKUP_PATH (temp dir retained: $INSTALL_TMP)" >&2
        if [[ "$_cleanup_status" -eq 0 ]]; then
          return 1
        fi
        return "$_cleanup_status"
      fi
    else
      echo "install-local: rollback backup missing at $BACKUP_PATH (temp dir retained: $INSTALL_TMP)" >&2
      if [[ "$_cleanup_status" -eq 0 ]]; then
        return 1
      fi
      return "$_cleanup_status"
    fi
    return "$_cleanup_status"
  fi
  # First install (no original moved): remove only the candidate we installed.
  if [[ "$INSTALLED_CANDIDATE" == true && -d "$APP_PATH" && ! -L "$APP_PATH" ]]; then
    rm -rf "$APP_PATH"
  fi
  # Do not claim cleanup success when the candidate is still left (rm failed);
  # preserve the candidate path + temp dir and return the original failure.
  if [[ "$INSTALLED_CANDIDATE" == true ]] && [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
    echo "install-local: candidate cleanup failed; candidate preserved at $APP_PATH (temp dir retained: $INSTALL_TMP)" >&2
    if [[ "$_cleanup_status" -eq 0 ]]; then
      return 1
    fi
    return "$_cleanup_status"
  fi
  rm -rf "$INSTALL_TMP"
  return "$_cleanup_status"
}
trap cleanup EXIT

/usr/bin/ditto "$NMH_APP_BUNDLE" "$STAGING_PATH"

NMH_EXPECTED_BUILD_ID="$EXPECTED_BUILD_ID" \
NMH_EXPECTED_SOURCE_COMMIT="$NMH_SOURCE_COMMIT" \
NMH_EXPECTED_BINARY_SHA256="$SOURCE_BINARY_SHA256" \
  "$ROOT/script/verify-installed-release.sh" "$STAGING_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGING_PATH"

nmh_stop_app_binary "$TARGET_APP_BINARY" true
# Re-check destination identity immediately before the first mv: the prebuild
# preflight above can go stale during the long build. Anything created at
# APP_PATH during the build is what would be replaced, so refuse a swapped
# symlink or foreign bundle here instead of deleting it.
nmh_check_existing_destination || exit 1
if [[ -d "$APP_PATH" ]]; then
  mv "$APP_PATH" "$BACKUP_PATH"
  MOVED_ORIGINAL=true
fi
mv "$STAGING_PATH" "$APP_PATH"
INSTALLED_CANDIDATE=true

NMH_EXPECTED_BUILD_ID="$EXPECTED_BUILD_ID" \
NMH_EXPECTED_SOURCE_COMMIT="$NMH_SOURCE_COMMIT" \
NMH_EXPECTED_BINARY_SHA256="$SOURCE_BINARY_SHA256" \
  "$ROOT/script/verify-installed-release.sh" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

INSTALL_SUCCESS=true
echo "local install ok: $APP_PATH build_id=$EXPECTED_BUILD_ID binary_sha256=$SOURCE_BINARY_SHA256"
