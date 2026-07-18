[CmdletBinding()]
param(
  [string]$DeploymentRoot = (Join-Path $env:LOCALAPPDATA 'MacMakeover\bin'),
  [switch]$SkipDownloadCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$repoRoot = Split-Path -Parent $PSScriptRoot
foreach ($required in @(
    (Join-Path $DeploymentRoot 'MacMakeover.MenuBar.exe'),
    (Join-Path $DeploymentRoot 'MacMakeover.MenuHost.exe'),
    (Join-Path $DeploymentRoot 'MacMakeover.Dock.exe'),
    (Join-Path $DeploymentRoot 'native-taskbar-pins.json'),
    (Join-Path $DeploymentRoot 'Assets\apple-mark.png'),
    (Join-Path $DeploymentRoot 'Assets\Fonts\Manrope-Regular.ttf'),
    (Join-Path $DeploymentRoot 'Assets\Fonts\Manrope-SemiBold.ttf'),
    (Join-Path $DeploymentRoot 'Assets\Fonts\JetBrainsMono-Medium.ttf'),
    (Join-Path $DeploymentRoot 'Assets\Fonts\OFL-Manrope.txt'),
    (Join-Path $DeploymentRoot 'Assets\Fonts\OFL-JetBrainsMono.txt'),
    (Join-Path $repoRoot 'assets\wallpapers\mac-wallpaper.jpg')
  )) {
  if (-not (Test-Path -LiteralPath $required)) {
    $failures.Add("Missing preflight dependency: $required")
  }
}

$scriptNames = @(
  'Build-NativeShell.ps1',
  'Capture-Desktop.ps1',
  'install-apps.ps1',
  'Install-NativeDock.ps1',
  'Prepare-NativeShellUserProfile.ps1',
  'Promote-NativeShell.ps1',
  'Request-NativeShellPromotion.ps1',
  'Switch-To-NativeShell.ps1',
  'Invoke-NativeShellPromotion.ps1',
  'Complete-NativeShellPromotion.ps1',
  'Test-NativeShellProfile.ps1',
  'verify.ps1'
)
foreach ($scriptName in $scriptNames) {
  $scriptPath = Join-Path $PSScriptRoot $scriptName
  $tokens = $null
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors)
  foreach ($parseError in $parseErrors) {
    $failures.Add("PowerShell parse error in ${scriptName}: $($parseError.Message)")
  }
}

foreach ($elevatedScript in @('Switch-To-NativeShell.ps1', 'Invoke-NativeShellPromotion.ps1')) {
  $firstLine = Get-Content -LiteralPath (Join-Path $PSScriptRoot $elevatedScript) -TotalCount 1
  if ($firstLine -ne '#Requires -RunAsAdministrator') {
    $failures.Add("$elevatedScript is missing its elevation guard.")
  }
}

foreach ($userScript in @('Prepare-NativeShellUserProfile.ps1', 'Complete-NativeShellPromotion.ps1')) {
  $firstLine = Get-Content -LiteralPath (Join-Path $PSScriptRoot $userScript) -TotalCount 1
  if ($firstLine -eq '#Requires -RunAsAdministrator') {
    $failures.Add("$userScript must run in the unelevated user token.")
  }
}

$menuBarSource = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\MacMakeover.MenuBar\MenuBarForm.cs') -Raw
$menuBarProgramSource = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\MacMakeover.MenuBar\Program.cs') -Raw
$nativeSource = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\MacMakeover.MenuBar\NativeMethods.cs') -Raw
if ($menuBarSource -match 'EnsureNativeDockZOrder|MonitorNativeDockAsync' -or
    $nativeSource -match 'IsBorderlessFullscreen|FindTaskbarFor') {
  $failures.Add('A taskbar z-order monitor is present; Explorer must own dock z-order.')
}
$displaySubscription = $menuBarProgramSource.IndexOf('SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;', [StringComparison]::Ordinal)
$initialBarBuild = $menuBarProgramSource.IndexOf('RebuildBars();', [StringComparison]::Ordinal)
if ($displaySubscription -lt 0 -or $initialBarBuild -lt 0 -or $displaySubscription -gt $initialBarBuild) {
  $failures.Add('MenuBar must subscribe to display changes before its initial screen enumeration.')
}

$dockSource = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\MacMakeover.Dock\Program.cs') -Raw
if ($dockSource -notmatch 'WsExNoActivate' -or $dockSource -notmatch 'WsExToolWindow') {
  $failures.Add('Dock must remain a non-activating tool window and stay out of Alt+Tab.')
}
if ($dockSource -notmatch 'SlotWidth = 44' -or $dockSource -notmatch 'IconSize = 28') {
  $failures.Add('Dock no longer uses the approved icon and slot geometry.')
}
if ($dockSource -notmatch 'LogicalGap = 8' -or
    $dockSource -notmatch 'SHAppBarMessage\(NativeMethods\.AbmNew' -or
    $dockSource -notmatch 'SHAppBarMessage\(NativeMethods\.AbmRemove') {
  $failures.Add('Dock no longer owns the approved reversible 8 px work-area gap reservation.')
}
if ($dockSource -match 'RegisterHotKey|SetWindowsHookEx') {
  $failures.Add('Dock must not own global keyboard hooks.')
}

$hostPath = Join-Path $DeploymentRoot 'MacMakeover.MenuHost.exe'
if (Test-Path -LiteralPath $hostPath) {
  $hostSelfTest = $null
  foreach ($attempt in 1..3) {
    $hostSelfTest = Start-Process -FilePath $hostPath -ArgumentList '--self-test' `
      -Wait -PassThru -WindowStyle Hidden
    if ($hostSelfTest.ExitCode -eq 0) { break }
    Start-Sleep -Milliseconds 400
  }
  if ($hostSelfTest.ExitCode -ne 0) {
    $failures.Add("MenuHost Core Audio self-test failed after three attempts with exit code $($hostSelfTest.ExitCode).")
  }
}

$dockPath = Join-Path $DeploymentRoot 'MacMakeover.Dock.exe'
if (Test-Path -LiteralPath $dockPath) {
  $dockSelfTest = Start-Process -FilePath $dockPath -ArgumentList '--self-test' `
    -Wait -PassThru -WindowStyle Hidden
  if ($dockSelfTest.ExitCode -ne 0) {
    $failures.Add("Dock manifest/icon self-test failed with exit code $($dockSelfTest.ExitCode).")
  }
}

$nativePins = @(Get-ChildItem -LiteralPath "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar" `
  -Filter '*.lnk' -ErrorAction SilentlyContinue)
if ($nativePins.Count -lt 10) {
  $warnings.Add("Only $($nativePins.Count) native taskbar shortcuts were found.")
}

Add-Type -AssemblyName System.Windows.Forms
$screens = [Windows.Forms.Screen]::AllScreens
foreach ($screen in $screens) {
  Write-Host ("Display {0}: {1}x{2} at {3},{4}; work area {5}x{6}" -f `
      $screen.DeviceName,
      $screen.Bounds.Width,
      $screen.Bounds.Height,
      $screen.Bounds.Left,
      $screen.Bounds.Top,
      $screen.WorkingArea.Width,
      $screen.WorkingArea.Height)
}

foreach ($warning in $warnings) { Write-Warning $warning }
if ($failures.Count) {
  foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
  exit 1
}

Write-Host ("PASS: native-shell preflight is ready. {0} display(s); {1} native pinned shortcuts." -f `
    $screens.Count,
    $nativePins.Count)
