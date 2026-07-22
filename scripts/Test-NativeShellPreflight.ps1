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

$wallpaperAsset = Join-Path $repoRoot 'assets\wallpapers\mac-wallpaper.jpg'
$wallpaperHash = 'D228004F1A1DD90FA49EF04C7799AD80D98E6B19CC1C7CF28C7D484B86A8759D'
if ((Test-Path -LiteralPath $wallpaperAsset) -and
    (Get-FileHash -LiteralPath $wallpaperAsset -Algorithm SHA256).Hash -ne $wallpaperHash) {
  $failures.Add('The managed wallpaper is not the archived Seelen Big Sur (Day) asset.')
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
  'Repair-NativeWallpaperPolicy.ps1',
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
$systemStateSource = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\MacMakeover.MenuBar\SystemState.cs') -Raw
$switchSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Switch-To-NativeShell.ps1') -Raw
$menuHostSource = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\MacMakeover.MenuHost\Program.cs') -Raw
$buildSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Build-NativeShell.ps1') -Raw
$promoteSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Promote-NativeShell.ps1') -Raw
$prepareSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Prepare-NativeShellUserProfile.ps1') -Raw
$completeSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Complete-NativeShellPromotion.ps1') -Raw
$profileSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-NativeShellProfile.ps1') -Raw
$pinTestSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-NativeTaskbarPins.ps1') -Raw
$nativeSource = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\MacMakeover.MenuBar\NativeMethods.cs') -Raw
if ($buildSource -notmatch 'MacMakeover\\native-shell-build') {
  $failures.Add('The standalone build must default to staging and must not overwrite the running shell.')
}
if ($menuBarSource -match 'EnsureNativeDockZOrder|MonitorNativeDockAsync' -or
    $nativeSource -match 'IsBorderlessFullscreen|FindTaskbarFor') {
  $failures.Add('A taskbar z-order monitor is present; Explorer must own dock z-order.')
}
if ($menuBarSource -notmatch '_screen\.Primary \? 1F : 1\.5F' -or
    $menuBarSource -notmatch 'opticalScale = 1F \+ \(\(VisualScale / DpiScale\) - 1F\) \* 0\.3F' -or
    $menuBarProgramSource -notmatch '--preview-all') {
  $failures.Add('MenuBar no longer keeps external-monitor geometry and typography at physical parity with the laptop.')
}
if ($nativeSource -notmatch 'PowerGetUserConfiguredACPowerMode' -or
    $nativeSource -notmatch 'PowerGetUserConfiguredDCPowerMode' -or
    $systemStateSource -notmatch 'BatteryChargeStatus\.Charging' -or
    $menuBarSource -notmatch 'High performance' -or
    $menuBarProgramSource -notmatch '--preview-power=') {
  $failures.Add('MenuBar no longer distinguishes power source, charging state, and Windows power mode.')
}
if ($menuBarSource -match '\\u26A1' -or
    $menuBarSource -notmatch 'ShowsExternalPowerIndicator\(snapshot\)' -or
    $menuBarSource -notmatch 'ShowsExternalPowerIndicator\(SystemSnapshot snapshot\) => snapshot\.OnAcPower' -or
    $menuBarSource -notmatch 'DrawExternalPowerBolt') {
  $failures.Add('MenuBar no longer shows a separate vector power indicator whenever AC is connected.')
}
if ($menuBarSource -notmatch 'LogicalCornerHitSize = 8' -or
    $menuBarSource -notmatch 'IsShowDesktopCorner\(e\.Location') {
  $failures.Add('MenuBar no longer preserves the Seelen-sized Show Desktop corner hit target.')
}
if ($menuBarSource -notmatch 'ReassertAppBarAfterStartupAsync' -or
    $menuBarSource -notmatch 'foreach \(var delay in new\[\] \{ 1000, 4000 \}\)') {
  $failures.Add('MenuBar no longer reasserts its AppBar work area after restored windows settle at login.')
}
if ($systemStateSource -notmatch '"notepad" => "Notepad"' -or
    $systemStateSource -notmatch '_ => executableDescription' -or
    $systemStateSource -notmatch 'ReadExecutableDescription\(process\)') {
  $failures.Add('MenuBar active-app identity has regressed to document-window titles instead of executable application names.')
}
if ($prepareSource -match '\$savedState(?:\.run)?\.ContainsKey\(') {
  $failures.Add('Profile preparation uses Hashtable-only ContainsKey on ConvertFrom-Json ordered dictionaries.')
}
if ($completeSource -notmatch 'foreach \(\$attempt in 1\.\.4\)' -or
    $completeSource -notmatch '\$profileScript 2>&1' -or
    $completeSource -notmatch '\$profilePassed') {
  $failures.Add('Native-shell completion can report acceptance after a failed live-profile check.')
}
if ($profileSource -match '\.Verbs\(' -or $pinTestSource -match '\.Verbs\(' -or
    $profileSource -notmatch 'User Pinned\\TaskBar' -or $pinTestSource -notmatch 'User Pinned\\TaskBar') {
  $failures.Add('Pin verification can block on Shell verb enumeration instead of using Taskband and pinned shortcuts.')
}
if ($profileSource -notmatch "Write-Host \('PASS: native shell is coherent[\s\S]*?exit 0") {
  $failures.Add('A passing live-profile check does not explicitly return exit code zero.')
}
if ($promoteSource -notmatch 'Restore-InteractiveNativeShell' -or
    $promoteSource -notmatch 'Get-Process explorer.*Stop-Process' -or
    $promoteSource -notmatch 'Native-shell promotion failed; restoring the interactive shell') {
  $failures.Add('Promotion no longer restores Explorer and the native shell after cancellation or failure.')
}
if ($switchSource -notmatch 'policyWallpaperManagedHash' -or
    $switchSource -notmatch 'WallpaperStyle.*value=.*4' -or
    $switchSource -notmatch 'policyManagerProviderPath' -or
    $switchSource -notmatch 'MacMakeover Wallpaper Guard' -or
    $switchSource -notmatch 'hot-corners-startup\.lnk' -or
    $prepareSource -notmatch 'mac-wallpaper-policy\.png' -or
    $prepareSource -notmatch 'virtualDesktopsPath') {
  $failures.Add('Wallpaper deployment no longer reconciles the MDM target/provider or updates virtual desktops.')
}
$wallpaperRepairSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Repair-NativeWallpaperPolicy.ps1') -Raw
if ($wallpaperRepairSource -notmatch 'public static class NativeWallpaperRefresh' -or
    $wallpaperRepairSource -notmatch 'public static extern bool SystemParametersInfo' -or
    $wallpaperRepairSource -notmatch 'WallpaperStyle" value="4"') {
  $failures.Add('Wallpaper repair no longer exposes its Win32 refresh type or preserves ADMX Fill mode.')
}
if ($switchSource -notmatch 'windhawkUiTaskWasEnabled') {
  $failures.Add('Privileged promotion no longer preserves the Windhawk UI task rollback state.')
}
$displaySubscription = $menuBarProgramSource.IndexOf('SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;', [StringComparison]::Ordinal)
$initialBarBuild = $menuBarProgramSource.IndexOf('RebuildBars();', [StringComparison]::Ordinal)
if ($displaySubscription -lt 0 -or $initialBarBuild -lt 0 -or $displaySubscription -gt $initialBarBuild) {
  $failures.Add('MenuBar must subscribe to display changes before its initial screen enumeration.')
}
if ($menuHostSource -notmatch 'PowerLineStatus\.Online && pct < 100') {
  $failures.Add('MenuHost charging state can disagree with the menu-bar battery state at 100 percent.')
}

$dockSource = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\MacMakeover.Dock\Program.cs') -Raw
$workAreaSource = [regex]::Match(
  $dockSource,
  'internal sealed class WorkAreaGapForm[\s\S]*?(?=internal sealed class DockForm)'
).Value
if ($dockSource -notmatch 'WsExNoActivate' -or $dockSource -notmatch 'WsExToolWindow') {
  $failures.Add('Dock must remain a non-activating tool window and stay out of Alt+Tab.')
}
if ($dockSource -notmatch 'SlotWidth = 44' -or $dockSource -notmatch 'IconSize = 28') {
  $failures.Add('Dock no longer uses the approved icon and slot geometry.')
}
if ($dockSource -notmatch 'screen\.Primary \? 1F : 1\.5F' -or
    $dockSource -notmatch 'app\.LoadIcon\(iconSize \* 3\)' -or
    $dockSource -notmatch 'if \(AppId is not null\)' -or
    $dockSource -notmatch 'CopyShellBitmap' -or
    $dockSource -notmatch 'Format32bppPArgb' -or
    $dockSource -notmatch '--preview-all') {
  $failures.Add('Dock no longer keeps both displays at physical parity with high-resolution packaged icons.')
}
if ($dockSource -match 'FillPath\(hover' -or $dockSource -match 'new SolidBrush\(Color\.FromArgb\(32, 255, 255, 255\)\)') {
  $failures.Add('Dock hover styling reintroduced an opaque-looking rectangular tile.')
}
if ($dockSource -match 'FlowLayoutPanel' -or $dockSource -match 'class DockButton : Control') {
  $failures.Add('Dock icons are child controls again; WinForms transparency creates black slot backgrounds.')
}
if ($dockSource -match 'AutoScaleMode = AutoScaleMode\.Dpi') {
  $failures.Add('Dock manually scaled forms must not be scaled a second time by WinForms DPI autoscaling.')
}
if ($dockSource -notmatch 'displayEdge = Screen\.AllScreens' -or
    $dockSource -notmatch 'Math\.Min\(1d, displayEdge') {
  $failures.Add('Dock wallpaper loading must retain a display-sized copy instead of decoding the full source image.')
}
if ($dockSource -notmatch 'NativeMethods\.HwndBottom' -or
    $dockSource -notmatch 'TopMost = false') {
  $failures.Add('The work-area reservation window can cover the enlarged external dock instead of staying behind it.')
}
if ($dockSource -notmatch '--export-icons' -or $dockSource -notmatch '--preview-hover') {
  $failures.Add('Dock no longer exposes the icon-export and hover-preview paths used by visual release QA.')
}
if ($dockSource -notmatch 'LogicalGap = 8' -or
    $dockSource -notmatch 'var gap = visualDockHeight \+ \(int\)Math\.Round\(LogicalGap \* visualScale\)' -or
    $dockSource -match 'visualDockHeight - nativeDockHeight' -or
    $dockSource -notmatch 'SHAppBarMessage\(NativeMethods\.AbmNew' -or
    $dockSource -notmatch 'SHAppBarMessage\(NativeMethods\.AbmRemove' -or
    $dockSource -notmatch 'NativeMethods\.AbnPosChanged' -or
    $dockSource -notmatch 'RegisterWindowMessage\("TaskbarCreated"\)' -or
    $dockSource -notmatch 'expectedReservation' -or
    $dockSource -notmatch '_remainingSettleAttempts = 20' -or
    $dockSource -notmatch 'gapForm\.EnsureReserved\(\)') {
  $failures.Add('Dock no longer owns the approved reversible 8 px work-area gap reservation.')
}
if ($dockSource -notmatch 'dispatcher\.InvokeRequired' -or
    $dockSource -notmatch 'Interlocked\.Exchange\(ref _displayRebuildPending') {
  $failures.Add('Dock display changes are no longer marshalled and deduplicated on the UI thread.')
}
if ($dockSource -match 'class DockBackdropForm' -or
    $workAreaSource -notmatch 'ReservationAnchorSize = 1' -or
    $workAreaSource -notmatch 'Opacity = 0' -or
    $workAreaSource -match 'WallpaperSlice\.Draw' -or
    $workAreaSource -notmatch 'data\.Bounds\.Left,\s*data\.Bounds\.Bottom - ReservationAnchorSize,\s*ReservationAnchorSize,\s*ReservationAnchorSize' -or
    $dockSource -notmatch 'WsExLayered' -or
    $dockSource -notmatch 'WsExTransparent' -or
    $dockSource -notmatch 'Region = new Region\(path\)' -or
    $dockSource -notmatch '_frame\.Width <= 0') {
  $failures.Add('Dock reservation must use a nonpainting 1 px anchor and leave the real desktop visible around the rounded frame.')
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

$menuBarPath = Join-Path $DeploymentRoot 'MacMakeover.MenuBar.exe'
if (Test-Path -LiteralPath $menuBarPath) {
  $menuBarSelfTest = Start-Process -FilePath $menuBarPath -ArgumentList '--self-test' `
    -Wait -PassThru -WindowStyle Hidden
  if ($menuBarSelfTest.ExitCode -ne 0) {
    $failures.Add("MenuBar power-state self-test failed with exit code $($menuBarSelfTest.ExitCode).")
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
