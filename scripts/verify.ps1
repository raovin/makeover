[CmdletBinding()]
param(
  [switch]$CaptureScreenshot,
  [switch]$SkipDownloadCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'Test-NativeShellPreflight.ps1') -SkipDownloadCheck:$SkipDownloadCheck
if ($LASTEXITCODE) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot 'Test-NativeShellProfile.ps1')
if ($LASTEXITCODE) { exit $LASTEXITCODE }

if ($CaptureScreenshot) {
  if (Get-Process LogonUI -ErrorAction SilentlyContinue) {
    throw 'Visual QA is unavailable while Windows is locked. Unlock the desktop and rerun verification.'
  }
  $repoRoot = Split-Path -Parent $PSScriptRoot
  $qaRoot = Join-Path $repoRoot 'qa'
  New-Item -ItemType Directory -Path $qaRoot -Force | Out-Null
  $path = Join-Path $qaRoot ("native-shell-{0}.png" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
  & (Join-Path $PSScriptRoot 'Capture-Desktop.ps1') -Path $path
  Write-Host "Visual QA capture: $path"
}

Write-Host 'PASS: native shell verification completed.'
