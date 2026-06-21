#!/usr/bin/env bash
#
# Build a signed, universal Potret .dmg ready to attach to a GitHub release.
#
# Why this script exists:
#   `tauri build --target universal-apple-darwin` produces a universal app whose
#   ad-hoc signature is broken (a known lipo issue). A broken signature stops
#   macOS from persisting the Screen Recording permission, and Tauri's own .dmg
#   step also fails without Finder/AppleScript access. This script rebuilds,
#   *deep re-signs* the app, and packages the .dmg correctly — reproducibly.
#
# Usage (from the repo root):
#   ./scripts/release.sh
#
# Output:
#   dist-dmg/Potret_<version>_universal.dmg   (drag-to-install, with an install guide inside)
#
# Then publish:
#   gh release create v<version> dist-dmg/Potret_<version>_universal.dmg --title "Potret v<version>"
#
# Requirements: Rust + the x86_64 target (`rustup target add x86_64-apple-darwin`),
# Node 18+, and Xcode command line tools. macOS only.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Potret"
VERSION="$(node -p "require('./package.json').version")"
APP="src-tauri/target/universal-apple-darwin/release/bundle/macos/${APP_NAME}.app"
OUT_DIR="dist-dmg"
DMG="${OUT_DIR}/${APP_NAME}_${VERSION}_universal.dmg"

echo "▸ Building universal app (Intel + Apple Silicon) — this takes a few minutes…"
# Tauri's .dmg bundling step fails without AppleScript access; the .app still
# builds fine, so don't abort on that — we make the .dmg ourselves below.
npm run tauri build -- --target universal-apple-darwin || true

[ -d "$APP" ] || { echo "✗ Build did not produce ${APP}"; exit 1; }

echo "▸ Deep re-signing the app (repairs the broken universal signature)…"
codesign --force --deep --sign - "$APP"
codesign -v --deep --strict "$APP" >/dev/null && echo "  ✓ signature valid"

echo "▸ Staging .dmg contents…"
STAGE="$(mktemp -d)"
cp -R "$APP" "${STAGE}/${APP_NAME}.app"
codesign --force --deep --sign - "${STAGE}/${APP_NAME}.app"   # re-sign the copy too
ln -s /Applications "${STAGE}/Applications"
cat > "${STAGE}/① OPEN ME FIRST.txt" <<'GUIDE'
HOW TO INSTALL & OPEN POTRET

EASIEST — Homebrew (no Gatekeeper prompt):
   brew install --cask --no-quarantine PradiptaPutra/tap/potret

Or install from this disk image:

1) Drag  Potret  onto the  Applications  folder (both are in this window).
   ⚠️ Do NOT double-click Potret here — copy it to Applications first.

2) Open your Applications folder and double-click Potret.
   macOS says "Apple could not verify..." (expected for open-source apps) — click  Done.

3) Open  System Settings → Privacy & Security , scroll down, and click
   "Open Anyway"  next to Potret.

4) On first capture, grant Screen Recording permission, then click "Restart"
   in Potret's banner.

NOTE: Potret runs in your MENU BAR (top-right of the screen), not the Dock.

----
Prefer Terminal? Run this instead of steps 2-3:
   xattr -dr com.apple.quarantine /Applications/Potret.app
GUIDE

echo "▸ Creating ${DMG}…"
mkdir -p "$OUT_DIR"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo ""
echo "✓ Done:  ${DMG}"
echo "  Publish:  gh release create v${VERSION} \"${DMG}\" --title \"${APP_NAME} v${VERSION}\""
echo "  Then:     ./scripts/publish-homebrew-cask.sh   (create/update the Homebrew tap)"
