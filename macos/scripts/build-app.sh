#!/usr/bin/env bash
# Assemble Potret.app by hand.
#
# There is no Xcode on this machine — only the Command Line Tools — so there is no xcodebuild, no
# asset catalog (actool requires Xcode) and no archive/export step. SwiftPM produces the universal
# binary; everything else here is bundle plumbing that Xcode would normally do.
#
# Usage:  ./scripts/build-app.sh [--debug] [--release-id]
#   --debug       build the debug configuration, current arch only (fast iteration)
#   --release-id  bundle as com.potret.app instead of com.potret.app.dev
#
# The dev identifier is the default on purpose: while the rewrite is in progress the shipped Tauri
# app keeps com.potret.app, and with it the Screen Recording grant that is keyed to that id.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

CONFIGURATION="release"
BUNDLE_ID="com.potret.app.dev"
UNIVERSAL=1

for arg in "$@"; do
    case "$arg" in
        --debug)      CONFIGURATION="debug"; UNIVERSAL=0 ;;
        --release-id) BUNDLE_ID="com.potret.app" ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="$ROOT/build/Potret.app"

echo "==> Building ($CONFIGURATION, $([[ $UNIVERSAL == 1 ]] && echo universal || echo native))"
if [[ $UNIVERSAL == 1 ]]; then
    # NOT `swift build --arch arm64 --arch x86_64`: passing two --arch flags switches SwiftPM to
    # the Xcode build system, which shells out to
    #   /Library/Developer/SharedFrameworks/XCBuild.framework/.../xcbuild
    # and that ships with Xcode, not the Command Line Tools. Building each slice against its own
    # --triple uses the native build system, then lipo joins them — same result, no Xcode.
    mkdir -p "$ROOT/build"
    UNIVERSAL_BIN="$ROOT/build/Potret-universal"
    SLICES=()
    # Unversioned triples: the deployment target comes from platforms: [.macOS(.v14)] in
    # Package.swift, and the build directory is named after the triple verbatim.
    for triple in arm64-apple-macosx x86_64-apple-macosx; do
        echo "    $triple"
        swift build -c "$CONFIGURATION" --triple "$triple" > /dev/null
        SLICES+=("$ROOT/.build/$triple/$CONFIGURATION/Potret")
    done
    lipo -create -output "$UNIVERSAL_BIN" "${SLICES[@]}"
    BIN="$UNIVERSAL_BIN"
else
    swift build -c "$CONFIGURATION"
    BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)/Potret"
fi
[[ -f "$BIN" ]] || { echo "error: binary not found at $BIN" >&2; exit 1; }

echo "==> Assembling bundle"
# Clear the previous bundle. Scoped to $ROOT/build, which only ever holds generated output.
if [[ -d "$APP" ]]; then
    /bin/rm -rf -- "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Potret"
printf 'APPL????' > "$APP/Contents/PkgInfo"

sed -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD__|$BUILD|g" \
    Resources/Info.plist.in > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "    (no AppIcon.icns yet — run ./scripts/make-icns.sh)"
fi

# A STABLE signing identity is what makes macOS keep the Screen Recording grant across updates:
# TCC keys the permission on (bundle id, signing certificate). Ad-hoc signing gives every build a
# different identity, so the user is re-prompted on every release. Falls back to ad-hoc with a
# loud warning rather than failing, so CI (which has no keychain) can still build.
SIGN_ID="Potret Self-Signed"
if ! security find-identity -p codesigning | grep -qF "$SIGN_ID"; then
    echo "    WARNING: '$SIGN_ID' not in the keychain — signing ad-hoc."
    echo "             Screen Recording will be re-requested on every build."
    echo "             Fix: ../scripts/setup-signing-cert.sh"
    SIGN_ID="-"
fi

echo "==> Signing as ${SIGN_ID}"
# No --deep (deprecated, and nothing is nested), no --options runtime (hardened runtime without
# notarization only adds failure modes), no entitlements, no sandbox.
codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "==> Verifying"
lipo -info "$APP/Contents/MacOS/Potret"
codesign -dvv "$APP" 2>&1 | grep -E "Identifier|Signature" || true
echo
echo "Built $APP  ($VERSION build $BUILD)"
