#!/usr/bin/env bash
#
# Install the freshly built Potret.app into /Applications — the RIGHT way.
#
# Why this script exists (issue #4): replacing the app with a raw `cp -R` skips
# LaunchServices re-registration, so System Settings → Privacy & Security can keep
# tracking a stale entry that isn't linked to the binary actually running. The user
# then toggles Screen Recording on, restarts, and the app still reports the
# permission as missing. Re-registering with `lsregister -f` after every replace
# keeps the Privacy pane pointed at the real bundle (this is also what the Homebrew
# cask's postflight does).
#
# Usage (from the repo root, after ./scripts/release.sh or a tauri build):
#   ./scripts/install-local.sh
#
# Optional: pass an explicit .app path to install something other than the
# universal release build.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Potret"
SRC="${1:-$ROOT/src-tauri/target/universal-apple-darwin/release/bundle/macos/${APP_NAME}.app}"
DEST="/Applications/${APP_NAME}.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

[ -d "$SRC" ] || { echo "✗ No app bundle at ${SRC} — build first (./scripts/release.sh)"; exit 1; }

echo "▸ Quitting ${APP_NAME} (if running)…"
osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
sleep 1

echo "▸ Installing ${SRC} → ${DEST}…"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "▸ Verifying signature…"
codesign -v --deep --strict "$DEST" && echo "  ✓ signature valid"

echo "▸ Re-registering with LaunchServices (keeps the Privacy pane pointed at this bundle)…"
"$LSREGISTER" -f "$DEST"

echo "▸ Relaunching…"
open "$DEST"

echo ""
echo "✓ Installed. If macOS still claims Screen Recording is missing, reset the stale"
echo "  grant once and re-grant on next capture:"
echo "    tccutil reset ScreenCapture com.potret.app"
