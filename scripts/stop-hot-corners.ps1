[CmdletBinding()]
param(
  [switch]$StopTaskOnly,
  [switch]$Unregister
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$taskName = "Mac Makeover Hot Corners"
$taskPath = "\"
$startupShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\Mac Makeover Hot Corners.lnk"

try {
  $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
  if ($task) {
    Stop-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    if ($Unregister) {
      Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false
      Write-Host "Unregistered scheduled task: $taskPath$taskName"
    } else {
      Write-Host "Stopped scheduled task: $taskPath$taskName"
    }
  }
} catch {
  Write-Warning "Scheduled task cleanup skipped: $($_.Exception.Message)"
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
