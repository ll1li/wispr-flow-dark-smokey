<h1 align="center">
  Wispr Flow Dark Smokey
</h1>

<h4 align="center">A one-command dark theme for <a href="https://wispr.com/" target="_blank">Wispr Flow</a> on macOS.</h4>

<p align="center">
  <a href="https://github.com/ll1li/wispr-flow-dark-smokey/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/ll1li/wispr-flow-dark-smokey?style=flat-square" alt="License">
  </a>
  <a href="https://github.com/ll1li/wispr-flow-dark-smokey/releases">
    <img src="https://img.shields.io/github/v/release/ll1li/wispr-flow-dark-smokey?style=flat-square&label=version" alt="Version">
  </a>
  <img src="https://img.shields.io/badge/platform-macOS-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/requires-Node.js-green?style=flat-square" alt="Requires Node.js">
</p>

<p align="center">
  <a href="#install">Install</a> •
  <a href="#usage">Usage</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="screenshot.png" alt="Wispr Flow Dark Smokey" width="700">
</p>

---

Wispr Flow ships with a hardcoded white UI and no dark mode option. This script patches the Electron app bundle to inject a carefully tuned dark theme with warm smoky tones, uniform backgrounds, and clean outlines.

## Features

- **Uniform dark background** -- overrides internal CSS variables to eliminate sidebar/content color mismatch
- **Warm smoky tone** -- subtle sepia filter avoids the clinical white-on-black look
- **Dimmed text** -- comfortable reading without harsh contrast
- **Clean outlines** -- thin borders on interactive elements for visual structure
- **Natural media** -- images and video are counter-inverted so they render correctly
- **Safe** -- creates a backup on first run, one-command restore at any time

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/ll1li/wispr-flow-dark-smokey/main/wispr-dark-mode \
  -o ~/.local/bin/wispr-dark-mode && chmod +x ~/.local/bin/wispr-dark-mode
```

> Make sure `~/.local/bin` is in your `PATH`. Alternatively, use `/usr/local/bin/` (may require `sudo`).

## Usage

```bash
# Apply dark mode (auto-restarts Wispr Flow)
wispr-dark-mode

# Restore original
wispr-dark-mode --restore
```

Re-run after Wispr Flow updates -- the update will overwrite the patch.

## How It Works

The script extracts Wispr Flow's Electron `app.asar` bundle, patches the hub and scratchpad renderer HTML with CSS overrides, and repacks it. A backup is saved as `app.asar.bak` on first run.

| Layer | What it does |
|-------|-------------|
| `filter: invert(0.94) hue-rotate(180deg)` | Flips the UI to dark while preserving color relationships |
| `--sand-*`, `--vast-*`, `--neutral-*` overrides | Forces all background shades to the same value |
| `sepia(0.08)` + `opacity: 0.92` | Adds warmth and dims harsh whites |
| Counter-invert on `img, video, canvas` | Keeps media looking natural |

## Requirements

- macOS
- [Wispr Flow](https://wispr.com/) in `/Applications/`
- [Node.js](https://nodejs.org/) (uses `npx asar` to unpack/repack the bundle)

## License

[MIT](LICENSE)
