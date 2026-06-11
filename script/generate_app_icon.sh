#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BRAND_DIR="Resources/Brand"
SOURCE="${1:-}"
SOURCE_MASTER="$BRAND_DIR/AppLogo-source.png"
LOGO_PNG="$BRAND_DIR/AppLogo.png"
ICONSET="$BRAND_DIR/AppIcon.iconset"
RENDER_SCRIPT="script/render_dock_icon.swift"
GLYPH_SCALE="${GLYPH_SCALE:-0.72}"

mkdir -p "$BRAND_DIR"

if [[ -n "$SOURCE" && -f "$SOURCE" ]]; then
  echo "== extract logo from source → $SOURCE_MASTER =="
  ffmpeg -y -i "$SOURCE" \
    -vf "colorkey=0x000000:0.22:0.06,format=rgba" \
    -frames:v 1 -update 1 \
    "$SOURCE_MASTER" >/dev/null 2>&1
elif [[ ! -f "$SOURCE_MASTER" ]]; then
  echo "Usage: $0 <logo-source.jpg|png>  (or keep $SOURCE_MASTER and re-run)" >&2
  exit 1
fi

echo "== macOS dock icon master → $LOGO_PNG =="
# Render only the white glyph on a flat blue canvas. Pre-baked squircles and
# padded sources fight the system mask and show up as oversized square tiles.
TMP_LOGO="$BRAND_DIR/.AppLogo-render.png"
swift "$RENDER_SCRIPT" "$SOURCE_MASTER" "$TMP_LOGO" "$GLYPH_SCALE"
# Dock icons must be fully opaque; stray alpha shows as white in Finder/Dock.
ffmpeg -y -i "$TMP_LOGO" -pix_fmt rgb24 -frames:v 1 -update 1 "$LOGO_PNG" >/dev/null 2>&1
rm -f "$TMP_LOGO"

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
