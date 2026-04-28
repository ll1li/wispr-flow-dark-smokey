# Wispr Flow Dark-Smokey

## What This Is
Bash + PowerShell scripts that inject dark CSS into Wispr Flow's Electron `app.asar` bundle.
No build system, no dependencies beyond Node.js (`npx @electron/asar`).

## Naming
- Display name: "Wispr Flow Dark-Smokey"
- Code/path name: `wispr-flow-dark-smokey`
- Script files: `wispr-flow-dark-smokey` (macOS bash) and `wispr-flow-dark-smokey.ps1` (Windows PowerShell)
- CLI command: `wispr-flow-dark-smokey` (macOS) / `.\wispr-flow-dark-smokey.ps1` (Windows)
- CSS marker: `data-wispr-dark-smokey`
- GitHub repo: `ll1li/wispr-flow-dark-smokey`

## Project Layout
- `wispr-flow-dark-smokey` — macOS bash script (v1.4.0). Injects `<style>` before `</head>`, idempotent.
- `wispr-flow-dark-smokey.ps1` — Windows PowerShell port (v1.4.0). Same structure, auto-discovers Squirrel/MSI installs, refuses MS Store.
- `banner.png` — hero image for README (replaced `screenshot.jpg` in v1.3.3)
- Two-file project (one per platform). No tests, no CI — manual verification only.
- Both scripts share the same CSS by convention but are not auto-synced — they may diverge intentionally per-platform.

## Commands
```bash
# macOS
wispr-flow-dark-smokey            # Apply dark theme
wispr-flow-dark-smokey --restore  # Restore original
wispr-flow-dark-smokey --check    # Check if applied
wispr-flow-dark-smokey --version  # Print version
```
```powershell
# Windows
.\wispr-flow-dark-smokey.ps1           # Apply
.\wispr-flow-dark-smokey.ps1 -Restore  # Restore
.\wispr-flow-dark-smokey.ps1 -Check    # Check
.\wispr-flow-dark-smokey.ps1 -Version  # Version
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
- `filter: invert(.91) hue-rotate(180deg) brightness(.93)` on `html` — no sepia (neutral)
- Background `#15131a` on both `html` and `body` — faint cool tint, no brown
- No animated overlay (removed in v1.3.3 — was constant GPU cost for subtle effect)
- CSS variable overrides: all `--sand-*`, `--vast-*`, `--neutral-10` forced to `#fff`
- Modal overlays targeted by CSS Module hashed class names (see Overlay Hashes)
- Images/video/canvas counter-inverted: `filter: invert(1) hue-rotate(180deg)`
- `-webkit-font-smoothing: antialiased` prevents text bloom
- Selection color: cool slate `rgba(120,130,170,.35)` matching neutral dark aesthetic
- Focus: `rgba(100,149,237,.6)` outline with 2px offset
- Scrollbar: 5px width, hover + active states

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
- macOS or Windows 10+ (Wispr Flow target platforms)
- Windows: PowerShell 5.1+ (preinstalled) or PowerShell 7+

## Process Management
- macOS: `pgrep -f` (not `-x`) to catch Electron helper processes (GPU, Renderer, Plugin); `killall 'Wispr Flow'` cascades SIGTERM to children
- Windows: `Get-Process -Name 'Wispr Flow'` returns the main process and helpers; `Stop-Process -Force` is the equivalent of SIGKILL. Capture `.Path` BEFORE killing to know what to relaunch.
- Both: poll up to 5s after kill before proceeding to file ops, to avoid file-locking races

## macOS Security
- Replacing `app.asar` invalidates codesign sealed resources — expected and safe
- Gatekeeper does not re-check previously approved apps
- No ASAR integrity checking in current Wispr Flow (no `ElectronAsarIntegrity` in Info.plist)
- If future Wispr Flow adds integrity checking, patch will fail at startup — check Info.plist

## Windows Install Paths
Three Wispr Flow install types on Windows. Script auto-detects in this order:

1. **Microsoft Store** (`Get-AppxPackage *WisprFlow*`) — **refused with redirect**. Lives in `C:\Program Files\WindowsApps\` (TrustedInstaller-locked); modifying breaks UWP signature so app refuses to launch. Script tells user to uninstall and grab the `.exe` from wisprflow.ai.
2. **MSI / enterprise** — `%ProgramFiles%\Wispr Flow\resources\app.asar`. Stable path.
3. **Squirrel `.exe` (default end-user)** — `%LocalAppData%\WisprFlow\app-{version}\resources\app.asar`. **Path drifts on every auto-update** (new `app-{version}` dir each time). Script picks newest by `LastWriteTime`.

Override with `$env:WISPR_PATH` set to the full path of `app.asar`.

## Windows Gotchas
- Squirrel's `app-{version}` folder rotates on every auto-update — patch silently lost, just re-run the script
- `Set-Content -Encoding UTF8` adds a BOM in PowerShell 5.1; use `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)` to write UTF-8 without BOM and match Electron's webpack output
- PowerShell `-replace` operator treats `$` specially in the replacement string; use string `.Replace()` or `[regex]::Replace()` when payload contains `$` chars
- `Move-Item -Force` is atomic on the same volume — use it for the temp-asar swap
- Execution policy: users must `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once before running unsigned local scripts

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
