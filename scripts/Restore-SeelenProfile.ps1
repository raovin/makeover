[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$yasbc = Join-Path $env:ProgramFiles 'YASB\yasbc.exe'
$seelenTaskPath = '\Seelen\'
$seelenTaskName = 'Seelen UI Service'
$startupShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Mac Makeover Hot Corners.lnk'
$statePath = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration\native-shell-state.json'

if (-not (Get-Command slu-service.exe -ErrorAction SilentlyContinue)) {
  Write-Host 'Reinstalling Seelen UI for rollback...'
  & winget install --id Seelen.SeelenUI --exact --silent --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    throw 'Seelen UI could not be reinstalled.'
  }
}

if (Test-Path -LiteralPath $yasbc) {
  & $yasbc stop 2>$null
  & $yasbc disable-autostart 2>$null
}

$seelenTask = Get-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction SilentlyContinue
if ($seelenTask) {
  try {
    Enable-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName | Out-Null
    Start-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName
  } catch {
    Write-Warning 'Seelen scheduled task needs elevation to re-enable.'
  }
}

if (Test-Path -LiteralPath $startupShortcut) {
  & (Join-Path $PSScriptRoot 'install-hot-corners.ps1')
}

if (Test-Path -LiteralPath $statePath) {
  $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
  if ($state.taskbarAutoHide) {
    $stuckRectsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
    $stuckRects = (Get-ItemProperty -LiteralPath $stuckRectsPath -ErrorAction SilentlyContinue).Settings
    if ($stuckRects -and $stuckRects.Length -gt 8) {
      $stuckRects[8] = [byte]($stuckRects[8] -bor 1)
      Set-ItemProperty -LiteralPath $stuckRectsPath -Name Settings -Value $stuckRects
    }
  }
}

Write-Host 'Seelen profile restored. Sign out and back in if its service does not immediately repaint both bars.'
