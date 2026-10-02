[CmdletBinding()]
param(
  [switch]$SkipBuild,
  [switch]$SelfTestOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NativeShellTasks.ps1')

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

function Get-RegistryValueSnapshot([string]$Path, [string]$Name, [scriptblock]$GetItem = $null) {
  if ($GetItem) {
    $key = & $GetItem $Path
  } else {
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  }
  if (-not $key) { return @{ exists = $false; value = $null; kind = $null } }
  $exists = $key.GetValueNames() -contains $Name
  $value = $null
  $kind = $null
  if ($exists) {
    # Assign the registry object directly. An if-expression enumerates byte[] values.
    $value = $key.GetValue($Name)
    $kind = [string]$key.GetValueKind($Name)
  }
  return @{
    exists = $exists
    value = $value
    kind = $kind
  }
}

function Get-RegistrySnapshotValue([hashtable]$Snapshot) {
  if ($Snapshot.exists) { return $Snapshot.value }
  return $null
}

function Get-TaskbarAutoHideFromSnapshot([hashtable]$Snapshot) {
  $settings = $null
  if ($Snapshot.exists) {
    # Keep the registry's byte[] type intact; an if-expression enumerates it.
    $settings = $Snapshot.value
  }
  return [bool]($settings -is [byte[]] -and $settings.Length -gt 8 -and (($settings[8] -band 1) -eq 1))
}

function Test-ProfileSnapshotFixtures {
  $enabled = [byte[]](0..8)
  $enabled[8] = 1
  $disabled = [byte[]](0..8)
  $disabled[8] = 0
  $registryKey = [pscustomobject]@{
    Values = @{ Settings = $enabled; DisabledSettings = $disabled; MalformedSettings = 'not-binary' }
    Kinds = @{ Settings = 'Binary'; DisabledSettings = 'Binary'; MalformedSettings = 'String' }
  }
  Add-Member -InputObject $registryKey -MemberType ScriptMethod -Name GetValueNames -Value {
    @($this.Values.Keys)
  }
  Add-Member -InputObject $registryKey -MemberType ScriptMethod -Name GetValue -Value {
    param([string]$Name)
    return ,$this.Values[$Name]
  }
  Add-Member -InputObject $registryKey -MemberType ScriptMethod -Name GetValueKind -Value {
    param([string]$Name)
    return $this.Kinds[$Name]
  }
  $getFixtureItem = { param([string]$Path) $registryKey }
  $missing = Get-RegistryValueSnapshot -Path 'fixture:\missing' -Name 'Settings' -GetItem { $null }
  $missingValue = Get-RegistryValueSnapshot -Path 'fixture:\key' -Name 'NotPresent' -GetItem $getFixtureItem
  $enabledSnapshot = Get-RegistryValueSnapshot -Path 'fixture:\key' -Name 'Settings' -GetItem $getFixtureItem
  $disabledSnapshot = Get-RegistryValueSnapshot -Path 'fixture:\key' -Name 'DisabledSettings' -GetItem $getFixtureItem
  $malformedSnapshot = Get-RegistryValueSnapshot -Path 'fixture:\key' -Name 'MalformedSettings' -GetItem $getFixtureItem

  -not $missing.exists -and
    -not $missingValue.exists -and
    (Get-RegistrySnapshotValue $missingValue) -eq $null -and
    -not (Get-TaskbarAutoHideFromSnapshot $missingValue) -and
    $enabledSnapshot.value -is [byte[]] -and
    (Get-TaskbarAutoHideFromSnapshot $enabledSnapshot) -and
    $disabledSnapshot.value -is [byte[]] -and
    -not (Get-TaskbarAutoHideFromSnapshot $disabledSnapshot) -and
    $malformedSnapshot.value -is [string] -and
    -not (Get-TaskbarAutoHideFromSnapshot $malformedSnapshot)
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
  $policyTarget = Join-Path $targetRoot 'mac-wallpaper-policy.png'
  New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
  Copy-Item -LiteralPath $source -Destination $target -Force

  Add-Type -AssemblyName System.Drawing.Common
  $sourceImage = [Drawing.Image]::FromFile($source)
  try {
    $scale = [Math]::Min(1.0, 2560.0 / [Math]::Max($sourceImage.Width, $sourceImage.Height))
    $width = [Math]::Max(1, [int][Math]::Round($sourceImage.Width * $scale))
    $height = [Math]::Max(1, [int][Math]::Round($sourceImage.Height * $scale))
    $policyImage = [Drawing.Bitmap]::new($width, $height, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    try {
      $graphics = [Drawing.Graphics]::FromImage($policyImage)
      try {
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($sourceImage, [Drawing.Rectangle]::new(0, 0, $width, $height))
      } finally {
        $graphics.Dispose()
      }
      $policyImage.Save($policyTarget, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $policyImage.Dispose()
    }
  } finally {
    $sourceImage.Dispose()
  }

  $policyProperty = Get-ItemProperty -LiteralPath $desktopPolicyPath -Name Wallpaper -ErrorAction SilentlyContinue
  if ($policyProperty -and $policyProperty.PSObject.Properties['Wallpaper'].Value) {
    Write-Warning 'The active MDM wallpaper image will be reconciled by the privileged promotion phase.'
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

if ($SelfTestOnly) {
  if (-not (Test-ProfileSnapshotFixtures)) {
    throw 'Profile registry snapshot fixture failed.'
  }
  Write-Host 'PASS: missing, binary, and malformed profile snapshot fixtures.'
  exit 0
}

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
Remove-Item -LiteralPath $preparedPath -Force -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath $statePath)) {
  $stuckRectsSnapshot = Get-RegistryValueSnapshot $stuckRectsPath 'Settings'
  $wallpaperSnapshot = Get-RegistryValueSnapshot 'HKCU:\Control Panel\Desktop' 'Wallpaper'
  $state = [ordered]@{
    capturedAt = (Get-Date).ToString('o')
    taskbarAutoHide = Get-TaskbarAutoHideFromSnapshot $stuckRectsSnapshot
    wallpaper = Get-RegistrySnapshotValue $wallpaperSnapshot
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
  foreach ($name in 'MacMakeoverMenuBar', 'MacMakeoverMenuHost', 'MacMakeoverDock', 'MacMakeoverAwakeAndAvailable') {
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
foreach ($name in 'MacMakeoverDock', 'MacMakeoverAwakeAndAvailable') {
  if ($savedState.run.Contains($name)) { continue }
  $savedState.run[$name] = Get-RegistryValueSnapshot $runKey $name
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
    'AwakeAndAvailable.exe',
    'MacMakeover.Supervisor.exe',
    'deployment-manifest.json',
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
Stop-NativeShellTasks -DeploymentRoot $deploymentRoot
if (Test-Path -LiteralPath $deployedDock) {
  $shutdown = Start-Process -FilePath $deployedDock -ArgumentList '--shutdown' -Wait -PassThru -WindowStyle Hidden
  if ($shutdown.ExitCode -ne 0) {
    throw "Dock shutdown command failed with exit code $($shutdown.ExitCode)."
  }
  Start-Sleep -Milliseconds 500
}
Get-NativeShellCurrentSessionProcess -ProcessName @('MacMakeover.MenuBar', 'MacMakeover.MenuHost', 'MacMakeover.Dock', 'MacMakeover.Supervisor', 'AwakeAndAvailable') |
  Stop-Process -Force -ErrorAction SilentlyContinue
if ($artifactRoot -ne $deploymentRoot) {
  New-Item -ItemType Directory -Force -Path $deploymentRoot | Out-Null
  Copy-Item -Path (Join-Path $artifactRoot '*') -Destination $deploymentRoot -Recurse -Force
}

$manifestFile = Join-Path $deploymentRoot 'deployment-manifest.json'
if (-not (Test-Path -LiteralPath $manifestFile)) {
  throw 'Deployed directory is missing deployment-manifest.json.'
}
$manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json -AsHashtable
$manifestExecutables = $manifest.executables
foreach ($exeName in @('MacMakeover.MenuBar.exe', 'MacMakeover.MenuHost.exe', 'MacMakeover.Dock.exe', 'AwakeAndAvailable.exe', 'MacMakeover.Supervisor.exe')) {
  $deployedPath = Join-Path $deploymentRoot $exeName
  if (-not (Test-Path -LiteralPath $deployedPath)) {
    throw "Deployed executable missing: $exeName"
  }
  $actualHash = (Get-FileHash -LiteralPath $deployedPath -Algorithm SHA256).Hash
  $expectedHash = $manifestExecutables[$exeName]
  if ($actualHash -ne $expectedHash) {
    throw "Deployed file $exeName hash mismatch. Expected $expectedHash, got $actualHash."
  }
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
Set-MacWallpaper

if (-not (Test-Path -LiteralPath $searchKey)) { New-Item -Path $searchKey -Force | Out-Null }
foreach ($name in 'SearchboxTaskbarMode', 'SearchboxTaskbarModeCache') {
  New-ItemProperty -LiteralPath $searchKey -Name $name -Value 0 -PropertyType DWord -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $runKey)) { New-Item -Path $runKey | Out-Null }
$startupSerializeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'
if (-not (Test-Path -LiteralPath $startupSerializeKey)) {
  New-Item -Path $startupSerializeKey -Force | Out-Null
}
# Keep any remaining user startup entries responsive; native-shell startup itself is task-based.
New-ItemProperty -LiteralPath $startupSerializeKey -Name StartupDelayInMSec `
  -Value 0 -PropertyType DWord -Force | Out-Null
Register-NativeShellTasks -DeploymentRoot $deploymentRoot
foreach ($legacyRunValue in 'MacMakeoverMenuHost', 'MacMakeoverMenuBar', 'MacMakeoverDock', 'MacMakeoverAwakeAndAvailable') {
  Remove-ItemProperty -LiteralPath $runKey -Name $legacyRunValue -ErrorAction SilentlyContinue
}

$promotionRunId = [guid]::NewGuid().ToString('N')
$preparedAt = (Get-Date).ToUniversalTime().ToString('o')
$prepared = [ordered]@{
  preparedAt = $preparedAt
  promotionRunId = $promotionRunId
  deploymentRoot = $deploymentRoot
  policyWallpaper = (Join-Path $env:LOCALAPPDATA 'MacMakeover\wallpapers\mac-wallpaper-policy.png')
} | ConvertTo-Json
[System.IO.File]::WriteAllText($preparedPath, $prepared, (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'Unelevated native-shell user profile prepared.'
