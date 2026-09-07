#!/usr/bin/env bash
# Build, sign and package a release of the native app.
#
#   ./scripts/setup-signing-cert.sh     # once: the stable self-signed identity
#   ./scripts/release.sh                # → dist-dmg/Potret_<version>_universal.dmg
#   gh release create v<version> dist-dmg/Potret_<version>_universal.dmg ...
#   ./scripts/publish-homebrew-cask.sh
#
# The version comes from macos/VERSION. Everything else is in macos/scripts: build-app.sh makes
# the universal, signed bundle (--release-id gives it com.potret.app, which is what keeps the
# Screen Recording grant across updates) and build-dmg.sh refuses to package anything that is not
# signed with the stable identity or does not carry the release bundle id.
set -euo pipefail
cd "$(dirname "$0")/.."

./macos/scripts/test.sh
./macos/scripts/lint-design.sh
./macos/scripts/build-app.sh --release-id
./macos/scripts/build-dmg.sh
