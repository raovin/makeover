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
  if ($systemState.windhawkUiTaskExisted -and $systemState.windhawkUiTaskWasEnabled) {
    Enable-ScheduledTask -TaskName 'WindhawkRunUITask' -ErrorAction SilentlyContinue | Out-Null
  }
  if ($systemState.PSObject.Properties.Name -contains 'policyWallpaperPath' -and
      $systemState.PSObject.Properties.Name -contains 'policyWallpaperBackup' -and
      (Test-Path -LiteralPath ([string]$systemState.policyWallpaperBackup))) {
    Copy-Item -LiteralPath ([string]$systemState.policyWallpaperBackup) `
      -Destination ([string]$systemState.policyWallpaperPath) -Force
  }
  if ($systemState.PSObject.Properties.Name -contains 'policyManagerProviderPath' -and
      $systemState.PSObject.Properties.Name -contains 'policyManagerProviderBackup' -and
      $systemState.policyManagerProviderPath -and
      (Test-Path -LiteralPath ([string]$systemState.policyManagerProviderBackup))) {
    $providerWallpaper = Get-Content -LiteralPath ([string]$systemState.policyManagerProviderBackup) -Raw
    Set-ItemProperty -LiteralPath ([string]$systemState.policyManagerProviderPath) `
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
