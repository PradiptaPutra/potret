#!/usr/bin/env bash
# Guard the design system and the activation rule.
#
# A design system nobody enforces is just a document. The Tauri app had a full set of CSS
# variables in src/index.css that roughly half the components ignored, which is how it ended up
# with 12 corner radii, 8 font sizes and two different greens. These greps are the difference.
#
# Rules:
#   1. Colours come from the system (Color.accentColor, .primary, NSColor.separatorColor …) or
#      from Theme.swift. Hardcoded literals elsewhere break Light/Dark and Increase Contrast.
#   2. Fonts come from the semantic ramp, never .system(size:).
#   3. Corner radii come from Radius.*, so the scale stays a scale.
#   4. NSApp.activate() lives in exactly one file. Every overlay is a non-activating panel; an
#      activate() call anywhere else is what drags the user across Spaces (the bug that produced
#      seven consecutive Tauri releases).
set -euo pipefail

cd "$(dirname "$0")/.."
SOURCES="Sources"
STATUS=0

# $1 = human description, $2 = scope directory, $3 = grep pattern, rest = paths allowed to match
check() {
    local description="$1" scope="$2" pattern="$3"; shift 3
    local hits
    hits="$(grep -rnE "$pattern" "$scope" --include='*.swift' || true)"
    # Comments describe the rules; they don't break them.
    hits="$(grep -vE '^[^:]+:[0-9]+: *(//|\*)' <<< "$hits" || true)"
    for path in "$@"; do
        hits="$(grep -vF "$path" <<< "$hits" || true)"
    done
    if [[ -n "$hits" ]]; then
        STATUS=1
        echo "✗ $description"
        head -10 <<< "$hits" | sed 's/^/    /'
    fi
}

# Chrome only. PotretRender and PotretCore deal in ink — the annotation palette and the colours
# baked into an exported image are document data that must serialize, not themeable UI.
check "hardcoded colour literal (use Theme or a system colour)" \
    "$SOURCES/PotretUI" \
    '(Color|NSColor)\(red:|Color\(hex' \
    "Sources/PotretUI/Design/Theme.swift"

check "hardcoded font size (use the semantic type ramp)" \
    "$SOURCES" \
    '\.font\(\.system\(size:|NSFont\.[a-zA-Z]*[Ff]ont\(ofSize:' \
    "Sources/PotretUI/Design/Theme.swift"

check "hardcoded corner radius (use Radius.sm/md/lg)" \
    "$SOURCES/PotretUI" \
    'cornerRadius: *[0-9]' \
    "Sources/PotretUI/Design/Theme.swift"

check "NSApp.activate outside the one controller allowed to activate the app" \
    "$SOURCES" \
    'NSApp\.activate|NSApplication\.shared\.activate' \
    "Sources/PotretUI/MainWindowController.swift"

if [[ $STATUS -eq 0 ]]; then
    echo "✓ design lint clean"
fi
exit $STATUS
