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
$windhawkUiTaskName = 'WindhawkRunUITask'
$desktopPolicyPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\System'

if (-not (Test-Path -LiteralPath $preparedPath)) {
  throw 'The unelevated user-profile preparation has not completed.'
}

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
Remove-Item -LiteralPath $systemPath -Force -ErrorAction SilentlyContinue
$seelenTask = Get-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction SilentlyContinue
$windhawkUiTask = Get-ScheduledTask -TaskName $windhawkUiTaskName -ErrorAction SilentlyContinue
$windhawkUiTaskWasEnabled = [bool]($windhawkUiTask -and $windhawkUiTask.Settings.Enabled)

try {
  $desktopPolicy = Get-Item -LiteralPath $desktopPolicyPath -ErrorAction SilentlyContinue
  foreach ($name in 'Wallpaper', 'WallpaperStyle') {
    if ($desktopPolicy -and $desktopPolicy.GetValueNames() -contains $name) {
      Remove-ItemProperty -LiteralPath $desktopPolicyPath -Name $name -ErrorAction Stop
    }
  }
  $remainingWallpaperPolicy = $null
  $remainingWallpaperProperty = Get-ItemProperty -LiteralPath $desktopPolicyPath `
    -Name Wallpaper -ErrorAction SilentlyContinue
  if ($remainingWallpaperProperty) {
    $remainingWallpaperPolicy = $remainingWallpaperProperty.PSObject.Properties['Wallpaper'].Value
  }
  if (-not [string]::IsNullOrWhiteSpace($remainingWallpaperPolicy)) {
    throw "The protected wallpaper policy remains active: $remainingWallpaperPolicy"
  }
  & (Join-Path $PSScriptRoot 'Install-NativeDock.ps1') -Disable
  Stop-Service -Name Windhawk -Force -ErrorAction SilentlyContinue
  Set-Service -Name Windhawk -StartupType Manual -ErrorAction SilentlyContinue
  if ($windhawkUiTask) {
    Stop-ScheduledTask -TaskName $windhawkUiTaskName -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskName $windhawkUiTaskName | Out-Null
  }

  if ($seelenTask) {
    Stop-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName | Out-Null
  }

  & (Join-Path $PSScriptRoot 'stop-hot-corners.ps1')
  Get-Process MacMakeover.MenuBar, MacMakeover.MenuHost, MacMakeover.Dock, seelen-ui, slu-service, yasb -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

  $result = [ordered]@{
    enabledAt = (Get-Date).ToString('o')
    seelenTaskExisted = [bool]$seelenTask
    windhawkUiTaskExisted = [bool]$windhawkUiTask
    windhawkUiTaskWasEnabled = $windhawkUiTaskWasEnabled
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
  if ($windhawkUiTaskWasEnabled) {
    Enable-ScheduledTask -TaskName $windhawkUiTaskName -ErrorAction SilentlyContinue | Out-Null
  }
  throw
}

Write-Host 'Privileged native-shell phase completed.'
