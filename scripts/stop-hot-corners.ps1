[CmdletBinding()]
param(
  [switch]$StopTaskOnly,
  [switch]$Unregister
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$keepaliveTaskName = "MacMakeover Hot Corners Keepalive"
$startupShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\Mac Makeover Hot Corners.lnk"

# The keepalive task relaunches the helper every 5 minutes, so stopping the helper
# without pausing the task would just resurrect it. Disable on stop, remove on unregister.
try {
  $task = Get-ScheduledTask -TaskName $keepaliveTaskName -ErrorAction SilentlyContinue
  if ($task) {
    if ($Unregister) {
      Unregister-ScheduledTask -TaskName $keepaliveTaskName -Confirm:$false
      Write-Host "Unregistered keepalive scheduled task: $keepaliveTaskName"
    } else {
      Disable-ScheduledTask -TaskName $keepaliveTaskName | Out-Null
      Write-Host "Disabled keepalive scheduled task (re-enable with install-hot-corners.ps1): $keepaliveTaskName"
    }
  }
} catch {
  Write-Warning "Keepalive task cleanup skipped: $($_.Exception.Message)"
}

if ($Unregister -and (Test-Path -LiteralPath $startupShortcut)) {
  Remove-Item -LiteralPath $startupShortcut -Force
  Write-Host "Removed Startup shortcut: $startupShortcut"
}

if (-not $StopTaskOnly) {
  Get-CimInstance Win32_Process |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "* -File *start-hot-corners.ps1*" } |
    ForEach-Object {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
      Write-Host "Stopped hot-corners process: $($_.ProcessId)"
    }
}
