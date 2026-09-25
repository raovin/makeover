#Requires -RunAsAdministrator
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$systemStatePath = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration\system-profile-enabled.json'
$userStatePath = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration\native-shell-state.json'
$desktopPolicyPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\System'

function Restore-RegistrySnapshot([string]$Path, [string]$Name, $Snapshot) {
  if ($null -eq $Snapshot) { return }
  if (-not $Snapshot.exists) {
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    return
  }
  $kind = if ($Snapshot.kind) { [string]$Snapshot.kind } else { 'String' }
  New-ItemProperty -LiteralPath $Path -Name $Name -Value $Snapshot.value -PropertyType $kind -Force | Out-Null
}

function Get-StateProperty {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name
  )

  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

& (Join-Path $repoRoot 'scripts\Install-NativeDock.ps1') -Disable
$task = Get-ScheduledTask -TaskPath '\Seelen\' -TaskName 'Seelen UI Service' -ErrorAction SilentlyContinue
if ($task) {
  Enable-ScheduledTask -TaskPath '\Seelen\' -TaskName 'Seelen UI Service' -ErrorAction SilentlyContinue | Out-Null
  Start-ScheduledTask -TaskPath '\Seelen\' -TaskName 'Seelen UI Service' -ErrorAction SilentlyContinue
}
$hotCorners = Get-ScheduledTask -TaskName 'MacMakeover Hot Corners Keepalive' -ErrorAction SilentlyContinue
if ($hotCorners) { Enable-ScheduledTask -TaskName 'MacMakeover Hot Corners Keepalive' -ErrorAction SilentlyContinue | Out-Null }
if (Test-Path -LiteralPath $systemStatePath) {
  $systemState = Get-Content -LiteralPath $systemStatePath -Raw | ConvertFrom-Json
  $wallpaperGuardTaskName = [string](Get-StateProperty $systemState 'wallpaperGuardTaskName')
  if ([string]::IsNullOrWhiteSpace($wallpaperGuardTaskName)) { $wallpaperGuardTaskName = 'MacMakeover Wallpaper Guard' }
  Unregister-ScheduledTask -TaskName $wallpaperGuardTaskName -Confirm:$false -ErrorAction SilentlyContinue
  $wallpaperGuardScript = [string](Get-StateProperty $systemState 'wallpaperGuardScript')
  if (-not [string]::IsNullOrWhiteSpace($wallpaperGuardScript) -and
      (Test-Path -LiteralPath $wallpaperGuardScript)) {
    Remove-Item -LiteralPath $wallpaperGuardScript -Force
  }
  $hotCornersStartupBackup = [string](Get-StateProperty $systemState 'hotCornersStartupBackup')
  $hotCornersStartupPath = [string](Get-StateProperty $systemState 'hotCornersStartupPath')
  if ([bool](Get-StateProperty $systemState 'hotCornersStartupExisted') -and
      -not [string]::IsNullOrWhiteSpace($hotCornersStartupBackup) -and
      -not [string]::IsNullOrWhiteSpace($hotCornersStartupPath) -and
      (Test-Path -LiteralPath $hotCornersStartupBackup)) {
    Copy-Item -LiteralPath $hotCornersStartupBackup -Destination $hotCornersStartupPath -Force
  }
  if ([bool](Get-StateProperty $systemState 'windhawkUiTaskExisted') -and
      [bool](Get-StateProperty $systemState 'windhawkUiTaskWasEnabled')) {
    Enable-ScheduledTask -TaskName 'WindhawkRunUITask' -ErrorAction SilentlyContinue | Out-Null
  }
  $policyWallpaperPath = [string](Get-StateProperty $systemState 'policyWallpaperPath')
  $policyWallpaperBackup = [string](Get-StateProperty $systemState 'policyWallpaperBackup')
  if (-not [string]::IsNullOrWhiteSpace($policyWallpaperPath) -and
      -not [string]::IsNullOrWhiteSpace($policyWallpaperBackup) -and
      (Test-Path -LiteralPath $policyWallpaperBackup)) {
    Copy-Item -LiteralPath $policyWallpaperBackup -Destination $policyWallpaperPath -Force
  }
  $policyManagerProviderPath = [string](Get-StateProperty $systemState 'policyManagerProviderPath')
  $policyManagerProviderBackup = [string](Get-StateProperty $systemState 'policyManagerProviderBackup')
  if (-not [string]::IsNullOrWhiteSpace($policyManagerProviderPath) -and
      -not [string]::IsNullOrWhiteSpace($policyManagerProviderBackup) -and
      (Test-Path -LiteralPath $policyManagerProviderBackup)) {
    $providerWallpaper = Get-Content -LiteralPath $policyManagerProviderBackup -Raw
    Set-ItemProperty -LiteralPath $policyManagerProviderPath `
      -Name Wallpaper -Value $providerWallpaper -Type String
  }
}
if (Test-Path -LiteralPath $userStatePath) {
  $userState = Get-Content -LiteralPath $userStatePath -Raw | ConvertFrom-Json
  if ($userState.PSObject.Properties.Name -contains 'wallpaperPolicy') {
    Restore-RegistrySnapshot $desktopPolicyPath 'Wallpaper' $userState.wallpaperPolicy.Wallpaper
    Restore-RegistrySnapshot $desktopPolicyPath 'WallpaperStyle' $userState.wallpaperPolicy.WallpaperStyle
  }
}
Write-Host 'Privileged Seelen rollback completed.'
