#!/usr/bin/env bash
#
# Create or update the Homebrew tap (PradiptaPutra/homebrew-tap) with the current
# Potret cask, so users can install cleanly with:
#
#   brew install --cask --no-quarantine PradiptaPutra/tap/potret
#
# Run this AFTER `scripts/release.sh` and `gh release create` for a version.
# Requires: gh (authenticated as the repo owner), Node, and the built .dmg.
#
# Usage (from the repo root):
#   ./scripts/publish-homebrew-cask.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(node -p "require('${ROOT}/package.json').version")"
DMG="${ROOT}/dist-dmg/Potret_${VERSION}_universal.dmg"
TAP="PradiptaPutra/homebrew-tap"          # users tap this as "PradiptaPutra/tap"
REPO="PradiptaPutra/potret"

[ -f "$DMG" ] || { echo "✗ Missing ${DMG} — run scripts/release.sh first."; exit 1; }
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

WORK="$(mktemp -d)"
if gh repo view "$TAP" >/dev/null 2>&1; then
  echo "▸ Tap ${TAP} exists — updating…"
  git clone -q "https://github.com/${TAP}.git" "$WORK"
else
  echo "▸ Creating public tap repo ${TAP}…"
  gh repo create "$TAP" --public -d "Homebrew tap for Potret" >/dev/null
  git -C "$WORK" init -q
  git -C "$WORK" remote add origin "https://github.com/${TAP}.git"
  git -C "$WORK" branch -M main
fi

mkdir -p "${WORK}/Casks"
cat > "${WORK}/Casks/potret.rb" <<RB
cask "potret" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/${REPO}/releases/download/v#{version}/Potret_#{version}_universal.dmg",
      verified: "github.com/${REPO}/"
  name "Potret"
  desc "Free, open-source screenshot & annotation tool"
  homepage "https://github.com/${REPO}"

  app "Potret.app"

  # Potret isn't Apple-notarized, so after install: strip quarantine (no Gatekeeper
  # prompt) and register with LaunchServices (so it shows in Launchpad / Spotlight).
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Potret.app"]
    system_command "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                   args: ["-f", "#{appdir}/Potret.app"]
  end

  # \`brew uninstall --zap potret\` removes the app AND all of its data.
  zap trash: [
    "~/Library/Application Support/com.potret.app",
    "~/Library/Caches/com.potret.app",
    "~/Library/Caches/potret",
    "~/Library/Preferences/com.potret.app.plist",
    "~/Library/Saved Application State/com.potret.app.savedState",
    "~/Library/WebKit/com.potret.app",
    "~/Library/LaunchAgents/Potret.plist",
  ]
end
RB

cat > "${WORK}/README.md" <<MD
# PradiptaPutra/homebrew-tap

Homebrew tap for [Potret](https://github.com/${REPO}) — a free, open-source macOS screenshot & annotation tool.

\`\`\`bash
brew install --cask PradiptaPutra/tap/potret   # install (auto-handles Gatekeeper + Launchpad)
brew upgrade --cask potret                     # update
brew uninstall --zap potret                    # uninstall + remove all data
\`\`\`

The cask strips the quarantine flag and registers the app after install, so it opens without
the Gatekeeper prompt and appears in Launchpad — even though Potret isn't Apple-notarized.
MD

git -C "$WORK" add .
git -C "$WORK" commit -q -m "Potret cask v${VERSION}"
git -C "$WORK" push -u origin main

echo ""
echo "✓ Tap published. Users install with:"
echo "    brew install --cask PradiptaPutra/tap/potret"
