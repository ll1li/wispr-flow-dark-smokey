#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
  Wispr Flow Dark-Smokey — dark theme patcher for Wispr Flow on Windows.

.DESCRIPTION
  Patches Wispr Flow's Electron app.asar bundle to inject a neutral dark theme.
  Mirrors the macOS bash script feature-for-feature with Windows-native process
  management and Squirrel install-path discovery.

.NOTES
  Set $env:WISPR_PATH to override the default install location
  ($env:LOCALAPPDATA\WisprFlow\app-X.Y.Z\).
#>

$ErrorActionPreference = 'Stop'

$Version = '1.5.0'
$Marker  = 'data-wispr-dark-smokey'
$AsarCmd = '@electron/asar@4.2.0'   # pinned — no supply-chain surprise

# Auto re-apply: a per-user scheduled task that runs `--ensure` one minute after
# logon and every four hours, so a Squirrel auto-update never leaves the app white.
$TaskName = 'WisprFlowDarkSmokey'
$StampDir = Join-Path $env:LOCALAPPDATA 'wispr-flow-dark-smokey'
$Stamp    = Join-Path $StampDir 'ensure-failed'   # asar identity of the last failed --ensure; stops retry loops
$Ensure   = $false

# ----------------------------------------------------------------------------
# Argument parsing — supports both bash-style (--restore) and PowerShell-style
# (-Restore) flags so the .cmd shim and PS-native invocation both work.
# ----------------------------------------------------------------------------

function Show-Usage {
    @"
wispr-flow-dark-smokey $Version - dark theme for Wispr Flow

Usage: wispr-flow-dark-smokey [option]

  (no args)       Apply the dark theme (restarts Wispr Flow)
  --restore       Restore original Wispr Flow
  --check         Check if the theme is applied (exit 0 = applied, 1 = not)
  --ensure        Apply only if not applied; quiet, never restarts a themed app
  --enable-auto   Keep the theme across Wispr Flow updates (scheduled task)
  --disable-auto  Remove the scheduled task
  --uninstall     Restore the app, remove the task and this command
  --version       Print version
  --help          Show this help

Set WISPR_PATH (env var) to override the default install location.
PowerShell-native flags (-Restore, -Check, -Ensure, -EnableAuto, ...) work too.
"@
}

$Action = 'apply'

$argList = @($args)
$i = 0
while ($i -lt $argList.Count) {
    $a = [string]$argList[$i]
    switch -Regex ($a) {
        '^(-h|--help|-\?|/\?|-Help)$'              { Show-Usage; exit 0 }
        '^(--version|-Version|-v)$'                { "wispr-flow-dark-smokey $Version"; exit 0 }
        '^(--restore|-Restore)$'                   { $Action = 'restore'; $i++; continue }
        '^(--check|-Check)$'                       { $Action = 'check';   $i++; continue }
        '^(--ensure|-Ensure)$'                     { $Action = 'apply'; $Ensure = $true; $i++; continue }
        '^(--enable-auto|-EnableAuto)$'            { $Action = 'enable-auto';  $i++; continue }
        '^(--disable-auto|-DisableAuto)$'          { $Action = 'disable-auto'; $i++; continue }
        '^(--uninstall|-Uninstall)$'               { $Action = 'uninstall';    $i++; continue }
        default {
            Write-Host "Error: unknown argument '$a'" -ForegroundColor Red
            Write-Host ''
            Show-Usage
            exit 1
        }
    }
}

# ----------------------------------------------------------------------------
# Path discovery — Squirrel rotates app-X.Y.Z directories on every auto-update,
# so resolve the latest one at runtime instead of caching it. There is a small
# race window: if Wispr Flow auto-updates between our path resolution and the
# atomic mv, we'd patch the OLD versioned dir while a NEW one is now active.
# Acceptable — user just re-runs after the update completes.
# ----------------------------------------------------------------------------

function Get-WisprAsarPath {
    $rootCandidates = @()
    if ($env:WISPR_PATH) {
        $rootCandidates += $env:WISPR_PATH
    }
    else {
        $rootCandidates += (Join-Path $env:LOCALAPPDATA 'WisprFlow')
    }

    foreach ($root in $rootCandidates) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        # Form 1: $root points directly at app-X.Y.Z\
        $direct = Join-Path $root 'resources\app.asar'
        if (Test-Path -LiteralPath $direct) { return $direct }

        # Form 2: $root points at WisprFlow\ (Squirrel root) — find latest app-*
        $versioned = Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { [pscustomobject]@{ Dir = $_; Ver = [version]($_.Name -replace '^app-','') } }
                catch { $null }
            } |
            Where-Object { $_ } |
            Sort-Object Ver |
            Select-Object -Last 1

        if ($versioned) {
            $candidate = Join-Path $versioned.Dir.FullName 'resources\app.asar'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }

    return $null
}

function Get-WisprLauncher {
    # The Squirrel stub at WisprFlow\Wispr Flow.exe always launches the latest version.
    if ($env:WISPR_PATH) {
        $stub = Join-Path $env:WISPR_PATH 'Wispr Flow.exe'
        if (Test-Path -LiteralPath $stub) { return $stub }
        # Walk up if WISPR_PATH was an app-X.Y.Z dir
        $parent = Split-Path -Parent $env:WISPR_PATH
        $stub = Join-Path $parent 'Wispr Flow.exe'
        if (Test-Path -LiteralPath $stub) { return $stub }
    }
    $stub = Join-Path $env:LOCALAPPDATA 'WisprFlow\Wispr Flow.exe'
    if (Test-Path -LiteralPath $stub) { return $stub }
    return $null
}

# ----------------------------------------------------------------------------
# Process management — Electron spawns 10+ processes (main + GPU + renderer +
# helpers) all named "Wispr Flow". Wildcard catches them all in one pass.
# ----------------------------------------------------------------------------

function Test-WisprRunning {
    $procs = @()
    $procs += Get-Process -Name 'Wispr Flow'        -ErrorAction SilentlyContinue
    $procs += Get-Process -Name 'Wispr Flow Helper*' -ErrorAction SilentlyContinue
    return ($procs.Count -gt 0)
}

function Stop-WisprFlow {
    Get-Process -Name 'Wispr Flow'        -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name 'Wispr Flow Helper*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # 10-second budget — slow machines can lag releasing handles after Stop-Process
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Test-WisprRunning)) { return }
        Start-Sleep -Milliseconds 500
    }
}

function Start-WisprFlow {
    $launcher = Get-WisprLauncher
    if ($launcher) {
        try { Start-Process -FilePath $launcher -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
}

# ----------------------------------------------------------------------------
# Auto re-apply: scheduled task running this script with --ensure, as the
# current user, hidden. Two triggers: one minute after logon (Wispr Flow starts
# from the Startup folder around the same time) and every four hours.
# ----------------------------------------------------------------------------

function Enable-Auto {
    $hostExe = (Get-Process -Id $PID).Path            # the pwsh/powershell running right now
    $argLine = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" --ensure"
    $action  = New-ScheduledTaskAction -Execute $hostExe -Argument $argLine
    $user    = "$env:USERDOMAIN\$env:USERNAME"
    $logon   = New-ScheduledTaskTrigger -AtLogOn -User $user
    $logon.Delay = 'PT1M'
    $repeat  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 4)
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logon, $repeat) -Settings $settings `
        -Principal $principal -Description 'Re-applies the Wispr Flow Dark-Smokey theme after Wispr Flow updates.' -Force | Out-Null
    Write-Host "Auto re-apply enabled: scheduled task '$TaskName'" -ForegroundColor Green
    Write-Host "Runs '$PSCommandPath --ensure' a minute after logon and every 4 hours."
}

function Disable-Auto {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host 'Auto re-apply disabled.'
    }
    else {
        Write-Host 'Auto re-apply was not enabled.'
    }
}

if ($Action -eq 'enable-auto')  { Enable-Auto;  exit 0 }
if ($Action -eq 'disable-auto') { Disable-Auto; exit 0 }

if ($Action -eq 'uninstall') {
    $asar = Get-WisprAsarPath
    if ($asar -and (Test-Path -LiteralPath "$asar.bak")) {
        & $PSCommandPath --restore
    }
    else {
        Write-Host 'No backup found - Wispr Flow left as is.'
    }
    Disable-Auto
    if (Test-Path -LiteralPath $StampDir) { Remove-Item -LiteralPath $StampDir -Recurse -Force -ErrorAction SilentlyContinue }
    $cmdShim = [System.IO.Path]::ChangeExtension($PSCommandPath, '.cmd')
    foreach ($f in @($PSCommandPath, $cmdShim)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
    }
    Write-Host "Removed $PSCommandPath. Wispr Flow Dark-Smokey is uninstalled." -ForegroundColor Green
    exit 0
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

$asarPath = Get-WisprAsarPath
if (-not $asarPath) {
    if ($Ensure) { exit 0 }   # nothing to keep dark; stay quiet for the scheduled task
    $hint = if ($env:WISPR_PATH) { "(WISPR_PATH=$env:WISPR_PATH)" } else { "(default: $env:LOCALAPPDATA\WisprFlow)" }
    Write-Host "Error: Wispr Flow not found $hint" -ForegroundColor Red
    Write-Host "Install Wispr Flow from https://wispr.com/, or set WISPR_PATH to a custom location." -ForegroundColor Yellow
    exit 1
}

# The scheduled task inherits the user environment, but be generous about where
# node lives (nodejs.org MSI, winget, nvm-windows, fnm, volta).
$env:Path += ";$env:ProgramFiles\nodejs;$env:APPDATA\npm;$env:LOCALAPPDATA\Programs\nodejs;$env:NVM_SYMLINK;$env:LOCALAPPDATA\Volta\bin;$env:LOCALAPPDATA\fnm_multishells"
if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    if ($Ensure) { Write-Host 'npx not found; cannot re-apply'; exit 0 }
    Write-Host "Error: Node.js required (npx not found). Install: https://nodejs.org" -ForegroundColor Red
    exit 1
}

# The asar format stores HTML uncompressed, so the marker is searchable as a
# literal substring inside the binary — no extract needed. Codepage 28591
# (Latin1) round-trips bytes on both .NET Framework (PS 5.1) and .NET 6+.
function Test-Applied([string]$path) {
    $bytes = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::GetEncoding(28591))
    return $bytes.Contains($Marker)
}
function Get-AsarId([string]$path) {
    $f = Get-Item -LiteralPath $path
    return "$($f.LastWriteTimeUtc.Ticks):$($f.Length)"
}

$unpacked       = "$asarPath.unpacked"
$backup         = "$asarPath.bak"
$backupUnpacked = "$backup.unpacked"
$asarDir        = Split-Path -Parent $asarPath

$appWasRunning = Test-WisprRunning
$asarWritten   = $false
$tmpFile       = $null
$workDir       = $null

# ----------------------------------------------------------------------------
# --check: fast path, no extract. Exit 0 when applied, 1 when not, so scripts
# and the scheduled task can branch on it.
# ----------------------------------------------------------------------------
if ($Action -eq 'check') {
    try {
        if (Test-Applied $asarPath) { "Dark Smokey is applied."; exit 0 }
        "Dark Smokey is not applied."; exit 1
    }
    catch {
        Write-Host "Error reading asar: $_" -ForegroundColor Red
        exit 2
    }
}

# ----------------------------------------------------------------------------
# --ensure: only act when the theme is missing, and do not retry an asar that
# already failed once (a restructured Wispr Flow would otherwise get its app
# killed and restarted on every trigger).
# ----------------------------------------------------------------------------
if ($Ensure) {
    if (Test-Applied $asarPath) { exit 0 }
    if ((Test-Path -LiteralPath $Stamp) -and ((Get-Content -LiteralPath $Stamp -Raw).Trim() -eq (Get-AsarId $asarPath))) {
        Write-Host 'skipping: last attempt on this Wispr Flow build failed'
        exit 0
    }
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') theme missing - re-applying ($asarPath)"
}

# ----------------------------------------------------------------------------
# Cleanup trap — runs on success, failure, or Ctrl-C. Mirrors bash trap EXIT.
# ----------------------------------------------------------------------------
try {
    if ($appWasRunning) {
        Stop-WisprFlow
    }

    # ------------------------------------------------------------------------
    # --restore
    # ------------------------------------------------------------------------
    if ($Action -eq 'restore') {
        if (-not (Test-Path -LiteralPath $backup)) {
            Write-Host "No backup found." -ForegroundColor Red
            exit 1
        }
        Move-Item -LiteralPath $backup -Destination $asarPath -Force

        if (Test-Path -LiteralPath $backupUnpacked) {
            $unpackedTmp = "$unpacked.restoring.$PID"
            if (Test-Path -LiteralPath $unpacked) {
                try { Move-Item -LiteralPath $unpacked -Destination $unpackedTmp -Force } catch {}
            }
            try {
                Move-Item -LiteralPath $backupUnpacked -Destination $unpacked -Force
                if (Test-Path -LiteralPath $unpackedTmp) {
                    Remove-Item -LiteralPath $unpackedTmp -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                if (Test-Path -LiteralPath $unpackedTmp) {
                    Move-Item -LiteralPath $unpackedTmp -Destination $unpacked -Force -ErrorAction SilentlyContinue
                }
                Write-Host "Error: failed to restore $unpacked - original left intact." -ForegroundColor Red
                exit 1
            }
        }

        $asarWritten = $true
        Write-Host "Restored. Wispr Flow will restart."
        exit 0
    }

    # ------------------------------------------------------------------------
    # Apply theme
    # ------------------------------------------------------------------------

    # Backup (first run only) - must include .unpacked dir for native binaries
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $asarPath -Destination $backup
        if (Test-Path -LiteralPath $unpacked) {
            Copy-Item -LiteralPath $unpacked -Destination $backupUnpacked -Recurse
        }
    }

    # Working directory for extract/repack
    $workDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("wispr-dark-" + [Guid]::NewGuid().ToString('N'))) -Force
    $extractDir = Join-Path $workDir 'wispr'
    $patchedAsar = Join-Path $workDir 'patched.asar'

    Write-Host "==> Extracting..."
    & npx --yes $AsarCmd extract $backup $extractDir
    if ($LASTEXITCODE -ne 0) { throw "asar extract failed (exit $LASTEXITCODE)" }

    # ------------------------------------------------------------------------
    # CSS payloads (single line each — sed strip pattern uses .* which doesn't
    # span newlines, so multi-line CSS would break idempotent strip-and-repatch)
    # ------------------------------------------------------------------------

    $darkCss   = '<style data-wispr-dark-smokey>html{background:#15131a!important;filter:invert(.91) hue-rotate(180deg) brightness(.93)!important;-webkit-font-smoothing:antialiased!important}body{background:#15131a!important}img,video,canvas,svg image,picture>img{filter:invert(1) hue-rotate(180deg)!important}:root{--sand-50:#fff!important;--sand-100:#fefefe!important;--sand-200:#fdfdfc!important;--sand-300:#fcfcfb!important;--sand-400:#fbfbfa!important;--sand-500:#fafaf9!important;--vast-50:#fefefe!important;--vast-100:#fdfdfc!important;--neutral-10:#fff!important}*:focus-visible{outline:2px solid rgba(100,149,237,.6)!important;outline-offset:2px!important}::-webkit-scrollbar{width:5px;height:5px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:rgba(128,128,128,.22);border-radius:3px}::-webkit-scrollbar-thumb:hover{background:rgba(128,128,128,.5)}::-webkit-scrollbar-thumb:active{background:rgba(128,128,128,.7)}::selection{background:rgba(120,130,170,.35)!important;color:inherit!important}</style>'

    $statusCss = '<style data-wispr-dark-smokey>html,body{background:transparent!important}*{border-color:transparent!important;box-shadow:none!important}</style>'

    # ------------------------------------------------------------------------
    # Patch each renderer's index.html. Strip pattern matches both legacy bare
    # markers AND any attribute-bearing markers from intermediate v1.4.x
    # installs, so upgrades from any v1.x are clean.
    # ------------------------------------------------------------------------

    $stripRegex = "<style $Marker[^>]*>.*?</style>"
    $utf8NoBom  = [System.Text.UTF8Encoding]::new($false)

    foreach ($renderer in @('hub','scratchpad','contextMenu')) {
        $target = Join-Path $extractDir ".webpack\renderer\$renderer\index.html"
        if (-not (Test-Path -LiteralPath $target)) {
            throw "$renderer not found at $target - Wispr Flow may have updated its structure."
        }

        $content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)

        if ($content.Contains($Marker)) {
            Write-Host "==> Stripping old patch from $renderer..."
            $content = [regex]::Replace($content, $stripRegex, '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        }

        Write-Host "==> Patching $renderer..."
        $content = $content.Replace('</head>', "$darkCss</head>")
        [System.IO.File]::WriteAllText($target, $content, $utf8NoBom)

        if (-not $content.Contains($Marker)) {
            throw "failed to inject CSS into $renderer - </head> not found in $target"
        }
    }

    # Status bar: separate, invert-free stylesheet
    $statusTarget = Join-Path $extractDir '.webpack\renderer\status\index.html'
    if (Test-Path -LiteralPath $statusTarget) {
        $content = [System.IO.File]::ReadAllText($statusTarget, [System.Text.Encoding]::UTF8)
        if ($content.Contains($Marker)) {
            $content = [regex]::Replace($content, $stripRegex, '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        }
        Write-Host "==> Patching status..."
        $content = $content.Replace('</head>', "$statusCss</head>")
        [System.IO.File]::WriteAllText($statusTarget, $content, $utf8NoBom)

        if (-not $content.Contains($Marker)) {
            throw "failed to inject CSS into status - </head> not found in $statusTarget"
        }
    }

    # ------------------------------------------------------------------------
    # Repack and atomic rename. Temp file lives in the same NTFS volume as the
    # asar so Move-Item is atomic. Verify temp size matches packed size before
    # mv — catches truncated copies on disk-pressure conditions.
    # ------------------------------------------------------------------------
    Write-Host "==> Repacking..."
    & npx --yes $AsarCmd pack $extractDir $patchedAsar
    if ($LASTEXITCODE -ne 0) { throw "asar pack failed (exit $LASTEXITCODE)" }

    $packedSize = (Get-Item -LiteralPath $patchedAsar).Length
    if ($packedSize -le 0) { throw "asar pack produced empty file" }

    $tmpFile = Join-Path $asarDir (".app.asar.tmp." + [Guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $patchedAsar -Destination $tmpFile -Force

    $tmpSize = (Get-Item -LiteralPath $tmpFile).Length
    if ($tmpSize -ne $packedSize) {
        throw "temp file copy truncated ($tmpSize / $packedSize bytes) - is the disk full?"
    }

    # Retry Move-Item briefly in case Windows hasn't released the asar handle yet
    $moved = $false
    for ($i = 0; $i -lt 10; $i++) {
        try {
            Move-Item -LiteralPath $tmpFile -Destination $asarPath -Force
            $moved = $true
            break
        }
        catch {
            Start-Sleep -Milliseconds 400
        }
    }
    if (-not $moved) { throw "could not replace $asarPath - is Wispr Flow still running?" }

    $tmpFile = $null   # consumed by Move-Item; prevent finally from rm'ing it
    $asarWritten = $true

    Write-Host "Done. Wispr Flow Dark-Smokey applied." -ForegroundColor Green
}
finally {
    if ($Ensure -and $Action -eq 'apply') {
        if ($asarWritten) {
            if (Test-Path -LiteralPath $Stamp) { Remove-Item -LiteralPath $Stamp -Force -ErrorAction SilentlyContinue }
        }
        else {
            try {
                New-Item -ItemType Directory -Path $StampDir -Force | Out-Null
                Set-Content -LiteralPath $Stamp -Value (Get-AsarId $asarPath) -Encoding ascii
            } catch {}
        }
    }
    if ($workDir -and (Test-Path -LiteralPath $workDir)) {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($tmpFile -and (Test-Path -LiteralPath $tmpFile)) {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
    if ($asarWritten -or $appWasRunning) {
        Start-WisprFlow
    }
}
