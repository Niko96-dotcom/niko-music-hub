# Shared Niko Music Hub app lifecycle helpers for shell scripts.
# shellcheck shell=bash

NMH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NMH_SCRIPT_DIR="$(cd "$NMH_LIB_DIR/.." && pwd)"
NMH_ROOT_DIR="$(cd "$NMH_SCRIPT_DIR/.." && pwd)"
# shellcheck source=../release-env.sh
source "$NMH_SCRIPT_DIR/release-env.sh"

NMH_APP_NAME="${NMH_APP_NAME:-NikoMusicHub}"
NMH_CANONICAL_BUNDLE_ID="$(nmh_bundle_id)"
NMH_BUNDLE_ID="${NMH_BUNDLE_ID:-$NMH_CANONICAL_BUNDLE_ID}"
if [[ "$NMH_BUNDLE_ID" != "$NMH_CANONICAL_BUNDLE_ID" ]]; then
  echo "bundle identifier override '$NMH_BUNDLE_ID' does not match canonical '$NMH_CANONICAL_BUNDLE_ID'" >&2
  exit 1
fi
NMH_VERSION_FILE="${NMH_VERSION_FILE:-$NMH_ROOT_DIR/VERSION}"
if [[ -z "${NMH_MARKETING_VERSION:-}" ]]; then
  if [[ ! -f "$NMH_VERSION_FILE" ]]; then
    echo "missing VERSION file: $NMH_VERSION_FILE" >&2
    exit 1
  fi
  NMH_MARKETING_VERSION="$(tr -d '[:space:]' <"$NMH_VERSION_FILE")"
fi
if [[ -z "${NMH_BUILD_VERSION:-}" ]]; then
  NMH_BUILD_VERSION="$(git -C "$NMH_ROOT_DIR" rev-list --count HEAD 2>/dev/null || printf '0')"
fi
if [[ -z "${NMH_SOURCE_COMMIT:-}" ]]; then
  NMH_SOURCE_COMMIT="$(git -C "$NMH_ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
fi
if [[ -z "${NMH_BUILD_ID:-}" ]]; then
  NMH_BUILD_ID="$NMH_MARKETING_VERSION+$(git -C "$NMH_ROOT_DIR" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown')"
fi
NMH_MIN_SYSTEM_VERSION="${NMH_MIN_SYSTEM_VERSION:-$(nmh_release_min_macos_version)}"
NMH_LAUNCH_WAIT_SEC="${NMH_LAUNCH_WAIT_SEC:-8}"
NMH_WINDOW_TITLE="${NMH_WINDOW_TITLE:-Niko Music Hub}"
NMH_WINDOW_MIN_WIDTH="${NMH_WINDOW_MIN_WIDTH:-400}"
NMH_WINDOW_MIN_HEIGHT="${NMH_WINDOW_MIN_HEIGHT:-300}"
NMH_BUILD_CONFIGURATION="${NMH_BUILD_CONFIGURATION:-debug}"
case "$NMH_BUILD_CONFIGURATION" in
  debug|release) ;;
  *)
    echo "unsupported NMH_BUILD_CONFIGURATION '$NMH_BUILD_CONFIGURATION' (expected debug or release)" >&2
    exit 2
    ;;
esac

NMH_DIST_DIR="${NMH_DIST_DIR:-$NMH_ROOT_DIR/dist}"
NMH_DIST_DIR="$(/usr/bin/python3 - "$NMH_ROOT_DIR/dist" "$NMH_DIST_DIR" <<'PY'
import os
import sys

allowed = os.path.realpath(sys.argv[1])
candidate = os.path.realpath(sys.argv[2])
if os.path.commonpath([allowed, candidate]) != allowed:
    raise SystemExit(f"output directory must stay beneath {allowed}: {candidate}")
print(candidate)
PY
)" || exit 1

_nmh_expected_app_bundle="$NMH_DIST_DIR/$NMH_APP_NAME.app"
for _nmh_output_override in NMH_APP_BUNDLE NMH_APP_CONTENTS NMH_APP_MACOS NMH_APP_BINARY NMH_INFO_PLIST NMH_ENTITLEMENTS_PLIST NMH_APP_FRAMEWORKS NMH_SPARKLE_FRAMEWORK; do
  if [[ -n "${!_nmh_output_override:-}" ]]; then
    echo "$_nmh_output_override is derived from NMH_DIST_DIR and cannot be overridden" >&2
    exit 1
  fi
done
unset _nmh_output_override
NMH_APP_BUNDLE="$_nmh_expected_app_bundle"
NMH_APP_CONTENTS="$NMH_APP_BUNDLE/Contents"
NMH_APP_MACOS="$NMH_APP_CONTENTS/MacOS"
NMH_APP_BINARY="$NMH_APP_MACOS/$NMH_APP_NAME"
NMH_INFO_PLIST="$NMH_APP_CONTENTS/Info.plist"
# A build input, not a shipped resource: codesign treats a stray file directly
# under Contents/ as unsigned nested code and refuses to seal the bundle.
NMH_ENTITLEMENTS_PLIST="$NMH_DIST_DIR/NikoMusicHub.entitlements"
NMH_APP_FRAMEWORKS="$NMH_APP_CONTENTS/Frameworks"
NMH_SPARKLE_FRAMEWORK="$NMH_APP_FRAMEWORKS/Sparkle.framework"
NMH_UI_PROBE="${NMH_UI_PROBE:-$NMH_SCRIPT_DIR/ui_probe.swift}"

nmh_running_app_binary_pids() {
  local app_binary="${1:?missing app binary path}"
  /bin/ps -axo pid=,command= | /usr/bin/awk -v binary="$app_binary" '
    {
      pid = $1
      sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", $0)
      if (index($0, binary) == 1 &&
          (length($0) == length(binary) || substr($0, length(binary) + 1, 1) ~ /[[:space:]]/)) {
        print pid
      }
    }
  '
}

nmh_running_dist_app_pids() {
  nmh_running_app_binary_pids "$NMH_APP_BINARY"
}

nmh_stop_app_binary() {
  local app_binary="${1:?missing app binary path}"
  local force="${2:-false}"
  local -a pids=()
  local pid attempt

  if [[ "$app_binary" != /* ]]; then
    echo "app binary path must be absolute: $app_binary" >&2
    return 2
  fi

  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] && pids+=("$pid")
  done < <(nmh_running_app_binary_pids "$app_binary")
  ((${#pids[@]} > 0)) || return 0

  /bin/kill -TERM "${pids[@]}" >/dev/null 2>&1 || true
  for attempt in {1..10}; do
    sleep 0.3
    if ! nmh_running_app_binary_pids "$app_binary" | /usr/bin/grep -q '[0-9]'; then
      return 0
    fi
  done

  if [[ "$force" == "true" ]]; then
    pids=()
    while IFS= read -r pid; do
      [[ "$pid" =~ ^[0-9]+$ ]] && pids+=("$pid")
    done < <(nmh_running_app_binary_pids "$app_binary")
    ((${#pids[@]} == 0)) || /bin/kill -KILL "${pids[@]}" >/dev/null 2>&1 || true
    for attempt in {1..10}; do
      sleep 0.1
      if ! nmh_running_app_binary_pids "$app_binary" | /usr/bin/grep -q '[0-9]'; then
        return 0
      fi
    done
  fi

  echo "timed out stopping app at $app_binary; refusing to signal unrelated installed copies" >&2
  return 1
}

nmh_stop_app() {
  nmh_stop_app_binary "$NMH_APP_BINARY" "${1:-false}"
}

# Forget a throwaway settings suite completely. `defaults delete` only empties the
# domain; cfprefsd leaves a 42-byte plist behind, and one pair per E2E run had
# piled up to ~270 files in ~/Library/Preferences. Only call this for suites the
# caller created itself (UUID-named smoke/review suites), never for the app's
# real domain. Stop the process that owns the suite first.
nmh_forget_settings_suite() {
  local suite="${1:?missing settings suite name}"
  case "$suite" in
    ""|com.niko96.NikoMusicHub|*/*) echo "refusing to forget settings suite: $suite" >&2; return 1 ;;
  esac
  defaults delete "$suite" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$suite.plist"
}

nmh_swift() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    DEVELOPER_DIR="$DEVELOPER_DIR" swift "$@"
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift "$@"
  else
    swift "$@"
  fi
}

# Embed Sparkle.framework and teach the executable where to find it.
#
# The app links @rpath/Sparkle.framework/..., and SPM only leaves @loader_path
# on the binary, which resolves to Contents/MacOS. Without the added rpath the
# bundle launches straight into a dyld failure.
nmh_embed_sparkle_framework() {
  local build_dir="${1:?missing build directory}"
  local source_framework="$build_dir/Sparkle.framework"

  if [[ ! -d "$source_framework" ]]; then
    echo "Sparkle.framework missing from build output: $source_framework" >&2
    return 1
  fi

  mkdir -p "$NMH_APP_FRAMEWORKS"
  rm -rf "$NMH_SPARKLE_FRAMEWORK"
  # ditto keeps the versioned-bundle symlinks and executable bits that codesign
  # and the installer both depend on.
  /usr/bin/ditto "$source_framework" "$NMH_SPARKLE_FRAMEWORK"

  if ! /usr/bin/otool -l "$NMH_APP_BINARY" \
    | /usr/bin/grep -q '@executable_path/../Frameworks'; then
    /usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$NMH_APP_BINARY"
  fi
}

# Decide whether this bundle ships a live update configuration.
#
# Fail-closed on both axes: debug bundles stay inert unless a test feed is named
# explicitly, and no bundle gets a feed URL without a matching public key. Sets
# NMH_SPARKLE_PLIST_FRAGMENT (possibly empty) and NMH_UPDATE_STATE for logging.
nmh_resolve_update_configuration() {
  local key url
  NMH_SPARKLE_PLIST_FRAGMENT=""

  if ! key="$(nmh_sparkle_public_ed_key)"; then
    return 1
  fi

  if [[ -z "$key" ]]; then
    NMH_UPDATE_STATE="disabled: no SPARKLE_PUBLIC_ED_KEY"
    return 0
  fi

  if [[ "$NMH_BUILD_CONFIGURATION" != "release" && -z "${NMH_UPDATE_FEED_URL:-}" ]]; then
    NMH_UPDATE_STATE="disabled: $NMH_BUILD_CONFIGURATION build without an explicit NMH_UPDATE_FEED_URL"
    return 0
  fi

  url="$(nmh_update_feed_url)" || return 1

  # SUVerifyUpdateBeforeExtraction is SURequireSignedFeed's prerequisite: the
  # enclosure signature must be checked before anything is unpacked.
  NMH_SPARKLE_PLIST_FRAGMENT="$(cat <<SPARKLE_KEYS
  <key>SUFeedURL</key>
  <string>$url</string>
  <key>SUPublicEDKey</key>
  <string>$key</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
  <key>SURequireSignedFeed</key>
  <true/>
SPARKLE_KEYS
)"
  if [[ -n "${NMH_UPDATE_FEED_URL:-}" ]]; then
    NMH_UPDATE_STATE="enabled against OVERRIDDEN TEST FEED $url"
  else
    NMH_UPDATE_STATE="enabled against $url"
  fi
}

# Sign the bundle inside-out.
#
# Deliberately not `codesign --deep`: it is deprecated for signing, and it would
# stamp the app's own entitlements onto Sparkle's updater and installer helpers.
# Nested code is signed first, then the app wrapper.
nmh_sign_bundle() {
  local identity="${1:?missing signing identity}"
  local -a sign_options=()
  local nested

  # Ad-hoc signatures cannot carry a hardened runtime. Bash 3.2 treats an empty
  # array expansion as unbound under `set -u`, so always keep at least one
  # element rather than relying on "${array[@]}" of an empty array.
  sign_options=(--force)
  if [[ "$identity" != "-" ]]; then
    # Notarization rejects every nested Sparkle binary whose signature lacks a
    # secure timestamp (1.5.0 was refused for exactly that), so request one
    # explicitly for real identities. Ad-hoc signatures cannot carry one.
    sign_options+=(--options runtime --timestamp)
  else
    sign_options+=(--timestamp=none)
  fi

  if [[ -d "$NMH_SPARKLE_FRAMEWORK" ]]; then
    for nested in "$NMH_SPARKLE_FRAMEWORK/Versions/B/XPCServices/"*.xpc; do
      [[ -e "$nested" ]] || continue
      /usr/bin/codesign "${sign_options[@]}" --sign "$identity" "$nested" >/dev/null
    done
    for nested in \
      "$NMH_SPARKLE_FRAMEWORK/Versions/B/Updater.app" \
      "$NMH_SPARKLE_FRAMEWORK/Versions/B/Autoupdate" \
      "$NMH_SPARKLE_FRAMEWORK/Versions/B"; do
      [[ -e "$nested" ]] || continue
      /usr/bin/codesign "${sign_options[@]}" --sign "$identity" "$nested" >/dev/null
    done
  fi

  /usr/bin/codesign "${sign_options[@]}" \
    --entitlements "$NMH_ENTITLEMENTS_PLIST" \
    --sign "$identity" "$NMH_APP_BUNDLE" >/dev/null
}

nmh_build_bundle() {
  cd "$NMH_ROOT_DIR"

  local build_dir build_binary
  # NOTE: --show-bin-path only PRINTS the path — it does not compile. Build first,
  # otherwise the bundle silently ships a stale binary (burned us on 2026-07-02).
  (
    cd "$NMH_ROOT_DIR" || exit 1
    nmh_swift build -c "$NMH_BUILD_CONFIGURATION" --product "$NMH_APP_NAME"
  )
  build_dir="$(
    cd "$NMH_ROOT_DIR" || exit 1
    nmh_swift build -c "$NMH_BUILD_CONFIGURATION" --product "$NMH_APP_NAME" --show-bin-path
  )"
  build_binary="$build_dir/$NMH_APP_NAME"

  rm -rf "$NMH_APP_BUNDLE"
  mkdir -p "$NMH_APP_MACOS"
  cp "$build_binary" "$NMH_APP_BINARY"
  chmod +x "$NMH_APP_BINARY"

  nmh_embed_sparkle_framework "$build_dir"

  local brand_dir="$NMH_ROOT_DIR/Resources/Brand"
  local app_resources="$NMH_APP_CONTENTS/Resources"
  if [[ -d "$brand_dir" ]]; then
    mkdir -p "$app_resources"
    for asset in AppIcon.icns AppLogo-48.png AppLogo-96.png; do
      if [[ -f "$brand_dir/$asset" ]]; then
        cp "$brand_dir/$asset" "$app_resources/$asset"
      fi
    done
  fi

  printf 'APPL????' >"$NMH_APP_CONTENTS/PkgInfo"

  nmh_resolve_update_configuration || exit 1
  printf 'update configuration: %s\n' "$NMH_UPDATE_STATE"

  cat >"$NMH_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$NMH_APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$NMH_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Niko Music Hub</string>
  <key>CFBundleDisplayName</key>
  <string>Niko Music Hub</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$NMH_MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$NMH_BUILD_VERSION</string>
  <key>NMHBuildID</key>
  <string>$NMH_BUILD_ID</string>
  <key>NMHBuildConfiguration</key>
  <string>$NMH_BUILD_CONFIGURATION</string>
  <key>NMHSourceCommit</key>
  <string>$NMH_SOURCE_COMMIT</string>
  <key>LSMultipleInstancesSupported</key>
  <false/>
  <key>LSMinimumSystemVersion</key>
  <string>$NMH_MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>Niko Music Hub needs access to record your Mac's internal audio so you can import recordings directly into Cubase.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Niko Music Hub does not record your microphone. Recorder uses system audio capture; allow it under Screen &amp; System Audio Recording in System Settings.</string>
$NMH_SPARKLE_PLIST_FRAGMENT
</dict>
</plist>
PLIST

  cat >"$NMH_ENTITLEMENTS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.audio-input</key>
  <true/>
</dict>
</plist>
PLIST

  local sign_identity
  sign_identity="${NMH_SIGNING_IDENTITY:-}"
  if [[ -z "$sign_identity" ]]; then
    sign_identity="$(
      /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
        | awk '/Apple Development:/ && $0 !~ /REVOKED|EXPIRED/ { print $2; exit }'
    )"
  fi
  nmh_sign_bundle "${sign_identity:--}"
}

nmh_open_app() {
  local open_args=(-n "$@")
  local var
  for var in NIKO_MUSIC_HUB_DRY_RUN_OPEN NIKO_MUSIC_HUB_FIXTURE_ROOT NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT NIKO_MUSIC_HUB_E2E_SMOKE NIKO_MUSIC_HUB_SETTINGS_SUITE NIKO_MUSIC_HUB_SHOW_DEV_TOOL NIKO_MUSIC_HUB_UI_TOOL NIKO_MUSIC_HUB_DISABLE_ARCHIVE_WATCHER; do
    if [[ -n "${!var+x}" ]]; then
      open_args+=(--env "$var=${!var}")
    fi
  done
  open_args+=("$NMH_APP_BUNDLE")
  if [[ -n "${NIKO_MUSIC_HUB_UI_TOOL:-}" ]]; then
    open_args+=(--args -ui-tool "$NIKO_MUSIC_HUB_UI_TOOL")
  fi
  /usr/bin/open "${open_args[@]}"
}

nmh_focus_app() {
  /usr/bin/osascript -e "tell application \"System Events\" to tell process \"$NMH_APP_NAME\" to set frontmost to true" >/dev/null 2>&1 || true
}

nmh_ui_probe() {
  swift "$NMH_UI_PROBE" \
    --app-name "$NMH_APP_NAME" \
    --window-title "$NMH_WINDOW_TITLE" \
    --min-width "$NMH_WINDOW_MIN_WIDTH" \
    --min-height "$NMH_WINDOW_MIN_HEIGHT" \
    "$@"
}
