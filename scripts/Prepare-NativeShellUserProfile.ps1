[CmdletBinding()]
param(
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run user-profile preparation from a normal, non-administrator PowerShell session.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$deploymentRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin'
$stateRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration'
$statePath = Join-Path $stateRoot 'native-shell-state.json'
$preparedPath = Join-Path $stateRoot 'user-profile-prepared.json'
$stagingRoot = Join-Path $stateRoot 'native-shell-staged'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$advancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$searchKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$stuckRectsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
$desktopPolicyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
$virtualDesktopsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops\Desktops'

function Get-RegistryValueSnapshot([string]$Path, [string]$Name) {
  $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $key) { return @{ exists = $false; value = $null; kind = $null } }
  $exists = $key.GetValueNames() -contains $Name
  return @{
    exists = $exists
    value = if ($exists) { $key.GetValue($Name) } else { $null }
    kind = if ($exists) { [string]$key.GetValueKind($Name) } else { $null }
  }
}

function Set-NativeTaskbarVisible {
  $settings = (Get-ItemProperty -LiteralPath $stuckRectsPath -ErrorAction SilentlyContinue).Settings
  if ($settings -and $settings.Length -gt 8) {
    $settings[8] = [byte]($settings[8] -band 0xFE)
    Set-ItemProperty -LiteralPath $stuckRectsPath -Name Settings -Value $settings
  }
}

function Set-MacWallpaper {
  $source = Join-Path $repoRoot 'assets\wallpapers\mac-wallpaper.jpg'
  $expectedHash = 'D228004F1A1DD90FA49EF04C7799AD80D98E6B19CC1C7CF28C7D484B86A8759D'
  $actualHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
  if ($actualHash -ne $expectedHash) {
    throw 'The managed Big Sur (Day) wallpaper does not match the archived Seelen asset.'
  }
  $targetRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\wallpapers'
  $target = Join-Path $targetRoot 'mac-wallpaper.jpg'
  New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
  Copy-Item -LiteralPath $source -Destination $target -Force
  try {
    foreach ($name in 'Wallpaper', 'WallpaperStyle') {
      Remove-ItemProperty -LiteralPath $desktopPolicyPath -Name $name -ErrorAction Stop
    }
  } catch {
    if ($_.Exception.Message -notmatch 'registry access is not allowed|access.*denied') { throw }
    Write-Warning 'The SYSTEM-owned wallpaper policy will be cleared by the privileged promotion phase.'
  }
  Get-ChildItem -LiteralPath $virtualDesktopsPath -ErrorAction SilentlyContinue | ForEach-Object {
    Set-ItemProperty -LiteralPath $_.PSPath -Name Wallpaper -Value $target -Type String
  }
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'

  Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class NativeUserWallpaper {
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool SystemParametersInfo(int action, int parameter, string path, int flags);
}
'@
  if (-not [NativeUserWallpaper]::SystemParametersInfo(20, 0, $target, 3)) {
    throw 'Windows rejected the wallpaper update.'
  }
}

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
if (-not (Test-Path -LiteralPath $statePath)) {
  $stuckRects = (Get-ItemProperty -LiteralPath $stuckRectsPath -ErrorAction SilentlyContinue).Settings
  $state = [ordered]@{
    capturedAt = (Get-Date).ToString('o')
    taskbarAutoHide = [bool]($stuckRects -and $stuckRects.Length -gt 8 -and (($stuckRects[8] -band 1) -eq 1))
    wallpaper = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
    wallpaperPolicy = [ordered]@{
      Wallpaper = Get-RegistryValueSnapshot $desktopPolicyPath 'Wallpaper'
      WallpaperStyle = Get-RegistryValueSnapshot $desktopPolicyPath 'WallpaperStyle'
    }
    advanced = [ordered]@{}
    search = [ordered]@{}
    run = [ordered]@{}
  }
  foreach ($name in 'TaskbarAl', 'TaskbarDa', 'ShowTaskViewButton', 'SearchboxTaskbarMode', 'MMTaskbarEnabled') {
    $state.advanced[$name] = Get-RegistryValueSnapshot $advancedKey $name
  }
  foreach ($name in 'MacMakeoverMenuBar', 'MacMakeoverMenuHost', 'MacMakeoverDock') {
    $state.run[$name] = Get-RegistryValueSnapshot $runKey $name
  }
  foreach ($name in 'SearchboxTaskbarMode', 'SearchboxTaskbarModeCache') {
    $state.search[$name] = Get-RegistryValueSnapshot $searchKey $name
  }
  [System.IO.File]::WriteAllText(
    $statePath,
    ($state | ConvertTo-Json -Depth 8),
    (New-Object System.Text.UTF8Encoding($false)))
}

# Older native-profile snapshots predate the second Search registry location.
# Backfill it before changing live state so rollback remains lossless.
$savedState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
if (-not $savedState.Contains('search')) {
  $savedState.search = [ordered]@{}
  foreach ($name in 'SearchboxTaskbarMode', 'SearchboxTaskbarModeCache') {
    $savedState.search[$name] = Get-RegistryValueSnapshot $searchKey $name
  }
  [System.IO.File]::WriteAllText(
    $statePath,
    ($savedState | ConvertTo-Json -Depth 8),
    (New-Object System.Text.UTF8Encoding($false)))
}
if (-not $savedState.Contains('run')) { $savedState.run = [ordered]@{} }
if (-not $savedState.run.Contains('MacMakeoverDock')) {
  $savedState.run.MacMakeoverDock = Get-RegistryValueSnapshot $runKey 'MacMakeoverDock'
  [System.IO.File]::WriteAllText(
    $statePath,
    ($savedState | ConvertTo-Json -Depth 8),
    (New-Object System.Text.UTF8Encoding($false)))
}
if (-not $savedState.Contains('wallpaperPolicy')) {
  $savedState.wallpaperPolicy = [ordered]@{
    Wallpaper = Get-RegistryValueSnapshot $desktopPolicyPath 'Wallpaper'
    WallpaperStyle = Get-RegistryValueSnapshot $desktopPolicyPath 'WallpaperStyle'
  }
  [System.IO.File]::WriteAllText(
    $statePath,
    ($savedState | ConvertTo-Json -Depth 8),
    (New-Object System.Text.UTF8Encoding($false)))
}

$artifactRoot = $deploymentRoot
if (-not $SkipBuild) {
  & (Join-Path $PSScriptRoot 'Build-NativeShell.ps1') -Destination $stagingRoot
  $artifactRoot = $stagingRoot
}
foreach ($required in @(
    'MacMakeover.MenuBar.exe',
    'MacMakeover.MenuHost.exe',
    'MacMakeover.Dock.exe',
    'native-taskbar-pins.json',
    'Assets\apple-mark.png',
    'Assets\Fonts\Manrope-Regular.ttf',
    'Assets\Fonts\Manrope-SemiBold.ttf',
    'Assets\Fonts\JetBrainsMono-Medium.ttf'
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $artifactRoot $required))) {
    throw "Native shell artifact is missing: $required"
  }
}

$deployedDock = Join-Path $deploymentRoot 'MacMakeover.Dock.exe'
if (Test-Path -LiteralPath $deployedDock) {
  Start-Process -FilePath $deployedDock -ArgumentList '--shutdown' -Wait -WindowStyle Hidden
  Start-Sleep -Milliseconds 500
}
Get-Process MacMakeover.MenuBar, MacMakeover.MenuHost, MacMakeover.Dock -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
if ($artifactRoot -ne $deploymentRoot) {
  New-Item -ItemType Directory -Force -Path $deploymentRoot | Out-Null
  Copy-Item -Path (Join-Path $artifactRoot '*') -Destination $deploymentRoot -Recurse -Force
}

& (Join-Path $PSScriptRoot 'Install-AppleMenuHandler.ps1')
& (Join-Path $PSScriptRoot 'Install-MacControlCenterHandler.ps1')
& (Join-Path $PSScriptRoot 'Install-MacNetworkHandler.ps1')
& (Join-Path $PSScriptRoot 'Install-MacBluetoothHandler.ps1')
& (Join-Path $PSScriptRoot 'Install-MacNotificationCenterHandler.ps1')

if (-not (Test-Path -LiteralPath $advancedKey)) { New-Item -Path $advancedKey -Force | Out-Null }
foreach ($entry in @{
    TaskbarAl = 1
    TaskbarDa = 0
    ShowTaskViewButton = 0
    SearchboxTaskbarMode = 0
    MMTaskbarEnabled = 1
  }.GetEnumerator()) {
  try {
    $advanced = Get-Item -LiteralPath $advancedKey
    if ($advanced.GetValueNames() -contains $entry.Key) {
      Set-ItemProperty -LiteralPath $advancedKey -Name $entry.Key -Value $entry.Value
    } else {
      New-ItemProperty -LiteralPath $advancedKey -Name $entry.Key -Value $entry.Value -PropertyType DWord -Force | Out-Null
    }
  } catch {
    Write-Warning "Optional Explorer preference $($entry.Key) is managed by Windows and was left unchanged."
  }
}
Set-NativeTaskbarVisible
Set-MacWallpaper

if (-not (Test-Path -LiteralPath $searchKey)) { New-Item -Path $searchKey -Force | Out-Null }
foreach ($name in 'SearchboxTaskbarMode', 'SearchboxTaskbarModeCache') {
  New-ItemProperty -LiteralPath $searchKey -Name $name -Value 0 -PropertyType DWord -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $runKey)) { New-Item -Path $runKey | Out-Null }
$menuBar = Join-Path $deploymentRoot 'MacMakeover.MenuBar.exe'
$menuHost = Join-Path $deploymentRoot 'MacMakeover.MenuHost.exe'
$dock = Join-Path $deploymentRoot 'MacMakeover.Dock.exe'
New-ItemProperty -LiteralPath $runKey -Name MacMakeoverMenuHost -Value ('"{0}"' -f $menuHost) -PropertyType String -Force | Out-Null
New-ItemProperty -LiteralPath $runKey -Name MacMakeoverMenuBar -Value ('"{0}"' -f $menuBar) -PropertyType String -Force | Out-Null
New-ItemProperty -LiteralPath $runKey -Name MacMakeoverDock -Value ('"{0}"' -f $dock) -PropertyType String -Force | Out-Null

$prepared = [ordered]@{ preparedAt = (Get-Date).ToString('o'); deploymentRoot = $deploymentRoot } | ConvertTo-Json
[System.IO.File]::WriteAllText($preparedPath, $prepared, (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'Unelevated native-shell user profile prepared.'
