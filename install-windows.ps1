#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
  One-shot installer for Wispr Flow Dark-Smokey on Windows.

.DESCRIPTION
  Downloads (or copies, when run from a clone) the .ps1 + .cmd into
  $env:USERPROFILE\.local\bin\, applies the theme right away, and registers a
  scheduled task that re-applies it after Wispr Flow auto-updates.

.PARAMETER FromClone
  Install from the local repo clone instead of GitHub raw URLs.

.PARAMETER NoApply
  Install the command only; do not patch Wispr Flow now.

.PARAMETER NoAuto
  Do not register the re-apply scheduled task.

.EXAMPLE
  iwr -useb https://raw.githubusercontent.com/ll1li/wispr-flow-dark-smokey/main/install-windows.ps1 | iex

.EXAMPLE
  # Command + theme, no scheduled task:
  & ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/ll1li/wispr-flow-dark-smokey/main/install-windows.ps1))) -NoAuto

.EXAMPLE
  # From a local clone:
  ./install-windows.ps1 -FromClone
#>

[CmdletBinding()]
param(
    [switch]$FromClone,
    [switch]$NoApply,
    [switch]$NoAuto
)

$ErrorActionPreference = 'Stop'

$RawBase = 'https://raw.githubusercontent.com/ll1li/wispr-flow-dark-smokey/main'
$Files   = @('wispr-flow-dark-smokey.ps1', 'wispr-flow-dark-smokey.cmd')

$BinDir = Join-Path $env:USERPROFILE '.local\bin'
if (-not (Test-Path -LiteralPath $BinDir)) {
    Write-Host "Creating $BinDir..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

# ----------------------------------------------------------------------------
# Copy or download
# ----------------------------------------------------------------------------

foreach ($file in $Files) {
    $dest = Join-Path $BinDir $file
    if ($FromClone) {
        $src = Join-Path $PSScriptRoot $file
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Host "Error: $src not found. Run from inside the repo clone." -ForegroundColor Red
            exit 1
        }
        Write-Host "Copying $file -> $dest" -ForegroundColor Cyan
        Copy-Item -LiteralPath $src -Destination $dest -Force
    }
    else {
        $url = "$RawBase/$file"
        Write-Host "Downloading $file from $url" -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
}

$Ps1 = Join-Path $BinDir 'wispr-flow-dark-smokey.ps1'

Write-Host ''
Write-Host '----------------------------------------------------------------------'
Write-Host "Installed to: $BinDir" -ForegroundColor Green
Write-Host '----------------------------------------------------------------------'

# ----------------------------------------------------------------------------
# Apply now, so the theme is on without a second command. A missing Wispr Flow
# or Node.js is reported, not fatal: the command is installed either way.
# ----------------------------------------------------------------------------

if (-not $NoApply) {
    Write-Host ''
    & $Ps1 --ensure          # applies only when missing; a re-run never restarts a themed app
    & $Ps1 --check
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Theme not applied yet (see above). Run 'wispr-flow-dark-smokey' once that is fixed." -ForegroundColor Yellow
    }
}

if (-not $NoAuto) {
    Write-Host ''
    & $Ps1 --enable-auto
}

# ----------------------------------------------------------------------------
# PATH check - non-destructive: warn the user with a copy-pasteable fix.
# (We don't silently mutate PATH; that's surprising and hard to undo.)
# ----------------------------------------------------------------------------

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathParts = if ($userPath) { $userPath -split ';' | Where-Object { $_ } } else { @() }
$onPath = $pathParts -contains $BinDir -or $pathParts -contains $BinDir.TrimEnd('\')

if (-not $onPath) {
    Write-Host ''
    Write-Host "  To use the command by name, add $BinDir to your user PATH once (new PowerShell window):" -ForegroundColor Yellow
    Write-Host ''
    Write-Host "      [Environment]::SetEnvironmentVariable('Path', ([Environment]::GetEnvironmentVariable('Path','User') + ';$BinDir'), 'User')" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Then close and reopen your shell. The theme and the re-apply task work without this.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Commands:' -ForegroundColor Cyan
Write-Host '  wispr-flow-dark-smokey --check        # is the theme on?'
Write-Host '  wispr-flow-dark-smokey --restore      # back to the original look'
Write-Host '  wispr-flow-dark-smokey --uninstall    # restore, remove the task and the command'
Write-Host ''
