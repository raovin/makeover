#Requires -RunAsAdministrator
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration'
$preparedPath = Join-Path $stateRoot 'user-profile-prepared.json'
$systemPath = Join-Path $stateRoot 'system-profile-enabled.json'
$seelenTaskPath = '\Seelen\'
$seelenTaskName = 'Seelen UI Service'

if (-not (Test-Path -LiteralPath $preparedPath)) {
  throw 'The unelevated user-profile preparation has not completed.'
}

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
Remove-Item -LiteralPath $systemPath -Force -ErrorAction SilentlyContinue
$seelenTask = Get-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction SilentlyContinue

try {
  & (Join-Path $PSScriptRoot 'Install-NativeDock.ps1') -Enable

  if ($seelenTask) {
    Stop-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName | Out-Null
  }

  & (Join-Path $PSScriptRoot 'stop-hot-corners.ps1')
  Get-Process MacMakeover.MenuBar, MacMakeover.MenuHost, seelen-ui, slu-service, yasb -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

  $result = [ordered]@{
    enabledAt = (Get-Date).ToString('o')
    seelenTaskExisted = [bool]$seelenTask
  } | ConvertTo-Json
  [System.IO.File]::WriteAllText($systemPath, $result, (New-Object System.Text.UTF8Encoding($false)))
}
catch {
  Write-Warning "Privileged native-shell phase failed: $($_.Exception.Message)"
  & (Join-Path $PSScriptRoot 'Install-NativeDock.ps1') -Disable -ErrorAction SilentlyContinue
  if ($seelenTask) {
    Enable-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction SilentlyContinue | Out-Null
    Start-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction SilentlyContinue
  }
  throw
}

Write-Host 'Privileged native-shell phase completed.'
