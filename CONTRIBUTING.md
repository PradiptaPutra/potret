# Contributing to Potret

Thanks for your interest! Bug reports and small fixes can go straight to a PR;
for anything substantial, please open an issue first to discuss the approach.

## Development setup

Requirements: macOS, [Rust](https://rustup.rs), Node.js 18+, Xcode command line tools.

```bash
npm install
npm run tauri dev
```

The app is **Tauri 2** (Rust backend) + **React 19 / TypeScript** (frontend):

```
src/                  React frontend — capture UI, annotation, popup, settings
src-tauri/src/lib.rs  Rust backend — capture pipeline, windows, history, config, commands
scripts/release.sh    Build a signed, universal .dmg for a release
```

Before opening a PR, make sure both build cleanly:

```bash
npm run build                                            # frontend (tsc + vite)
cargo build --manifest-path src-tauri/Cargo.toml         # backend
```

## Building a release (.dmg)

Releases are universal (Intel + Apple Silicon) and built with one command:

```bash
rustup target add x86_64-apple-darwin   # one-time, for the Intel slice
./scripts/release.sh
```

This produces `dist-dmg/Potret_<version>_universal.dmg`.

> **Why a script instead of plain `tauri build`?** `tauri build --target universal-apple-darwin`
> leaves the universal binary with a broken ad-hoc signature (a known lipo issue), which prevents
> macOS from persisting the Screen Recording permission, and its built-in `.dmg` step needs Finder
> automation. `scripts/release.sh` rebuilds, **deep re-signs** the app, and packages the `.dmg`
> (with an "OPEN ME FIRST" install guide) correctly and reproducibly.

Publish it:

```bash
gh release create v<version> dist-dmg/Potret_<version>_universal.dmg --title "Potret v<version>"
```

### Signing & notarization

Builds are **ad-hoc signed** (no Apple Developer account). Consequences:

- Users see a one-time Gatekeeper warning on first launch (documented in the README).
- The Screen Recording permission is tied to the signature, so it must be re-granted after each
  **update** (each ad-hoc build has a different signature).

A paid **Apple Developer ID + notarization** would remove the Gatekeeper warning entirely and make
the permission persist across updates. If/when that's set up, the signing identity in
`scripts/release.sh` (`--sign -`) would be swapped for the Developer ID and a notarization step added.
