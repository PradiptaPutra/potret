# Potret

A free, open source screenshot and annotation tool for macOS — built with Tauri + React.

Inspired by CleanShot X, without the price tag.

## Features

- **Area capture** — drag to select any region
- **Window capture** — click any open window
- **Fullscreen capture** — grab the entire display
- **Annotation tools** — pen, line, arrow, rectangle, ellipse, text, eraser
- **Color picker** — 9 preset colors
- **Copy to clipboard** — paste anywhere instantly
- **Save as PNG** — choose your own path

## Stack

- [Tauri 2](https://tauri.app) — Rust backend, tiny binary
- React + TypeScript — UI
- Tailwind CSS — styling
- macOS `screencapture` — native screenshot engine

## Getting Started

### Prerequisites

- [Rust](https://rustup.rs)
- Node.js 18+

### Development

```bash
npm install
npm run tauri dev
```

### Build

```bash
npm run tauri build
```

## Contributing

PRs welcome. Open an issue first for large changes.

## License

MIT
