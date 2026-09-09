#!/usr/bin/env bash
# Package the built app into a DMG.
#
# Ported from the Tauri scripts/release.sh, minus the parts that only existed to work around
# Tauri: its universal build produced a broken ad-hoc signature that had to be repaired, and its
# built-in DMG step needed Finder automation permission. Neither applies now — build-app.sh
# produces a correctly signed universal binary, and hdiutil needs nothing.
#
# The output name, the volume name and the enclosed app name are a contract with the Homebrew
# cask: publish-homebrew-cask.sh builds its URL from the version. Changing any of them breaks
# every existing `brew upgrade`.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Potret.app"
VERSION="$(tr -d '[:space:]' < VERSION)"
OUTPUT_DIR="$ROOT/../dist-dmg"
OUTPUT="$OUTPUT_DIR/Potret_${VERSION}_universal.dmg"

[[ -d "$APP" ]] || {
    echo "error: $APP not found — run ./scripts/build-app.sh --release-id first" >&2
    exit 1
}

# Ship what will actually be installed. Refuse an ad-hoc signature: TCC keys the Screen Recording
# grant on the signing identity, so an ad-hoc build re-prompts every user on every update.
# Captured rather than piped into grep -q: `grep -q` exits as soon as it matches, codesign takes
# SIGPIPE, and `set -o pipefail` turns that success into a pipeline failure — so the check
# reported "not signed" for a correctly signed app.
SIGNATURE="$(codesign -dvv "$APP" 2>&1 || true)"
if ! grep -q "Authority=Potret Self-Signed" <<< "$SIGNATURE"; then
    echo "error: $APP is not signed with 'Potret Self-Signed'." >&2
    echo "       Packaging it would make macOS re-request Screen Recording after every update." >&2
    echo "       Fix: ../scripts/setup-signing-cert.sh, then rebuild." >&2
    exit 1
fi

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")"
if [[ "$BUNDLE_ID" != "com.potret.app" ]]; then
    echo "error: bundle id is $BUNDLE_ID, not com.potret.app." >&2
    echo "       Build with --release-id before packaging, or upgrading users lose their grant." >&2
    exit 1
fi

STAGE="$(mktemp -d)"
mkdir -p "$OUTPUT_DIR"
cp -R "$APP" "$STAGE/"
# Re-sign the copy: cp can break a signature, which is what bit the Tauri pipeline.
codesign --force --sign "Potret Self-Signed" --identifier com.potret.app \
    --timestamp=none "$STAGE/Potret.app"
ln -s /Applications "$STAGE/Applications"

# Kept from the Tauri release for as long as builds are not notarized: without it the first open
# is blocked with "Apple could not verify…" and users assume the app is broken.
cat > "$STAGE/① OPEN ME FIRST.txt" <<'GUIDE'
Installing Potret
=================

1. Drag Potret into the Applications folder shown here.
2. Eject this disk image.
3. The first time you open Potret, macOS will say it "could not verify" the app.
   That is expected: Potret is open source and not notarized by Apple.

   Either:
     • Terminal:  xattr -dr com.apple.quarantine /Applications/Potret.app
     • Or:        double-click Potret, click Done, then open
                  System Settings > Privacy & Security and click "Open Anyway".

4. Grant Screen Recording under System Settings > Privacy & Security,
   then quit and reopen Potret. It lives in the menu bar, not the Dock.

Installing with Homebrew instead does all of this for you:
   brew install --cask PradiptaPutra/tap/potret
GUIDE

rm -f "$OUTPUT"
hdiutil create -volname "Potret" -srcfolder "$STAGE" -ov -format UDZO "$OUTPUT" > /dev/null

echo "Built $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
echo
echo "Next:"
echo "  gh release create v$VERSION '$OUTPUT' --title 'v$VERSION' --notes '…'"
echo "  ../scripts/publish-homebrew-cask.sh"
