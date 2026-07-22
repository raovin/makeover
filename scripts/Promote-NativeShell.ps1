[CmdletBinding()]
param(
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run Promote-NativeShell.ps1 from a normal PowerShell session, not an administrator window.'
}

function Restore-InteractiveNativeShell {
  $deploymentRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin'
  $dock = Join-Path $deploymentRoot 'MacMakeover.Dock.exe'
  if (Test-Path -LiteralPath $dock) {
    Start-Process -FilePath $dock -ArgumentList '--shutdown' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
  }

  Get-Process MacMakeover.MenuBar, MacMakeover.MenuHost, MacMakeover.Dock, AwakeAndAvailable -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

  # Explorer owns the AppBar registry. Restarting it removes reservations left by a
  # process stopped for deployment before UAC was cancelled or failed.
  Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
  Start-Sleep -Seconds 4

  foreach ($entry in @(
      @{ Name = 'MacMakeover.MenuHost'; File = 'MacMakeover.MenuHost.exe' },
      @{ Name = 'MacMakeover.MenuBar'; File = 'MacMakeover.MenuBar.exe' },
      @{ Name = 'MacMakeover.Dock'; File = 'MacMakeover.Dock.exe' },
      @{ Name = 'AwakeAndAvailable'; File = 'AwakeAndAvailable.exe' }
    )) {
    $path = Join-Path $deploymentRoot $entry.File
    if ((Test-Path -LiteralPath $path) -and -not (Get-Process -Name $entry.Name -ErrorAction SilentlyContinue)) {
      Start-Process -FilePath $path -WindowStyle Hidden
      Start-Sleep -Milliseconds 500
    }
  }
  Start-Sleep -Seconds 5
}

try {
  & (Join-Path $PSScriptRoot 'Prepare-NativeShellUserProfile.ps1') -SkipBuild:$SkipBuild
  & (Join-Path $PSScriptRoot 'Test-NativeShellPreflight.ps1')
  & (Join-Path $PSScriptRoot 'Request-NativeShellPromotion.ps1')
  & (Join-Path $PSScriptRoot 'Complete-NativeShellPromotion.ps1')
}
catch {
  $promotionError = $_
  Write-Warning 'Native-shell promotion failed; restoring the interactive shell before returning the error.'
  try { Restore-InteractiveNativeShell }
  catch { Write-Warning "Interactive-shell recovery also failed: $($_.Exception.Message)" }
  throw $promotionError
}
