#!/usr/bin/env bash
# renders every platform icon from the two svg sources in assets/icon/:
#   veilist_icon.svg    - the full icon (opaque background), used for ios, web
#                         and the legacy square android launcher
#   veilist_icon_fg.svg - the adaptive-icon foreground (transparent), also the
#                         android 13+ monochrome layer
# needs inkscape. run it after editing either svg and commit the pngs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ICON="assets/icon/veilist_icon.svg"
FG="assets/icon/veilist_icon_fg.svg"
# the icon's background, also android's adaptive-icon background color (see
# android/app/src/main/res/values/ic_launcher_background.xml).
BG="#121318"

for tool in inkscape magick; do
  command -v "$tool" >/dev/null || { echo "!! $tool not found" >&2; exit 1; }
done

render() { # svg size out
  inkscape "$1" --export-type=png --export-width="$2" --export-height="$2" \
    --export-filename="$3" >/dev/null 2>&1
  echo "  $3 (${2}px)"
}

echo "== android launcher (square) + adaptive foreground =="
# density -> (launcher px, foreground px). the foreground is 108/48 larger, so
# the adaptive icon's safe zone lands where the layout expects it.
for d in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  IFS=: read -r dpi launcher fg <<<"$d"
  out="android/app/src/main/res/mipmap-$dpi"
  render "$ICON" "$launcher" "$out/ic_launcher.png"
  render "$FG" "$fg" "$out/ic_launcher_foreground.png"
done

echo "== web =="
render "$ICON" 64 web/favicon.png
for s in 192 512; do
  render "$ICON" "$s" "web/icons/Icon-$s.png"
  # the artwork already keeps a wide margin, so the maskable variant is the
  # same rendering; a mask crop cannot reach the shield.
  render "$ICON" "$s" "web/icons/Icon-maskable-$s.png"
done

echo "== ios =="
IOS="ios/Runner/Assets.xcassets/AppIcon.appiconset"
for e in 20x20@1x:20 20x20@2x:40 20x20@3x:60 29x29@1x:29 29x29@2x:58 \
         29x29@3x:87 40x40@1x:40 40x40@2x:80 40x40@3x:120 60x60@2x:120 \
         60x60@3x:180 76x76@1x:76 76x76@2x:152 83.5x83.5@2x:167 \
         1024x1024@1x:1024; do
  IFS=: read -r name px <<<"$e"
  out="$IOS/Icon-App-$name.png"
  render "$ICON" "$px" "$out"
  # ios rejects an app icon with an alpha channel and rounds the corners
  # itself, so fill the artwork's rounded corners and drop alpha entirely.
  magick "$out" -background "$BG" -alpha remove -alpha off "$out"
done
