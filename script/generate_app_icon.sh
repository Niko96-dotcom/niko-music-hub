#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BRAND_DIR="Resources/Brand"
SOURCE="${1:-}"
LOGO_PNG="$BRAND_DIR/AppLogo.png"
ICONSET="$BRAND_DIR/AppIcon.iconset"

mkdir -p "$BRAND_DIR"

if [[ -n "$SOURCE" && -f "$SOURCE" ]]; then
  echo "== remove black background → $LOGO_PNG =="
  ffmpeg -y -i "$SOURCE" \
    -vf "colorkey=0x000000:0.22:0.06,format=rgba" \
    -frames:v 1 -update 1 \
    "$LOGO_PNG" >/dev/null
elif [[ ! -f "$LOGO_PNG" ]]; then
  echo "Usage: $0 <logo-source.jpg|png>  (or keep $LOGO_PNG and re-run)" >&2
  exit 1
fi

echo "== sidebar PNGs =="
sips -z 48 48 "$LOGO_PNG" --out "$BRAND_DIR/AppLogo-48.png" >/dev/null
sips -z 96 96 "$LOGO_PNG" --out "$BRAND_DIR/AppLogo-96.png" >/dev/null

echo "== AppIcon.icns =="
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$LOGO_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$LOGO_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BRAND_DIR/AppIcon.icns"
rm -rf "$ICONSET"

echo "Done: $BRAND_DIR/AppIcon.icns (rebuild .app with ./script/build_and_run.sh)"
