# Shared Niko Music Hub app lifecycle helpers for shell scripts.
# shellcheck shell=bash

NMH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NMH_SCRIPT_DIR="$(cd "$NMH_LIB_DIR/.." && pwd)"
NMH_ROOT_DIR="$(cd "$NMH_SCRIPT_DIR/.." && pwd)"

NMH_APP_NAME="${NMH_APP_NAME:-NikoMusicHub}"
NMH_BUNDLE_ID="${NMH_BUNDLE_ID:-local.niko-music-hub.app}"
NMH_MARKETING_VERSION="${NMH_MARKETING_VERSION:-1.4}"
NMH_BUILD_VERSION="${NMH_BUILD_VERSION:-4}"
NMH_MIN_SYSTEM_VERSION="${NMH_MIN_SYSTEM_VERSION:-14.2}"
NMH_LAUNCH_WAIT_SEC="${NMH_LAUNCH_WAIT_SEC:-8}"
NMH_WINDOW_TITLE="${NMH_WINDOW_TITLE:-Niko Music Hub}"
NMH_WINDOW_MIN_WIDTH="${NMH_WINDOW_MIN_WIDTH:-400}"
NMH_WINDOW_MIN_HEIGHT="${NMH_WINDOW_MIN_HEIGHT:-300}"

NMH_DIST_DIR="${NMH_DIST_DIR:-$NMH_ROOT_DIR/dist}"
NMH_APP_BUNDLE="${NMH_APP_BUNDLE:-$NMH_DIST_DIR/$NMH_APP_NAME.app}"
NMH_APP_CONTENTS="${NMH_APP_CONTENTS:-$NMH_APP_BUNDLE/Contents}"
NMH_APP_MACOS="${NMH_APP_MACOS:-$NMH_APP_CONTENTS/MacOS}"
NMH_APP_BINARY="${NMH_APP_BINARY:-$NMH_APP_MACOS/$NMH_APP_NAME}"
NMH_INFO_PLIST="${NMH_INFO_PLIST:-$NMH_APP_CONTENTS/Info.plist}"
NMH_ENTITLEMENTS_PLIST="${NMH_ENTITLEMENTS_PLIST:-$NMH_APP_CONTENTS/NikoMusicHub.entitlements}"
NMH_UI_PROBE="${NMH_UI_PROBE:-$NMH_SCRIPT_DIR/ui_probe.swift}"

nmh_stop_app() {
  local force="${1:-false}"
  /usr/bin/pkill -x "$NMH_APP_NAME" >/dev/null 2>&1 || true
  sleep 0.3
  if /usr/bin/pgrep -x "$NMH_APP_NAME" >/dev/null 2>&1; then
    if [[ "$force" == "true" ]]; then
      /usr/bin/killall -9 "$NMH_APP_NAME" >/dev/null 2>&1 || true
      sleep 0.3
    fi
  fi
}

nmh_build_bundle() {
  cd "$NMH_ROOT_DIR"

  local build_dir build_binary
  build_dir="$(
    cd "$NMH_ROOT_DIR" || exit 1
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
      swift build --product "$NMH_APP_NAME" --show-bin-path
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
  sign_identity="$(
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
      | awk '/Apple Development:/ && $0 !~ /REVOKED|EXPIRED/ { print $2; exit }'
  )"
  if [[ -n "$sign_identity" ]]; then
    /usr/bin/codesign --force --deep --options runtime --entitlements "$NMH_ENTITLEMENTS_PLIST" --sign "$sign_identity" "$NMH_APP_BUNDLE" >/dev/null
  else
    /usr/bin/codesign --force --deep --sign - "$NMH_APP_BUNDLE" >/dev/null
  fi
}

nmh_open_app() {
  local open_args=(-n)
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
