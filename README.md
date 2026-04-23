<h1 align="center">
  Wispr Flow Dark-Smokey
</h1>

<h4 align="center">A one-command dark theme for <a href="https://wispr.com/" target="_blank">Wispr Flow</a> on macOS — clean, neutral dark, no eye strain.</h4>

<p align="center">
  <a href="https://github.com/ll1li/wispr-flow-dark-smokey/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/ll1li/wispr-flow-dark-smokey?style=flat-square" alt="License">
  </a>
  <img src="https://img.shields.io/badge/version-1.3.3-blue?style=flat-square" alt="Version">
  <img src="https://img.shields.io/badge/platform-macOS-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/requires-Node.js-green?style=flat-square" alt="Requires Node.js">
</p>

<p align="center">
  <a href="#why">Why</a> •
  <a href="#install">Install</a> •
  <a href="#usage">Usage</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#compatibility">Compatibility</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="banner.png" alt="Wispr Flow Dark-Smokey" width="860">
</p>

---

## Why

Wispr Flow ships with a hardcoded white UI and no dark mode option. Late-night dictation sessions mean staring directly into a full-brightness white window. This script patches Wispr Flow's Electron `app.asar` bundle to inject a neutral dark theme — deep without being clinical, zero GPU overhead, one command to apply or undo.

## Features

| | |
|---|---|
| **Neutral dark tone** | `invert(.91) hue-rotate(180deg) brightness(.93)` — deep dark without a colour cast |
| **Zero GPU overhead** | No animated overlays or background keyframes — static CSS only |
| **Uniform dark surfaces** | Overrides internal CSS variables so sidebar, content, and modals all match |
| **Natural media** | Images, video, and canvas are counter-inverted so they render correctly |
| **Atomic write** | Patches via temp file + `mv` — never leaves a corrupt bundle |
| **Idempotent** | Strips prior patches before injecting, safe to re-run at any time |
| **One-command restore** | `--restore` reverts to the original in seconds |

## Install

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/ll1li/wispr-flow-dark-smokey/main/wispr-flow-dark-smokey \
  -o ~/.local/bin/wispr-flow-dark-smokey && chmod +x ~/.local/bin/wispr-flow-dark-smokey
```

Make sure `~/.local/bin` is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add that line to your `~/.zshrc` or `~/.bash_profile` to make it permanent.

## Usage

```bash
wispr-flow-dark-smokey            # Apply dark theme (auto-restarts Wispr Flow)
wispr-flow-dark-smokey --restore  # Revert to the original
wispr-flow-dark-smokey --check    # Check whether the theme is currently applied
wispr-flow-dark-smokey --version  # Print version
wispr-flow-dark-smokey --help     # Show all options
```

**Custom install path:** Set `WISPR_PATH` to override the default `/Applications/Wispr Flow.app` location:

```bash
WISPR_PATH="/path/to/Wispr Flow.app" wispr-flow-dark-smokey
```

> Wispr Flow auto-updates silently overwrite the patch. Just re-run `wispr-flow-dark-smokey` after any app update.

## How It Works

The script extracts Wispr Flow's Electron bundle from a clean backup, injects a `<style>` block before `</head>` in each renderer's HTML, and repacks atomically. The first run saves a backup; all subsequent runs always extract from that clean backup, never from a previously patched file.

| Layer | What it does |
|-------|-------------|
| `filter: invert(.91) hue-rotate(180deg) brightness(.93)` on `html` | Flips the entire UI to dark while restoring hue relationships; `brightness(.93)` keeps it dark without overexposure |
| Background `#15131a` on `html` and `body` | Neutral dark with a faint cool tint — prevents white flash during paint |
| `--sand-*`, `--vast-*`, `--neutral-10` overrides | Equalises Wispr Flow's internal CSS variables so every surface inverts to the same depth |
| Counter-invert on `img, video, canvas` | Keeps media colours natural after the parent `html` inversion |
| Status bar CSS | Separate, invert-free stylesheet — the bar is natively dark and transparent |
| Scrollbar | 5 px, hover and active states, transparent track |

Four renderers are patched: `hub`, `scratchpad`, `contextMenu`, and `status`. The `meeting_recorder` renderer is intentionally left unpatched (transient window).

### Safety

- **Atomic writes** — patched bundle is written to a temp file on the same filesystem, then `mv`'d into place; a partial write can never corrupt the live bundle
- **Backup integrity** — backup includes the `app.asar.unpacked/` directory so native binaries (e.g. Jabra connectors) are preserved
- **Graceful process handling** — Wispr Flow is killed before any file is touched and restarted via the `EXIT` trap whether the script succeeds or fails
- **Post-inject verification** — the script checks for the CSS marker after injection and exits loudly if it is missing
- **Pinned asar version** — `@electron/asar@4.2.0`; no floating dependency, no supply-chain surprises

<details>
<summary>Overlay hashes and macOS security notes</summary>

### Overlay hashes (Wispr Flow 1.4.x)

Wispr Flow uses CSS Modules, so modal overlay selectors carry hashed class names. These hashes change when Wispr Flow updates its bundler output. If modals appear as a bright white wash after an app update, find the new hashes by extracting the asar and running:

```bash
grep -r "position:fixed;inset:0;background-color:rgba" .webpack/renderer/
```

Current hashes (1.4.x):

| Class | Role |
|-------|------|
| `.mgB3HwW13t29DKsEkfUD` | Modal overlay (z-index 700) |
| `.Lo3Dvv9YLP6w7ogTpGvR` | Dialog overlay (z-index 800) |
| `.h4ZXMTnO1FZBj82_Jjao` | Hold-hotkey overlay (z-index 9999) |

Update those three selectors in the script and re-run after each Wispr Flow release that changes them.

### macOS security

Replacing `app.asar` invalidates the bundle's codesign seal. This is expected: Gatekeeper does not re-check previously approved apps, and Wispr Flow currently has no `ElectronAsarIntegrity` key in its `Info.plist`. If a future Wispr Flow release enables ASAR integrity verification, this script will fail at Wispr Flow startup rather than silently corrupt the app — check `Info.plist` after major updates.

</details>

## Compatibility

| Wispr Flow | Dark-Smokey | Status |
|------------|-------------|--------|
| 1.4.x      | v1.3.3      | Tested |
| 1.3.x      | v1.3.3      | Tested |

If Wispr Flow restructures its renderer paths after an update, the script detects the missing file and exits with an error instead of silently failing.

## Requirements

- macOS
- [Wispr Flow](https://wispr.com/) installed in `/Applications/` (or set `WISPR_PATH`)
- [Node.js](https://nodejs.org/) (any version that includes `npx`)

## Disclaimer

Unofficial community project. Only CSS styling in renderer HTML is modified — no proprietary code is extracted, reverse-engineered, or redistributed. The original bundle is backed up automatically and restored with `--restore`.

## License

[MIT](LICENSE)
