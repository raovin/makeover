[CmdletBinding()]
param(
  [switch]$SkipAutostart,
  [switch]$KeepSeelenInstalled = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceConfig = Join-Path $repoRoot 'config\yasb'
$targetConfig = Join-Path $env:USERPROFILE '.config\yasb'
$yasbc = Join-Path $env:ProgramFiles 'YASB\yasbc.exe'
$stateRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration'
$statePath = Join-Path $stateRoot 'native-shell-state.json'
$seelenTaskPath = '\Seelen\'
$seelenTaskName = 'Seelen UI Service'
$stuckRectsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
$stuckRects = (Get-ItemProperty -LiteralPath $stuckRectsPath -ErrorAction SilentlyContinue).Settings
$taskbarAutoHide = [bool]($stuckRects -and $stuckRects.Length -gt 8 -and (($stuckRects[8] -band 1) -eq 1))

if (-not (Test-Path -LiteralPath $yasbc)) {
  throw "YASB is not installed: $yasbc"
}

New-Item -ItemType Directory -Force -Path $targetConfig, $stateRoot | Out-Null

$seelenTask = Get-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction SilentlyContinue
$state = [ordered]@{
  capturedAt = (Get-Date).ToString('o')
  seelenTaskExisted = [bool]$seelenTask
  seelenTaskEnabled = [bool]($seelenTask -and $seelenTask.State -ne 'Disabled')
  keepSeelenInstalled = [bool]$KeepSeelenInstalled
  taskbarAutoHide = $taskbarAutoHide
}
$state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM

& $yasbc stop 2>$null

# Wait for the old appbar to release its shell registration before replacing
# files. This avoids a duplicate YASB instance and an unstable work area.
$yasbDeadline = (Get-Date).AddSeconds(15)
while ((Get-Process yasb -ErrorAction SilentlyContinue) -and (Get-Date) -lt $yasbDeadline) {
  Start-Sleep -Milliseconds 250
}
if (Get-Process yasb -ErrorAction SilentlyContinue) {
  throw 'YASB did not stop cleanly within 15 seconds.'
}

Copy-Item -LiteralPath (Join-Path $sourceConfig 'config.yaml') -Destination (Join-Path $targetConfig 'config.yaml') -Force
Copy-Item -LiteralPath (Join-Path $sourceConfig '.env') -Destination (Join-Path $targetConfig '.env') -Force
Copy-Item -LiteralPath (Join-Path $sourceConfig 'assets') -Destination $targetConfig -Recurse -Force

$style = Get-Content -LiteralPath (Join-Path $sourceConfig 'styles.css') -Raw
$appleMark = (Join-Path $targetConfig 'assets\apple-mark.svg').Replace('\', '/')
$style = $style.Replace('__YASB_APPLE_MARK__', $appleMark)
[System.IO.File]::WriteAllText(
  (Join-Path $targetConfig 'styles.css'),
  $style,
  [System.Text.UTF8Encoding]::new($false)
)

# The old click-routing helper was built around Seelen's Tauri windows. It must not
# poll or synthesize clicks once the native-shell profile owns the desktop.
& (Join-Path $PSScriptRoot 'stop-hot-corners.ps1')

if ($seelenTask) {
  try {
    Stop-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath $seelenTaskPath -TaskName $seelenTaskName -ErrorAction Stop | Out-Null
  } catch {
    Write-Warning 'Seelen scheduled task needs elevation to disable. Its processes are stopped now; disable the task once from an elevated shell for a permanent switch.'
  }
}

Get-Process seelen-ui, slu-service -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeTaskbarVisibility {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr FindWindow(string className, string windowName);
  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr window, int command);
  [StructLayout(LayoutKind.Sequential)]
  public struct APPBARDATA {
    public uint cbSize;
    public IntPtr hWnd;
    public uint uCallbackMessage;
    public uint uEdge;
    public RECT rc;
    public IntPtr lParam;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int left, top, right, bottom; }
  [DllImport("shell32.dll")]
  public static extern UIntPtr SHAppBarMessage(uint message, ref APPBARDATA data);
  public static void DisableAutoHide() {
    var data = new APPBARDATA();
    data.cbSize = (uint)Marshal.SizeOf(data);
    data.lParam = (IntPtr)2; // ABS_ALWAYSONTOP, without ABS_AUTOHIDE.
    SHAppBarMessage(10, ref data); // ABM_SETSTATE
  }
}
'@
$taskbar = [NativeTaskbarVisibility]::FindWindow('Shell_TrayWnd', $null)
if ($taskbar -ne [IntPtr]::Zero) {
  [NativeTaskbarVisibility]::ShowWindow($taskbar, 5) | Out-Null
}

if ($stuckRects -and $stuckRects.Length -gt 8) {
  $stuckRects[8] = [byte]($stuckRects[8] -band 0xFE)
  Set-ItemProperty -LiteralPath $stuckRectsPath -Name Settings -Value $stuckRects
}
[NativeTaskbarVisibility]::DisableAutoHide()

if (-not $SkipAutostart) {
  & $yasbc enable-autostart
}

& (Join-Path $PSScriptRoot 'Install-AppleMenuHandler.ps1')
& (Join-Path $PSScriptRoot 'Install-MacControlCenterHandler.ps1')
& (Join-Path $PSScriptRoot 'Install-MacNetworkHandler.ps1')
& (Join-Path $PSScriptRoot 'Install-MacBluetoothHandler.ps1')

$menuHost = Join-Path $repoRoot 'tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe'
if (Test-Path -LiteralPath $menuHost) {
  if (-not (Get-Process MacMakeover.MenuHost -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $menuHost -WindowStyle Hidden
  }
}

& $yasbc start
Write-Host 'Native-shell profile enabled: YASB top bar + Windows taskbar + native Windows switching.'
Write-Host "Rollback: $PSScriptRoot\Restore-SeelenProfile.ps1"
