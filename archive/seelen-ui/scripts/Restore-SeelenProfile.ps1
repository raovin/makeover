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
$currentSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId

function Get-CurrentSessionProcess {
  param([Parameter(Mandatory)][string[]]$ProcessName)

  @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
    Where-Object {
      try { $_.SessionId -eq $currentSessionId } catch { $false }
    })
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

if (-not $SkipElevation) {
  $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
  if (-not (Test-Path -LiteralPath $pwsh)) { $pwsh = (Get-Command powershell.exe).Source }
  $systemRollback = Join-Path $PSScriptRoot 'Restore-SeelenSystemProfile.ps1'
  $process = Start-Process -FilePath $pwsh -Verb RunAs -Wait -PassThru -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $systemRollback))
  if ($process.ExitCode -ne 0) { throw "Privileged rollback failed with exit code $($process.ExitCode)." }
}

$dock = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin\MacMakeover.Dock.exe'
foreach ($taskName in 'MacMakeover Shell - MenuHost', 'MacMakeover Shell - MenuBar', 'MacMakeover Shell - Dock', 'MacMakeover Shell - Awake', 'MacMakeover Shell - Supervisor') {
  Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath $dock) {
  $shutdown = Start-Process -FilePath $dock -ArgumentList '--shutdown' -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
  if ($shutdown -and $shutdown.ExitCode -ne 0) {
    Write-Warning "Dock shutdown command failed with exit code $($shutdown.ExitCode)."
  }
  Start-Sleep -Milliseconds 500
}
Get-CurrentSessionProcess -ProcessName @('MacMakeover.MenuBar', 'MacMakeover.MenuHost', 'MacMakeover.Dock', 'MacMakeover.Supervisor', 'AwakeAndAvailable') |
  Stop-Process -Force -ErrorAction SilentlyContinue
$remainingNativeTasks = @(Get-ScheduledTask -TaskName 'MacMakeover Shell -*' -ErrorAction SilentlyContinue)
if ($remainingNativeTasks.Count -gt 0) {
  throw "Native-shell startup tasks remain after rollback: $($remainingNativeTasks.TaskName -join ', ')"
}
$remainingNativeProcesses = @(Get-CurrentSessionProcess -ProcessName @('MacMakeover.MenuBar', 'MacMakeover.MenuHost', 'MacMakeover.Dock', 'MacMakeover.Supervisor', 'AwakeAndAvailable'))
if ($remainingNativeProcesses.Count -gt 0) {
  throw "Native-shell processes remain after rollback: $($remainingNativeProcesses.ProcessName -join ', ')"
}
Remove-ItemProperty -LiteralPath $runKey -Name MacMakeoverMenuBar, MacMakeoverMenuHost, MacMakeoverDock, MacMakeoverAwakeAndAvailable -ErrorAction SilentlyContinue

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
  $advancedState = Get-StateProperty $state 'advanced'
  if ($null -ne $advancedState) {
    foreach ($name in 'TaskbarAl', 'TaskbarDa', 'ShowTaskViewButton', 'SearchboxTaskbarMode', 'MMTaskbarEnabled') {
      Restore-RegistrySnapshot $advancedKey $name (Get-StateProperty $advancedState $name)
    }
  }
  $searchState = Get-StateProperty $state 'search'
  if ($null -ne $searchState) {
    foreach ($name in 'SearchboxTaskbarMode', 'SearchboxTaskbarModeCache') {
      Restore-RegistrySnapshot $searchKey $name (Get-StateProperty $searchState $name)
    }
  }
  if ([bool](Get-StateProperty $state 'taskbarAutoHide')) {
    $settings = (Get-ItemProperty -LiteralPath $stuckRectsPath -ErrorAction SilentlyContinue).Settings
    if ($settings -and $settings.Length -gt 8) {
      $settings[8] = [byte]($settings[8] -bor 1)
      Set-ItemProperty -LiteralPath $stuckRectsPath -Name Settings -Value $settings
    }
  }
  $savedWallpaper = [string](Get-StateProperty $state 'wallpaper')
  if (-not [string]::IsNullOrWhiteSpace($savedWallpaper) -and (Test-Path -LiteralPath $savedWallpaper)) {
    Get-ChildItem -LiteralPath $virtualDesktopsPath -ErrorAction SilentlyContinue | ForEach-Object {
      Set-ItemProperty -LiteralPath $_.PSPath -Name Wallpaper -Value $savedWallpaper -Type String
    }
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class RestoredUserWallpaper {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern bool SystemParametersInfo(int action, int parameter, string path, int flags);
}
'@
    [void][RestoredUserWallpaper]::SystemParametersInfo(20, 0, $savedWallpaper, 3)
  }
}

& (Join-Path $repoRoot 'scripts\install-hot-corners.ps1') -StartNow
Get-CurrentSessionProcess -ProcessName 'explorer' | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (-not (Get-CurrentSessionProcess -ProcessName 'explorer')) { Start-Process explorer.exe }
Remove-Item -LiteralPath (Join-Path $stateRoot 'user-profile-prepared.json'), (Join-Path $stateRoot 'system-profile-enabled.json') -Force -ErrorAction SilentlyContinue
Write-Host 'Previous Seelen session restored.'
