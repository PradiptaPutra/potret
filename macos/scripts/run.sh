#!/usr/bin/env bash
# Build and (re)launch the development app — the closest thing to `npm run tauri dev`.
#
# A native app has no dev server and no hot reload: every change means a rebuild and a relaunch.
# This does both, and defaults to --debug because a debug build is arm64-only and roughly four
# times faster to produce than the universal release build. It is still signed with the same
# "Potret Self-Signed" identity, so the Screen Recording grant survives between runs — TCC keys on
# (bundle id, certificate), and both are unchanged.
#
# Usage: ./scripts/run.sh [--release]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Potret.app"
BUNDLE_ID="com.potret.app.dev"

BUILD_ARGS=("--debug")
[[ "${1:-}" == "--release" ]] && BUILD_ARGS=()

# Match on the trailing path fragment, not the absolute path: an instance launched from the
# shell as ./build/Potret.app/... has a relative argv[0], and an absolute-path pattern silently
# misses it — which leaves a stale copy running, makes `open` a no-op onto it, and then reports a
# launch failure for an app that is in fact running old code.
DEV_PATTERN="build/Potret.app/Contents/MacOS/Potret"

# Only ever this build. The installed /Applications/Potret.app does not match and is left alone.
if pgrep -f "$DEV_PATTERN" > /dev/null; then
    echo "==> Quitting the running dev build"
    osascript -e "quit app id \"$BUNDLE_ID\"" 2> /dev/null || true
    for _ in $(seq 20); do
        pgrep -f "$DEV_PATTERN" > /dev/null || break
        sleep 0.25
    done
    pkill -f "$DEV_PATTERN" 2> /dev/null || true
    sleep 0.5
fi

"$ROOT/scripts/build-app.sh" "${BUILD_ARGS[@]}"

echo "==> Launching"
open "$APP"

# Poll rather than sleeping once: a cold launch after a rebuild can take several seconds, and a
# fixed wait reports a false failure for an app that was merely still starting.
LAUNCHED=0
for _ in $(seq 40); do
    if pgrep -f "$DEV_PATTERN" > /dev/null; then
        LAUNCHED=1
        break
    fi
    sleep 0.25
done

if [[ $LAUNCHED == 1 ]]; then
    echo "    running (pid $(pgrep -f "$DEV_PATTERN" | head -1)) — aperture in the menu bar"
else
    echo "    FAILED to stay running. Recent output:" >&2
    /usr/bin/log show --last 1m --predicate 'subsystem == "com.potret.app"' 2> /dev/null \
        | tail -20 >&2
    exit 1
fi

# Both apps registering the same combos means the second one loses with eventHotKeyExistsErr.
if pgrep -f "/Applications/Potret.app" > /dev/null; then
    echo
    echo "    NOTE: the installed Tauri Potret is also running and wants the same shortcuts."
    echo "          Whichever registered first wins; the dev build reports the clash as"
    echo "          'Shortcut unavailable' in its menu. Quit it to test the hotkeys properly."
fi

# Screen Recording is granted per app identity, and the dev bundle is a different identity from
# the released app, so it needs its own grant even on a machine where Potret already works.
echo
echo "    If capture does nothing: add build/Potret.app under System Settings >"
echo "    Privacy & Security > Screen Recording, then re-run this script."
