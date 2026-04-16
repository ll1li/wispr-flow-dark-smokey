# Wispr Flow Dark-Smokey

## What This Is
Bash script that injects dark CSS into Wispr Flow's Electron `app.asar` bundle.
No build system, no dependencies beyond Node.js (`npx asar`).

## Naming
- Display name: "Wispr Flow Dark-Smokey"
- Code/path name: `wispr-flow-dark-smokey`
- Script file: `wispr-flow-dark-smokey`
- CLI command: `wispr-flow-dark-smokey`
- CSS marker: `data-wispr-dark-smokey`

## Project Layout
- `wispr-flow-dark-smokey` — the script (v1.2.0). Injects `<style>` before `</head>`, non-destructive.
- `screenshot.jpg` — before/after for README
- Single-file project. No tests, no CI — manual verification only.

## Key Patterns
- Always extract from `app.asar.bak` (clean backup), never from a previously patched asar
- Backup must include `app.asar.unpacked/` dir (native binaries like Jabra connectors live there)
- Atomic write: pack to temp file on same filesystem, then `mv` into place
- Status bar renderer gets different CSS (no invert — it's natively dark/transparent)
- Marker attribute `data-wispr-dark-smokey` prevents double-patching
- `@electron/asar@3.2.10` pinned for supply-chain safety
- Renderers: `hub`, `scratchpad`, `contextMenu`, `status` at `.webpack/renderer/*/index.html`

## CSS Strategy
- Global `invert(.88) hue-rotate(180deg) sepia(.15)` on `html` — flips the entire UI
- CSS variable overrides (`--sand-*`, `--vast-*`) force uniform backgrounds
- Dialogs/modals get explicit `background:#fff` so they invert to dark (not light gray)
- Images/video/canvas get counter-inverted to render naturally
- `-webkit-font-smoothing: antialiased` prevents text bloom on dark backgrounds

## Testing
- Manual only: run `wispr-flow-dark-smokey`, visually verify in Wispr Flow
- Test `--restore`, `--check` flags
- Check modals/dialogs/popups are dark (not white)
- Verify media (images/video) render correctly (counter-invert)
- After Wispr Flow updates, check renderer paths still exist

## Gotchas
- Wispr Flow auto-updates overwrite the patch silently — re-run after updates
- `killall 'Wispr Flow'` needed before touching `app.asar` (file is locked while running)
- The cleanup trap handles restart automatically on successful patch
- Stale `.bak` without matching `.bak.unpacked/` dir will crash `asar extract`
