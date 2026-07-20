[CmdletBinding()]
param(
  [switch]$SkipElevation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this rollback entry point from a normal PowerShell session.'
}

$stateRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration'
$statePath = Join-Path $stateRoot 'native-shell-state.json'
$virtualDesktopsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops\Desktops'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$advancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$searchKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$stuckRectsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'

if (-not $SkipElevation) {
  $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
  if (-not (Test-Path -LiteralPath $pwsh)) { $pwsh = (Get-Command powershell.exe).Source }
  $systemRollback = Join-Path $PSScriptRoot 'Restore-SeelenSystemProfile.ps1'
  $process = Start-Process -FilePath $pwsh -Verb RunAs -Wait -PassThru -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $systemRollback))
  if ($process.ExitCode -ne 0) { throw "Privileged rollback failed with exit code $($process.ExitCode)." }
}

$dock = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin\MacMakeover.Dock.exe'
if (Test-Path -LiteralPath $dock) {
  Start-Process -FilePath $dock -ArgumentList '--shutdown' -Wait -WindowStyle Hidden
  Start-Sleep -Milliseconds 500
}
Get-Process MacMakeover.MenuBar, MacMakeover.MenuHost, MacMakeover.Dock -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -LiteralPath $runKey -Name MacMakeoverMenuBar, MacMakeoverMenuHost, MacMakeoverDock -ErrorAction SilentlyContinue

function Restore-RegistrySnapshot([string]$Path, [string]$Name, $Snapshot) {
  if ($null -eq $Snapshot) { return }
  if (-not $Snapshot.exists) {
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    return
  }
  $kind = if ($Snapshot.kind) { [string]$Snapshot.kind } else { 'String' }
  New-ItemProperty -LiteralPath $Path -Name $Name -Value $Snapshot.value -PropertyType $kind -Force | Out-Null
}

if (Test-Path -LiteralPath $statePath) {
  $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
  if ($state.PSObject.Properties.Name -contains 'advanced') {
    foreach ($name in 'TaskbarAl', 'TaskbarDa', 'ShowTaskViewButton', 'SearchboxTaskbarMode', 'MMTaskbarEnabled') {
      Restore-RegistrySnapshot $advancedKey $name $state.advanced.$name
    }
  }
  if ($state.PSObject.Properties.Name -contains 'search') {
    foreach ($name in 'SearchboxTaskbarMode', 'SearchboxTaskbarModeCache') {
      Restore-RegistrySnapshot $searchKey $name $state.search.$name
    }
  }
  if ($state.taskbarAutoHide) {
    $settings = (Get-ItemProperty -LiteralPath $stuckRectsPath -ErrorAction SilentlyContinue).Settings
    if ($settings -and $settings.Length -gt 8) {
      $settings[8] = [byte]($settings[8] -bor 1)
      Set-ItemProperty -LiteralPath $stuckRectsPath -Name Settings -Value $settings
    }
  }
  if ($state.wallpaper -and (Test-Path -LiteralPath $state.wallpaper)) {
    Get-ChildItem -LiteralPath $virtualDesktopsPath -ErrorAction SilentlyContinue | ForEach-Object {
      Set-ItemProperty -LiteralPath $_.PSPath -Name Wallpaper -Value ([string]$state.wallpaper) -Type String
    }
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class RestoredUserWallpaper {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern bool SystemParametersInfo(int action, int parameter, string path, int flags);
}
'@
    [void][RestoredUserWallpaper]::SystemParametersInfo(20, 0, [string]$state.wallpaper, 3)
  }
}

& (Join-Path $repoRoot 'scripts\install-hot-corners.ps1') -StartNow
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
Remove-Item -LiteralPath (Join-Path $stateRoot 'user-profile-prepared.json'), (Join-Path $stateRoot 'system-profile-enabled.json') -Force -ErrorAction SilentlyContinue
Write-Host 'Previous Seelen session restored.'
