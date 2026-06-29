[CmdletBinding()]
param(
  [switch]$StartNow,
  [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "config\hot-corners.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "start-hot-corners.ps1"
$startupShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\Mac Makeover Hot Corners.lnk"
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) {
  $pwsh = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
}

$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -ConfigPath `"$ConfigPath`""

function Install-StartupShortcut {
  $shortcutDir = Split-Path -Parent $startupShortcut
  New-Item -ItemType Directory -Force -Path $shortcutDir | Out-Null
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($startupShortcut)
  $shortcut.TargetPath = $pwsh
  $shortcut.Arguments = $arguments
  $shortcut.WorkingDirectory = Split-Path -Parent $PSScriptRoot
  $shortcut.Description = "macOS-style hot corners for the Windows mac makeover."
  $shortcut.WindowStyle = 7
  $shortcut.Save()
  Write-Host "Installed Startup shortcut: $startupShortcut"
}

Install-StartupShortcut

if ($StartNow) {
  & (Join-Path $PSScriptRoot "stop-hot-corners.ps1")
  Start-Process -FilePath $pwsh -ArgumentList $arguments -WindowStyle Hidden
  Write-Host "Started hot corners."
}
