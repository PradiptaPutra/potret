#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from the 1024px master.
#
# actool — the tool that compiles .xcassets into Assets.car — ships only with Xcode, so there is
# no asset catalog here. A loose .icns referenced by CFBundleIconFile is fully supported by macOS
# and is the right answer for a hand-assembled bundle. sips and iconutil are both part of the
# base system, so this needs nothing installed.
set -euo pipefail

cd "$(dirname "$0")/.."
MASTER="../src-tauri/icons/potret-aperture-1024.png"
OUT="Resources/AppIcon.icns"

[[ -f "$MASTER" ]] || { echo "error: master icon not found at $MASTER" >&2; exit 1; }

STAGE="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$STAGE"

# The set macOS actually asks for: 16/32/128/256/512 at @1x and @2x.
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$STAGE/icon_${size}x${size}.png" > /dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$MASTER" \
        --out "$STAGE/icon_${size}x${size}@2x.png" > /dev/null
done

iconutil --convert icns --output "$OUT" "$STAGE"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
