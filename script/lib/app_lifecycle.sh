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
for _nmh_output_override in NMH_APP_BUNDLE NMH_APP_CONTENTS NMH_APP_MACOS NMH_APP_BINARY NMH_INFO_PLIST NMH_ENTITLEMENTS_PLIST; do
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
NMH_ENTITLEMENTS_PLIST="$NMH_APP_CONTENTS/NikoMusicHub.entitlements"
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

nmh_swift() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    DEVELOPER_DIR="$DEVELOPER_DIR" swift "$@"
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift "$@"
  else
    swift "$@"
  fi
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
  if [[ -n "$sign_identity" ]]; then
    /usr/bin/codesign --force --deep --options runtime --entitlements "$NMH_ENTITLEMENTS_PLIST" --sign "$sign_identity" "$NMH_APP_BUNDLE" >/dev/null
  else
    /usr/bin/codesign --force --deep --sign - "$NMH_APP_BUNDLE" >/dev/null
  fi
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
