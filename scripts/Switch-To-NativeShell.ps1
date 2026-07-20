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
$prepared = Get-Content -LiteralPath $preparedPath -Raw | ConvertFrom-Json
$managedPolicyWallpaper = [string]$prepared.policyWallpaper
if (-not (Test-Path -LiteralPath $managedPolicyWallpaper)) {
  throw "The managed MDM-compatible wallpaper is missing: $managedPolicyWallpaper"
}

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
Remove-Item -LiteralPath $systemPath -Force -ErrorAction SilentlyContinue
$seelenTask = Get-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction SilentlyContinue
$windhawkUiTask = Get-ScheduledTask -TaskName $windhawkUiTaskName -ErrorAction SilentlyContinue
$windhawkUiTaskWasEnabled = [bool]($windhawkUiTask -and $windhawkUiTask.Settings.Enabled)

try {
  $desktopPolicy = Get-Item -LiteralPath $desktopPolicyPath -ErrorAction SilentlyContinue
  $policyWallpaperPath = if ($desktopPolicy -and $desktopPolicy.GetValueNames() -contains 'Wallpaper') {
    [string]$desktopPolicy.GetValue('Wallpaper')
  } else {
    Join-Path $env:WINDIR 'web\wallpaper\DesktopPreto.png'
  }
  $policyWallpaperPath = [IO.Path]::GetFullPath($policyWallpaperPath)
  $allowedWallpaperRoot = [IO.Path]::GetFullPath((Join-Path $env:WINDIR 'web\wallpaper'))
  if (-not $policyWallpaperPath.StartsWith($allowedWallpaperRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace an MDM wallpaper outside the Windows wallpaper directory: $policyWallpaperPath"
  }
  $policyWallpaperBackup = Join-Path $stateRoot 'wallpaper-policy-original.png'
  if ((Test-Path -LiteralPath $policyWallpaperPath) -and -not (Test-Path -LiteralPath $policyWallpaperBackup)) {
    Copy-Item -LiteralPath $policyWallpaperPath -Destination $policyWallpaperBackup -Force
  }
  Copy-Item -LiteralPath $managedPolicyWallpaper -Destination $policyWallpaperPath -Force
  $managedPolicyHash = (Get-FileHash -LiteralPath $managedPolicyWallpaper -Algorithm SHA256).Hash
  if ((Get-FileHash -LiteralPath $policyWallpaperPath -Algorithm SHA256).Hash -ne $managedPolicyHash) {
    throw "The MDM wallpaper target was not replaced successfully: $policyWallpaperPath"
  }

  $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $policyManagerCurrentPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\current\$userSid\ADMX_Desktop"
  $policyManagerCurrent = Get-ItemProperty -LiteralPath $policyManagerCurrentPath -ErrorAction SilentlyContinue
  $policyManagerProviderPath = $null
  $policyManagerProviderBackup = Join-Path $stateRoot 'wallpaper-policy-provider-original.txt'
  if ($policyManagerCurrent -and $policyManagerCurrent.Wallpaper_ADMXInstanceData) {
    $instanceData = [string]$policyManagerCurrent.Wallpaper_ADMXInstanceData
    $policyManagerProviderPath = "Registry::HKEY_LOCAL_MACHINE\$instanceData"
    $provider = Get-ItemProperty -LiteralPath $policyManagerProviderPath -ErrorAction Stop
    $providerWallpaper = [string]$provider.Wallpaper
    if (-not (Test-Path -LiteralPath $policyManagerProviderBackup)) {
      [IO.File]::WriteAllText($policyManagerProviderBackup, $providerWallpaper, [Text.UTF8Encoding]::new($false))
    }
    $managedProviderWallpaper = '<enabled/><data id="WallpaperName" value="{0}" /><data id="WallpaperStyle" value="10" />' -f $policyWallpaperPath
    Set-ItemProperty -LiteralPath $policyManagerProviderPath -Name Wallpaper -Value $managedProviderWallpaper -Type String
  }
  New-ItemProperty -LiteralPath $desktopPolicyPath -Name Wallpaper -Value $policyWallpaperPath -PropertyType String -Force | Out-Null
  New-ItemProperty -LiteralPath $desktopPolicyPath -Name WallpaperStyle -Value '10' -PropertyType String -Force | Out-Null
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
    policyWallpaperPath = $policyWallpaperPath
    policyWallpaperBackup = $policyWallpaperBackup
    policyWallpaperManagedHash = $managedPolicyHash
    policyManagerProviderPath = $policyManagerProviderPath
    policyManagerProviderBackup = $policyManagerProviderBackup
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
