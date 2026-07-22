#Requires -RunAsAdministrator
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path $env:LOCALAPPDATA 'MacMakeover'
$managedWallpaper = Join-Path $root 'wallpapers\mac-wallpaper.jpg'
$managedPolicyWallpaper = Join-Path $root 'wallpapers\mac-wallpaper-policy.png'
$logPath = Join-Path $root 'wallpaper-guard.log'
$desktopPolicyPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\System'
$desktopPath = 'Registry::HKEY_CURRENT_USER\Control Panel\Desktop'
$allowedWallpaperRoot = [IO.Path]::GetFullPath((Join-Path $env:WINDIR 'web\wallpaper'))

function Write-GuardLog([string]$Message) {
  [IO.File]::AppendAllText(
    $logPath,
    ('{0:o} {1}{2}' -f (Get-Date), $Message, [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false))
}

try {
  if (-not (Test-Path -LiteralPath $managedWallpaper) -or
      -not (Test-Path -LiteralPath $managedPolicyWallpaper)) {
    throw 'Managed wallpaper assets are missing.'
  }

  $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $policyManagerCurrentPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\current\$userSid\ADMX_Desktop"
  $policyManagerCurrent = Get-ItemProperty -LiteralPath $policyManagerCurrentPath -ErrorAction SilentlyContinue
  $providerPath = $null
  $policyTarget = Join-Path $env:WINDIR 'web\wallpaper\DesktopPreto.png'
  if ($policyManagerCurrent -and $policyManagerCurrent.Wallpaper_ADMXInstanceData) {
    $providerPath = "Registry::HKEY_LOCAL_MACHINE\$([string]$policyManagerCurrent.Wallpaper_ADMXInstanceData)"
    $provider = Get-ItemProperty -LiteralPath $providerPath -ErrorAction Stop
    if ([string]$provider.Wallpaper -match 'WallpaperName" value="([^"]+)"') {
      $policyTarget = $Matches[1]
    }
  }

  $policyTarget = [IO.Path]::GetFullPath($policyTarget)
  if (-not $policyTarget.StartsWith($allowedWallpaperRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to repair an MDM wallpaper outside $allowedWallpaperRoot"
  }

  $changed = $false
  $managedHash = (Get-FileHash -LiteralPath $managedPolicyWallpaper -Algorithm SHA256).Hash
  if (-not (Test-Path -LiteralPath $policyTarget) -or
      (Get-FileHash -LiteralPath $policyTarget -Algorithm SHA256).Hash -ne $managedHash) {
    Copy-Item -LiteralPath $managedPolicyWallpaper -Destination $policyTarget -Force
    $changed = $true
  }

  # ADMX Desktop Wallpaper uses 4 for CropToFit/Fill. The ordinary desktop
  # registry uses 10 for the same visual mode.
  $providerValue = '<enabled/><data id="WallpaperName" value="{0}" /><data id="WallpaperStyle" value="4" />' -f $policyTarget
  if ($providerPath) {
    $provider = Get-ItemProperty -LiteralPath $providerPath -ErrorAction Stop
    if ([string]$provider.Wallpaper -ne $providerValue) {
      Set-ItemProperty -LiteralPath $providerPath -Name Wallpaper -Value $providerValue -Type String
      $changed = $true
    }
  }

  New-Item -ItemType Directory -Force -Path $desktopPolicyPath | Out-Null
  $policy = Get-ItemProperty -LiteralPath $desktopPolicyPath -ErrorAction SilentlyContinue
  if (-not $policy -or [string]$policy.Wallpaper -ne $policyTarget -or [string]$policy.WallpaperStyle -ne '4') {
    New-ItemProperty -LiteralPath $desktopPolicyPath -Name Wallpaper -Value $policyTarget -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $desktopPolicyPath -Name WallpaperStyle -Value '4' -PropertyType String -Force | Out-Null
    $changed = $true
  }

  Set-ItemProperty -LiteralPath $desktopPath -Name WallPaper -Value $managedWallpaper
  Set-ItemProperty -LiteralPath $desktopPath -Name WallpaperStyle -Value '10'
  Set-ItemProperty -LiteralPath $desktopPath -Name TileWallpaper -Value '0'

  Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class NativeWallpaperRefresh {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(int action, int param, string value, int flags);
}
'@
  if (-not [NativeWallpaperRefresh]::SystemParametersInfo(20, 0, $managedWallpaper, 3)) {
    throw "Wallpaper refresh failed with Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
  }

  if ($changed) { Write-GuardLog 'Reconciled managed wallpaper policy to Fill.' }
}
catch {
  Write-GuardLog "ERROR: $($_.Exception.Message)"
  throw
}
