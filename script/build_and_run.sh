#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="NikoMusicHub"
BUNDLE_ID="local.niko-music-hub.app"
MIN_SYSTEM_VERSION="14.2"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PLIST="$APP_CONTENTS/NikoMusicHub.entitlements"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift build --product "$APP_NAME"
BUILD_BINARY="$(DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Niko Music Hub</string>
  <key>CFBundleDisplayName</key>
  <string>Niko Music Hub</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>Niko Music Hub needs access to record your Mac's internal audio so you can import recordings directly into Cubase.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Niko Music Hub uses audio capture permission only when you start Recorder, so it can save a local WAV recording to your selected output folder.</string>
</dict>
</plist>
PLIST

cat >"$ENTITLEMENTS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.audio-input</key>
  <true/>
</dict>
</plist>
PLIST

SIGN_IDENTITY="$(
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Apple Development:/ && $0 !~ /REVOKED|EXPIRED/ { print $2; exit }'
)"
if [[ -n "$SIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_PLIST" --sign "$SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
else
  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
fi

open_app() {
  local open_args=(-n)
  local var
  for var in NIKO_MUSIC_HUB_DRY_RUN_OPEN NIKO_MUSIC_HUB_FIXTURE_ROOT NIKO_MUSIC_HUB_E2E_SMOKE; do
    if [[ -n "${!var+x}" ]]; then
      open_args+=(--env "$var=${!var}")
    fi
  done
  /usr/bin/open "${open_args[@]}" "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    while IFS= read -r pid; do
      command="$(ps -p "$pid" -o command=)"
      if [[ "$command" == "$APP_BINARY"* ]]; then
        exit 0
      fi
    done < <(pgrep -x "$APP_NAME" || true)
    echo "$APP_NAME did not launch from $APP_BINARY" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
