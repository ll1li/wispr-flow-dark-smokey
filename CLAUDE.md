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
- GitHub repo: `ll1li/wispr-flow-dark-smokey`

## Project Layout
- `wispr-flow-dark-smokey` — the script (v1.3.0). Injects `<style>` before `</head>`, idempotent.
- `screenshot.jpg` — hero image for README
- Single-file project. No tests, no CI — manual verification only.

## Commands
```bash
wispr-flow-dark-smokey            # Apply dark theme
wispr-flow-dark-smokey --restore  # Restore original
wispr-flow-dark-smokey --check    # Check if applied
wispr-flow-dark-smokey --version  # Print version
```

## Key Patterns
- Always extract from `app.asar.bak` (clean backup), never from a previously patched asar
- Backup must include `app.asar.unpacked/` dir (native binaries like Jabra connectors)
- Atomic write: `mktemp` on same filesystem → `cp` → `mv`
- TMPFILE tracked in cleanup trap — removed on failure, cleared after successful mv
- APP_WAS_RUNNING flag — restarts app even on script failure
- Post-inject verification — `grep -q "$MARKER"` after sed, fail loudly if missing
- Idempotent strip-and-repatch — strips old `<style>` before injecting new CSS
- Status bar renderer gets different CSS (no invert — natively dark/transparent)
- `meeting_recorder` renderer exists but intentionally not patched (transient window)

## CSS Strategy
- `filter: invert(.85) hue-rotate(180deg) sepia(.30) brightness(.95)` on `html`
- `body` also gets background to prevent white flash during paint
- CSS variable overrides: all `--sand-*`, `--vast-*`, `--neutral-10` forced to `#fff`
- Form elements (`input/textarea/select/button/[role=combobox]`) forced white
- Modal overlays targeted by CSS Module hashed class names (see Overlay Hashes)
- Images/video/canvas counter-inverted: `filter: invert(1) hue-rotate(180deg)`
- `-webkit-font-smoothing: antialiased` prevents text bloom
- Selection color: warm amber `rgba(180,140,100,.35)` matching smoky aesthetic
- Focus: `rgba(100,149,237,.9)` for WCAG AA compliance
- Scrollbar: 6px width, hover + active states

## Overlay Hashes (Wispr Flow 1.4.x)
These CSS Module hashes break on app updates. To find new ones:
```bash
grep -r "position:fixed;inset:0;background-color:rgba" .webpack/renderer/
```
- `.mgB3HwW13t29DKsEkfUD` — modal overlay (z-700)
- `.Lo3Dvv9YLP6w7ogTpGvR` — dialog overlay (z-800)
- `.h4ZXMTnO1FZBj82_Jjao` — hold-hotkey overlay (z-9999)

## Dependencies
- `@electron/asar@4.2.0` (pinned, not the deprecated `asar` package)
- Node.js (any version with npx)
- macOS (Wispr Flow target platform)

## Process Management
- Use `pgrep -f` (not `-x`) to catch all Electron helper processes (GPU, Renderer, Plugin)
- `killall 'Wispr Flow'` sends SIGTERM cascading to all children

## macOS Security
- Replacing `app.asar` invalidates codesign sealed resources — expected and safe
- Gatekeeper does not re-check previously approved apps
- No ASAR integrity checking in current Wispr Flow (no `ElectronAsarIntegrity` in Info.plist)
- If future Wispr Flow adds integrity checking, patch will fail at startup — check Info.plist

## Testing
- Manual only: run `wispr-flow-dark-smokey`, visually verify in Wispr Flow
- Test `--restore`, `--check` flags
- Check modals/dialogs/popups have dark overlay (not bleached white wash)
- Verify media (images/video) render correctly (counter-invert)
- After Wispr Flow updates: check renderer paths, find new overlay hashes

## Gotchas
- Wispr Flow auto-updates overwrite the patch silently — re-run after updates
- Stale `.bak` without matching `.bak.unpacked/` dir will crash `asar extract`
- sed strip pattern uses `.*` — CSS must not span multiple lines
- The `--restore` flow does atomic swap of `.unpacked` dir to prevent data loss
