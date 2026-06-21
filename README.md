<div align="center">
  <img src="public/app-icon.png" width="88" alt="Potret" />
  <h1>Potret</h1>
  <p><strong>A free, open-source screenshot & annotation tool for macOS.</strong></p>
  <p>Inspired by CleanShot X — without the price tag.</p>
</div>

---

Potret lives in your menu bar. Take a screenshot and a floating **Quick Access** panel appears so you can copy, save, annotate, pin, drag it out, or drop it onto a beautiful background — without opening a heavy editor.

## Download

### Homebrew (recommended — cleanest install)

```bash
brew install --cask --no-quarantine PradiptaPutra/tap/potret
```

`--no-quarantine` skips the macOS Gatekeeper warning (Potret is open-source and not Apple-notarized), so it just opens. Update with `brew upgrade --cask potret`; uninstall cleanly (app **and** all its data) with `brew uninstall --zap potret`.

### Direct download (.dmg)

1. Grab the latest `.dmg` from the [**Releases**](https://github.com/PradiptaPutra/potret/releases/latest) page (universal — **Apple Silicon and Intel**).
2. Open it, drag **Potret** into **Applications** (don't run it straight from the disk image), then **eject** the disk image.

> #### ⚠️ First launch — one-time step
> Without Apple notarization, the first open is blocked with *"Apple could not verify…"* — expected for open-source apps. Either:
> - **Terminal (one command):** `xattr -dr com.apple.quarantine /Applications/Potret.app`, then open Potret.
> - **No Terminal:** double-click Potret → **Done**, then **System Settings → Privacy & Security → "Open Anyway"**.
>
> Then grant **Screen Recording** (System Settings → Privacy & Security → Screen Recording) and restart. **Potret lives in your menu bar (top-right), not the Dock.**

**Uninstall:** `brew uninstall --zap potret` (cask), or drag **Potret** from Applications to the Trash.

Prefer to build it yourself (no Gatekeeper prompt)? See [Development](#getting-started) below.

## Screenshots

<div align="center">
  <img src="docs/home.png" width="820" alt="Potret — pick a capture mode from the menu-bar app" />
</div>

<!--
  More shots to add (capture them with Potret itself) — drop into docs/ and uncomment:
<div align="center">
  <img src="docs/quick-access.png" width="640" alt="Quick Access popup" /><br/>
  <img src="docs/annotate.png" width="640" alt="Annotation editor" /><br/>
  <img src="docs/background.png" width="640" alt="Background tool" />
</div>
-->

## Features

- **Capture** — area (drag to select), window (click any window), or fullscreen
- **Quick Access popup** — copy, save, annotate, pin, or drag the capture straight into another app; follows you across Spaces/desktops
- **Annotation** — pen, line, arrow, rectangle, ellipse, text, highlighter, pixelate/blur, numbered steps, crop, eraser — with undo/redo and a custom color picker
- **Background tool** — drop a screenshot onto gradient or custom backgrounds with padding, rounded corners, and shadow (great for social posts)
- **Pin to screen** — keep a floating screenshot on top while you work
- **History** — recent captures with copy / edit / pin / delete, plus a **Recent Captures** menu-bar popup (⌘⇧H) to browse them without opening the app
- **Output options** — PNG or JPG, adjustable quality, and filename templates
- **System** — customizable global shortcuts, menu-bar only, launch at login, and fluid animations (respects Reduce Motion)

## Tech stack

- [Tauri 2](https://tauri.app) — Rust backend, tiny native binary
- React 19 + TypeScript — UI
- Tailwind CSS v4 — styling
- macOS `screencapture` — native capture engine

## Getting started

### Prerequisites

- macOS
- [Rust](https://rustup.rs)
- Node.js 18+

### Development

```bash
npm install
npm run tauri dev
```

### Build a release (.dmg)

Releases are universal (Intel + Apple Silicon), signed, and packaged with one command:

```bash
rustup target add x86_64-apple-darwin   # one-time
./scripts/release.sh                     # → dist-dmg/Potret_<version>_universal.dmg
```

(Plain `npm run tauri build` leaves the universal binary with a broken signature — see
[CONTRIBUTING.md](CONTRIBUTING.md) for why the script handles signing/packaging instead.)

### Permissions

Potret needs **Screen Recording** permission. On first run, grant it in
**System Settings → Privacy & Security → Screen Recording**, then restart the app.

## Project layout

```
src/                  React frontend (capture UI, annotation, popup, settings)
src-tauri/            Rust backend (capture commands, windows, history, config)
src-tauri/src/lib.rs  main Rust entry — capture pipeline + Tauri commands
```

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for dev setup and the
release process. For anything substantial, please open an issue first to discuss the approach;
bug reports and small fixes can go straight to a PR.

## Status

Early but usable (v0.1), macOS only. Expect some rough edges — issues and PRs appreciated.

## License

[MIT](LICENSE)
