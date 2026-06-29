[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot
$programsDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Mac Makeover"
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) {
  $pwsh = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
}

New-Item -ItemType Directory -Force -Path $programsDir | Out-Null
$shell = New-Object -ComObject WScript.Shell

function New-PwshShortcut {
  param(
    [string]$Name,
    [string]$Arguments,
    [string]$Description
  )

  $shortcutPath = Join-Path $programsDir "$Name.lnk"
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $pwsh
  $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass $Arguments"
  $shortcut.WorkingDirectory = $PackageRoot
  $shortcut.Description = $Description
  $shortcut.IconLocation = "$env:windir\System32\shell32.dll,167"
  $shortcut.WindowStyle = 7
  $shortcut.Save()
  Write-Host "Shortcut: $shortcutPath"
}

function New-ExplorerShortcut {
  param(
    [string]$Name,
    [string]$TargetPath,
    [string]$Description
  )

  $shortcutPath = Join-Path $programsDir "$Name.lnk"
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = "$env:windir\explorer.exe"
  $shortcut.Arguments = "`"$TargetPath`""
  $shortcut.WorkingDirectory = $PackageRoot
  $shortcut.Description = $Description
  $shortcut.IconLocation = "$env:windir\System32\imageres.dll,3"
  $shortcut.Save()
  Write-Host "Shortcut: $shortcutPath"
}

$invoke = Join-Path $PSScriptRoot "Invoke-MacAction.ps1"
New-PwshShortcut "Mac Spotlight" "-File `"$invoke`" -Action Spotlight" "Open the Spotlight-style launcher."
New-PwshShortcut "Mac Mission Control" "-File `"$invoke`" -Action TaskView" "Open native Windows Task View."
New-PwshShortcut "Mac Show Desktop" "-File `"$invoke`" -Action ShowDesktop" "Toggle the desktop."
New-PwshShortcut "Mac Lock Screen" "-File `"$invoke`" -Action Lock" "Lock Windows."
New-PwshShortcut "Mac Visual QA" "-File `"$invoke`" -Action VisualQa" "Run mac makeover verification and capture QA screenshots."
New-PwshShortcut "Mac Backup Makeover" "-File `"$invoke`" -Action Backup" "Refresh the portable mac makeover package from this machine."
New-PwshShortcut "Mac Hot Corners Start" "-File `"$PSScriptRoot\install-hot-corners.ps1`" -StartNow" "Register and start macOS-style hot corners."
New-PwshShortcut "Mac Hot Corners Stop" "-File `"$PSScriptRoot\stop-hot-corners.ps1`"" "Stop macOS-style hot corners."
New-ExplorerShortcut "Mac Makeover Folder" $PackageRoot "Open the portable mac makeover package."

Write-Host "Spotlight shortcuts installed under: $programsDir"
