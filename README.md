<h1 align="center">
  Wispr Flow Dark-Smokey
</h1>

<h4 align="center">A one-command dark theme for <a href="https://wispr.com/" target="_blank">Wispr Flow</a> on macOS — warm, smoky, with a subtle drifting gradient.</h4>

<p align="center">
  <a href="https://github.com/ll1li/wispr-flow-dark-smokey/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/ll1li/wispr-flow-dark-smokey?style=flat-square" alt="License">
  </a>
  <img src="https://img.shields.io/badge/version-1.3.0-blue?style=flat-square" alt="Version">
  <img src="https://img.shields.io/badge/platform-macOS-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/requires-Node.js-green?style=flat-square" alt="Requires Node.js">
</p>

<p align="center">
  <a href="#install">Install</a> •
  <a href="#usage">Usage</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#compatibility">Compatibility</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="screenshot.jpg" alt="Wispr Flow Dark-Smokey" width="760">
</p>

---

Wispr Flow ships with a hardcoded white UI and no dark mode. This script patches the Electron `app.asar` bundle to inject a carefully tuned dark theme — warm but not yellow, dark but not clinical, with a slow-drifting radial gradient that gives the background a subtle smoky presence.

## Features

| | |
|---|---|
| **Warm smoky tone** | Soft sepia + counter-inverted whites — no harsh pure black |
| **Dynamic background** | Slow-drifting radial gradients (90s cycle) add depth without distraction |
| **Uniform dark surfaces** | Overrides internal CSS variables so sidebar, content, and modals all match |
| **Natural media** | Images and video are counter-inverted so they render correctly |
| **Atomic write** | Patches via temp file + `mv` — never leaves a corrupt bundle |
| **Idempotent** | Strips prior patches before injecting, safe to re-run any time |
| **One-command restore** | `--restore` reverts to the original in seconds |

## Install

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/ll1li/wispr-flow-dark-smokey/main/wispr-flow-dark-smokey \
  -o ~/.local/bin/wispr-flow-dark-smokey && chmod +x ~/.local/bin/wispr-flow-dark-smokey
```

> Make sure `~/.local/bin` is in your `PATH` (`export PATH="$HOME/.local/bin:$PATH"`).

## Usage

```bash
wispr-flow-dark-smokey            # Apply dark theme (auto-restarts Wispr Flow)
wispr-flow-dark-smokey --restore  # Revert to the original
wispr-flow-dark-smokey --check    # Is the theme currently applied?
wispr-flow-dark-smokey --version  # Print version
```

> **Note:** Wispr Flow auto-updates overwrite the patch. Just re-run `wispr-flow-dark-smokey` after any update.

## How It Works

The script extracts Wispr Flow's Electron bundle, injects a `<style>` block before `</head>` in the renderer HTML, and repacks it atomically. A clean backup is saved on first run.

| Layer | What it does |
|-------|-------------|
| `filter: invert(.89) hue-rotate(180deg)` | Flips the entire UI to dark while preserving hue relationships |
| `sepia(.13) brightness(1.0)` | Warm amber cast, no overexposure |
| `body::before` radial gradients | Slow-drifting smoke layer (90s cycle, GPU-friendly) |
| `--sand-*`, `--vast-*`, `--neutral-*` overrides | Equalises internal CSS variables so every surface inverts to the same shade |
| Counter-invert on `img, video, canvas` | Keeps media looking natural |
| Status bar CSS | Separate, invert-free — bar is natively transparent |

### Safety

- **Atomic writes** — patched bundle is written to a temp file on the same filesystem, then `mv`'d into place
- **Graceful process handling** — `pgrep -f` catches all Electron helpers (GPU, Renderer, Plugin), restart on failure via cleanup trap
- **Post-inject verification** — script fails loudly if CSS didn't land
- **Pinned asar version** — `@electron/asar@4.2.0`, no supply-chain surprises

## Compatibility

| Wispr Flow | Dark-Smokey | Status |
|------------|-------------|--------|
| 1.4.x      | v1.3.0      | Tested |
| 1.3.x      | v1.3.0      | Tested |

If Wispr Flow restructures its renderer after an update, the script detects the change and exits with an error instead of silently failing.

## Requirements

- macOS
- [Wispr Flow](https://wispr.com/) installed in `/Applications/`
- [Node.js](https://nodejs.org/) (uses `npx` to run `@electron/asar`)
- Internet connection (first run only, to download `asar`)

## Disclaimer

This is an unofficial community project. It only modifies CSS styling in the renderer HTML — no proprietary code is extracted, reverse-engineered, or redistributed. A backup of the original bundle is created automatically and can be restored at any time with `--restore`.

Replacing `app.asar` invalidates the bundle's codesign seal, which is expected and safe for locally installed apps. Wispr Flow does not currently enforce ASAR integrity verification; if it adds one in a future release, this script will fail at startup rather than corrupt the app.

## License

[MIT](LICENSE)
