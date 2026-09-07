# Contributing to Potret

Thanks for your interest! Bug reports and small fixes can go straight to a PR;
for anything substantial, please open an issue first to discuss the approach.

## Development setup

Requirements: macOS 14+, and the Swift toolchain — Xcode **or** just the Command Line Tools
(`xcode-select --install`). The project builds without Xcode on purpose; `macos/TESTING.md`
explains what that removes (no XCTest, no asset catalogs, no previews) and how each is handled.

```bash
./macos/scripts/run.sh     # build, sign and relaunch the dev app
./macos/scripts/test.sh    # swift-testing suite — do not call `swift test` directly
./macos/scripts/lint-design.sh
```

The app is a Swift package in `macos/` with a strictly linear dependency chain:

```
Potret → PotretUI → {PotretCapture, PotretRender, PotretRecord} → PotretCore
```

`PotretCore` imports Foundation and CoreGraphics only. That is the testability boundary: keep
model and logic there, and it can be tested headless with no display and no permission grant.

Before opening a PR, make sure all three pass:

```bash
./macos/scripts/test.sh && ./macos/scripts/lint-design.sh && ./macos/scripts/build-app.sh
```

`lint-design.sh` fails on hardcoded colours, font sizes or corner radii outside
`Sources/PotretUI/Design/Theme.swift`, and on `NSApp.activate` outside `MainWindowController` —
every overlay is a non-activating panel, and an activate() anywhere else brings back the
focus-stealing bugs the rewrite exists to remove.

## Building a release (.dmg)

```bash
./scripts/setup-signing-cert.sh   # one-time: creates the stable "Potret Self-Signed" identity
./scripts/release.sh              # test, lint, build universal, sign, package
```

This produces `dist-dmg/Potret_<version>_universal.dmg`. The version is `macos/VERSION`.

> **Why a stable self-signed identity?** macOS ties the Screen Recording grant to the signing
> certificate. An ad-hoc build has a different identity every time, so users would be asked for
> the permission again after every update. `build-dmg.sh` refuses to package an ad-hoc build, or
> one carrying the development bundle id.

Publish it:

```bash
gh release create v<version> dist-dmg/Potret_<version>_universal.dmg --title "Potret v<version>"
./scripts/publish-homebrew-cask.sh
```

The DMG filename, volume name and `app "Potret.app"` stanza are a contract with the Homebrew
cask — every existing `brew upgrade` depends on them.

### Notarization

Builds are not notarized (no Apple Developer account), so users see a one-time Gatekeeper prompt
on first launch; the README and the DMG's install guide cover it. A Developer ID plus
`notarytool` would remove that prompt; the signing identity in `macos/scripts/build-app.sh`
would be swapped for it.
