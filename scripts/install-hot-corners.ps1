[CmdletBinding()]
param(
  [switch]$StartNow,
  [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "config\hot-corners.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "start-hot-corners.ps1"
$startupShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\Mac Makeover Hot Corners.lnk"
$pwsh = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path -LiteralPath $pwsh)) {
  $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
}

$arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -ConfigPath `"$ConfigPath`""

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

# Keepalive: the helper is single-instance (named mutex), so a 5-minute scheduled task
# can safely re-launch it forever - duplicates exit instantly. This heals the failure
# mode where the helper silently dies (sleep/resume, crash) and every top-bar click
# stops working until the next login. conhost --headless avoids any window flash.
function Install-KeepaliveTask {
  try {
    $conhost = Join-Path $env:windir "System32\conhost.exe"
    $taskArgs = "--headless `"$pwsh`" $arguments"
    $action = New-ScheduledTaskAction -Execute $conhost -Argument $taskArgs
    $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
    $logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName "MacMakeover Hot Corners Keepalive" -Action $action -Trigger @($repeat, $logon) -Settings $settings -Force | Out-Null
    Write-Host "Installed keepalive scheduled task: MacMakeover Hot Corners Keepalive (every 5 minutes)"
  } catch {
    Write-Warning "Could not register the keepalive scheduled task (Startup shortcut still installed): $($_.Exception.Message)"
  }
}

if ($StartNow) {
  & (Join-Path $PSScriptRoot "stop-hot-corners.ps1")
  Start-Process -FilePath $pwsh -ArgumentList $arguments -WindowStyle Hidden
  Write-Host "Started hot corners."
}

# Registered after -StartNow: stop-hot-corners.ps1 disables the keepalive task, and
# Register-ScheduledTask -Force re-registers it enabled.
Install-KeepaliveTask
