#!/usr/bin/env pwsh
# wispr-flow-dark-smokey (Windows port) — dark theme for Wispr Flow on Windows.
# Mirrors the macOS bash script: backup app.asar, extract, inject CSS, atomic repack.
[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Restore')][switch]$Restore,
    [Parameter(ParameterSetName = 'Check')]  [switch]$Check,
    [Parameter(ParameterSetName = 'Version')][switch]$Version,
    [Parameter(ParameterSetName = 'Help')]   [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$ScriptVersion = '1.4.0'
$Marker        = 'data-wispr-dark-smokey'
$AsarCmd       = '@electron/asar@4.2.0'

function Show-Usage {
    @"
wispr-flow-dark-smokey $ScriptVersion — dark theme for Wispr Flow (Windows)

Usage: .\wispr-flow-dark-smokey.ps1 [-Restore|-Check|-Version|-Help]

  (no flags)   Apply dark theme
  -Restore     Restore original Wispr Flow
  -Check       Check if theme is currently applied
  -Version     Print version
  -Help        Show this help

Set `$env:WISPR_PATH to override the default install location (full path to app.asar).
"@ | Write-Host
    exit 0
}

if ($Help)    { Show-Usage }
if ($Version) { Write-Host "wispr-flow-dark-smokey $ScriptVersion"; exit 0 }

function Find-WisprAsar {
    if ($env:WISPR_PATH) {
        if (Test-Path -LiteralPath $env:WISPR_PATH) { return $env:WISPR_PATH }
        Write-Host "WISPR_PATH set but not found: $env:WISPR_PATH" -ForegroundColor Red
        exit 1
    }

    # Microsoft Store install — refuse with redirect to .exe download.
    # The MS Store install lives in C:\Program Files\WindowsApps\, owned by
    # TrustedInstaller, and modifying it breaks the UWP signature so the app
    # won't launch. The .exe and .msi from wisprflow.ai don't have this issue.
    $appx = $null
    try { $appx = Get-AppxPackage -Name '*WisprFlow*' -ErrorAction SilentlyContinue } catch {}
    if ($appx) {
        Write-Host ""
        Write-Host "Microsoft Store install of Wispr Flow detected." -ForegroundColor Red
        Write-Host ""
        Write-Host "MS Store apps live in C:\Program Files\WindowsApps\, which is locked by"
        Write-Host "TrustedInstaller. Patching app.asar there is blocked, and even if it weren't,"
        Write-Host "modification breaks the UWP signature so the app refuses to launch."
        Write-Host ""
        Write-Host "Fix:"
        Write-Host "  1. Uninstall the Microsoft Store version of Wispr Flow"
        Write-Host "  2. Download the .exe installer from https://wisprflow.ai/get-started"
        Write-Host "  3. Re-run this script"
        Write-Host ""
        exit 2
    }

    # MSI / enterprise install
    $msiPath = Join-Path $env:ProgramFiles 'Wispr Flow\resources\app.asar'
    if (Test-Path -LiteralPath $msiPath) { return $msiPath }

    # Squirrel per-user install — pick newest app-{version} dir (Squirrel rotates these on every update)
    $squirrelRoot = Join-Path $env:LOCALAPPDATA 'WisprFlow'
    if (Test-Path -LiteralPath $squirrelRoot) {
        $latest = Get-ChildItem -Path $squirrelRoot -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) {
            $candidate = Join-Path $latest.FullName 'resources\app.asar'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }

    Write-Host "Wispr Flow not found. Install from https://wisprflow.ai/get-started, or set `$env:WISPR_PATH." -ForegroundColor Red
    exit 1
}

$Asar           = Find-WisprAsar
$Unpacked       = "$Asar.unpacked"
$Backup         = "$Asar.bak"
$BackupUnpacked = "$Backup.unpacked"

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Host "Node.js required (npx not found). Install from https://nodejs.org" -ForegroundColor Red
    exit 1
}

# Capture exe path BEFORE killing — needed by cleanup to restart the app
$RunningProcs  = @(Get-Process -Name 'Wispr Flow' -ErrorAction SilentlyContinue)
$AppWasRunning = $RunningProcs.Count -gt 0
$ExePath       = $null
if ($AppWasRunning) {
    $ExePath = ($RunningProcs | Where-Object { $_.Path } | Select-Object -First 1).Path
}
if (-not $ExePath) {
    # Infer: ...\app-{ver}\resources\app.asar  →  ...\app-{ver}\Wispr Flow.exe
    $candidate = Join-Path (Split-Path (Split-Path $Asar -Parent) -Parent) 'Wispr Flow.exe'
    if (Test-Path -LiteralPath $candidate) { $ExePath = $candidate }
}

$WorkDir     = Join-Path ([System.IO.Path]::GetTempPath()) ("wispr-skin-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$AsarWritten = $false
$TmpFile     = $null

function Stop-WisprFlow {
    Get-Process -Name 'Wispr Flow' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 10; $i++) {
        if (-not (Get-Process -Name 'Wispr Flow' -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 500
    }
}

function Invoke-Cleanup {
    if (Test-Path -LiteralPath $WorkDir) { Remove-Item -Recurse -Force -LiteralPath $WorkDir -ErrorAction SilentlyContinue }
    if ($script:TmpFile -and (Test-Path -LiteralPath $script:TmpFile)) {
        Remove-Item -Force -LiteralPath $script:TmpFile -ErrorAction SilentlyContinue
    }
    if ($script:AsarWritten -or ($AppWasRunning -and -not $Check)) {
        Stop-WisprFlow
        if ($ExePath -and (Test-Path -LiteralPath $ExePath)) {
            Start-Process -FilePath $ExePath -ErrorAction SilentlyContinue
        }
    }
}

function Set-RendererHtml {
    param([string]$Path, [string]$Css, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Error: $Name not found at $Path — Wispr Flow may have updated its structure." -ForegroundColor Red
        exit 1
    }
    $html = Get-Content -Raw -LiteralPath $Path
    if ($html -match [regex]::Escape($Marker)) {
        Write-Host "==> Stripping old patch from $Name..."
        $stripPattern = '(?s)<style\s+' + [regex]::Escape($Marker) + '>.*?</style>'
        $html = [regex]::Replace($html, $stripPattern, '')
    }
    Write-Host "==> Patching $Name..."
    if ($html -notmatch '</head>') {
        Write-Host "Error: </head> not found in $Path" -ForegroundColor Red
        exit 1
    }
    # Plain string Replace — avoids -replace's regex/$-substitution semantics on the CSS payload
    $html = $html.Replace('</head>', $Css + '</head>')
    # Write UTF-8 without BOM to match Electron's webpack output
    [System.IO.File]::WriteAllText($Path, $html, (New-Object System.Text.UTF8Encoding $false))
    if ((Get-Content -Raw -LiteralPath $Path) -notmatch [regex]::Escape($Marker)) {
        Write-Host "Error: failed to inject CSS into $Name — marker missing after write." -ForegroundColor Red
        exit 1
    }
}

try {
    # --check
    if ($Check) {
        & npx --yes $AsarCmd extract $Asar (Join-Path $WorkDir 'wispr') *> $null
        $hub = Join-Path $WorkDir 'wispr\.webpack\renderer\hub\index.html'
        if ((Test-Path -LiteralPath $hub) -and (Select-String -Path $hub -Pattern $Marker -Quiet)) {
            Write-Host "Dark Smokey is applied."
        } else {
            Write-Host "Dark Smokey is not applied."
        }
        exit 0
    }

    # Kill before any file ops
    if ($AppWasRunning) { Stop-WisprFlow }

    # --restore
    if ($Restore) {
        if (-not (Test-Path -LiteralPath $Backup)) {
            Write-Host "No backup found at $Backup." -ForegroundColor Red
            exit 1
        }
        Move-Item -Force -LiteralPath $Backup -Destination $Asar
        if (Test-Path -LiteralPath $BackupUnpacked) {
            $UnpackedTmp = "$Unpacked.restoring.$PID"
            if (Test-Path -LiteralPath $Unpacked) {
                Move-Item -Force -LiteralPath $Unpacked -Destination $UnpackedTmp -ErrorAction SilentlyContinue
            }
            try {
                Move-Item -Force -LiteralPath $BackupUnpacked -Destination $Unpacked
                if (Test-Path -LiteralPath $UnpackedTmp) {
                    Remove-Item -Recurse -Force -LiteralPath $UnpackedTmp -ErrorAction SilentlyContinue
                }
            } catch {
                if (Test-Path -LiteralPath $UnpackedTmp) {
                    Move-Item -Force -LiteralPath $UnpackedTmp -Destination $Unpacked -ErrorAction SilentlyContinue
                }
                Write-Host "Error: failed to restore $Unpacked — original left intact." -ForegroundColor Red
                exit 1
            }
        }
        $AsarWritten = $true
        Write-Host "Restored. Wispr Flow will restart."
        exit 0
    }

    # First-run backup — must include .unpacked dir for native binaries
    if (-not (Test-Path -LiteralPath $Backup)) {
        Copy-Item -LiteralPath $Asar -Destination $Backup
        if (Test-Path -LiteralPath $Unpacked) {
            Copy-Item -LiteralPath $Unpacked -Destination $BackupUnpacked -Recurse
        }
    }

    # Always extract from clean backup
    Write-Host "==> Extracting..."
    & npx --yes $AsarCmd extract $Backup (Join-Path $WorkDir 'wispr')
    if ($LASTEXITCODE -ne 0) { Write-Host "asar extract failed." -ForegroundColor Red; exit 1 }

    # Theme CSS — same skin as macOS for v1.4.0; can diverge per-platform later.
    # See macOS script for the full design rationale of the invert/hue-rotate/brightness stack.
    $DarkCss = '<style data-wispr-dark-smokey>html{background:#15131a!important;filter:invert(.91) hue-rotate(180deg) brightness(.93)!important;-webkit-font-smoothing:antialiased!important}body{background:#15131a!important}img,video,canvas,svg image,picture>img{filter:invert(1) hue-rotate(180deg)!important}:root{--sand-50:#fff!important;--sand-100:#fefefe!important;--sand-200:#fdfdfc!important;--sand-300:#fcfcfb!important;--sand-400:#fbfbfa!important;--sand-500:#fafaf9!important;--vast-50:#fefefe!important;--vast-100:#fdfdfc!important;--neutral-10:#fff!important}*:focus-visible{outline:2px solid rgba(100,149,237,.6)!important;outline-offset:2px!important}::-webkit-scrollbar{width:5px;height:5px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:rgba(128,128,128,.22);border-radius:3px}::-webkit-scrollbar-thumb:hover{background:rgba(128,128,128,.5)}::-webkit-scrollbar-thumb:active{background:rgba(128,128,128,.7)}::selection{background:rgba(120,130,170,.35)!important;color:inherit!important}</style>'

    $StatusCss = '<style data-wispr-dark-smokey>html,body{background:transparent!important}*{border-color:transparent!important;box-shadow:none!important}</style>'

    foreach ($renderer in 'hub','scratchpad','contextMenu') {
        $target = Join-Path $WorkDir "wispr\.webpack\renderer\$renderer\index.html"
        Set-RendererHtml -Path $target -Css $DarkCss -Name $renderer
    }

    # Status bar — different CSS, optional renderer
    $statusTarget = Join-Path $WorkDir 'wispr\.webpack\renderer\status\index.html'
    if (Test-Path -LiteralPath $statusTarget) {
        Set-RendererHtml -Path $statusTarget -Css $StatusCss -Name 'status'
    }

    # Repack to temp on the same volume, then atomic Move-Item
    Write-Host "==> Repacking..."
    $patched = Join-Path $WorkDir 'patched.asar'
    & npx --yes $AsarCmd pack (Join-Path $WorkDir 'wispr') $patched
    if ($LASTEXITCODE -ne 0) { Write-Host "asar pack failed." -ForegroundColor Red; exit 1 }

    $TmpFile = Join-Path (Split-Path $Asar -Parent) (".app.asar.tmp." + [guid]::NewGuid().ToString('N').Substring(0,10))
    Copy-Item -LiteralPath $patched -Destination $TmpFile -Force
    Move-Item -Force -LiteralPath $TmpFile -Destination $Asar
    $TmpFile     = $null
    $AsarWritten = $true

    Write-Host "Done. Wispr Flow Dark-Smokey applied."
}
finally {
    Invoke-Cleanup
}
