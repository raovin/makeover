[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$repoRoot = Split-Path -Parent $PSScriptRoot
$deploymentRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin'
$modConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'config\windhawk\native-dock.json') -Raw |
  ConvertFrom-Json -AsHashtable
$modRegistry = "HKLM:\Software\Windhawk\Engine\Mods\$($modConfig.modId)"
$modSettingsRegistry = Join-Path $modRegistry 'Settings'

$menuBar = @(Get-Process MacMakeover.MenuBar -ErrorAction SilentlyContinue)
$menuHost = @(Get-Process MacMakeover.MenuHost -ErrorAction SilentlyContinue)
$seelen = @(Get-Process seelen-ui, slu-service -ErrorAction SilentlyContinue)
$yasb = @(Get-Process yasb -ErrorAction SilentlyContinue)

if ($menuBar.Count -ne 1) { $failures.Add("Expected one MenuBar process; found $($menuBar.Count).") }
if ($menuHost.Count -ne 1) { $failures.Add("Expected one MenuHost process; found $($menuHost.Count).") }
if ($seelen.Count) { $failures.Add('Seelen is still running alongside the native shell.') }
if ($yasb.Count) { $failures.Add('YASB is still running alongside the native shell.') }
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { $failures.Add('Windows Explorer is not running.') }

foreach ($required in @(
    'MacMakeover.MenuBar.exe',
    'MacMakeover.MenuHost.exe',
    'Assets\apple-mark.png',
    'Assets\Fonts\Manrope-Regular.ttf',
    'Assets\Fonts\Manrope-SemiBold.ttf',
    'Assets\Fonts\JetBrainsMono-Medium.ttf',
    'Assets\Fonts\OFL-Manrope.txt',
    'Assets\Fonts\OFL-JetBrainsMono.txt'
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $deploymentRoot $required))) {
    $failures.Add("Missing deployed file: $required")
  }
}

$hostSelfTest = Start-Process -FilePath (Join-Path $deploymentRoot 'MacMakeover.MenuHost.exe') `
  -ArgumentList '--self-test' -Wait -PassThru -WindowStyle Hidden
if ($hostSelfTest.ExitCode -ne 0) {
  $failures.Add("MenuHost Core Audio self-test failed with exit code $($hostSelfTest.ExitCode).")
}

$seelenTask = Get-ScheduledTask -TaskPath '\Seelen\' -TaskName 'Seelen UI Service' -ErrorAction SilentlyContinue
if ($seelenTask -and $seelenTask.State -ne 'Disabled') {
  $failures.Add('Seelen is still enabled at logon.')
}

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValues = Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
if (-not $runValues -or $runValues.MacMakeoverMenuBar -notmatch 'MacMakeover\.MenuBar\.exe') {
  $failures.Add('MenuBar is not registered at logon.')
}
if (-not $runValues -or $runValues.MacMakeoverMenuHost -notmatch 'MacMakeover\.MenuHost\.exe') {
  $failures.Add('MenuHost is not registered at logon.')
}

$mod = Get-ItemProperty -LiteralPath $modRegistry -ErrorAction SilentlyContinue
if (-not $mod) {
  $failures.Add('Windows 11 Taskbar Styler is not installed.')
} else {
  if ($mod.Disabled) { $failures.Add('Windows 11 Taskbar Styler is disabled.') }
  if ($mod.Version -ne $modConfig.version) { $failures.Add("Unexpected taskbar styler version: $($mod.Version)") }
  $binary = Join-Path $env:ProgramData "Windhawk\Engine\Mods\64\$($mod.LibraryFileName)"
  if (-not (Test-Path -LiteralPath $binary)) {
    $failures.Add('The configured taskbar styler DLL is missing.')
  } elseif ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -ne $modConfig.binarySha256) {
    $failures.Add('The installed taskbar styler DLL hash does not match the pinned build.')
  }
}

$dockSettings = Get-ItemProperty -LiteralPath $modSettingsRegistry -ErrorAction SilentlyContinue
if (-not $dockSettings -or $dockSettings.theme -ne 'DockLike') {
  $failures.Add('DockLike is not the active taskbar theme.')
}
if (-not $dockSettings -or $dockSettings.'controlStyles[2].styles[0]' -ne 'Visibility=Collapsed') {
  $failures.Add('The native system tray is not hidden from the bottom dock.')
}
$dockSettingNames = if ($dockSettings) { @($dockSettings.PSObject.Properties.Name) } else { @() }
$searchVisibility = if ($dockSettingNames -contains 'controlStyles[7].styles[0]') {
  $dockSettings.PSObject.Properties['controlStyles[7].styles[0]'].Value
} else { $null }
$widgetsVisibility = if ($dockSettingNames -contains 'controlStyles[8].styles[0]') {
  $dockSettings.PSObject.Properties['controlStyles[8].styles[0]'].Value
} else { $null }
if ($searchVisibility -ne 'Visibility=Collapsed' -or $widgetsVisibility -ne 'Visibility=Collapsed') {
  $failures.Add('The dock profile does not collapse Windows Search and Widgets.')
}
foreach ($settingName in @(
    'controlStyles[0].styles[3]',
    'controlStyles[1].styles[2]',
    'controlStyles[1].styles[3]',
    'controlStyles[9].target',
    'controlStyles[9].styles[3]',
    'controlStyles[10].styles[0]',
    'controlStyles[13].target',
    'controlStyles[13].styles[0]'
  )) {
  $liveValue = if ($dockSettingNames -contains $settingName) {
    $dockSettings.PSObject.Properties[$settingName].Value
  } else { $null }
  if ($liveValue -ne $modConfig.settings[$settingName]) {
    $failures.Add("Live dock setting is stale: $settingName")
  }
}
$advancedSearch = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name SearchboxTaskbarMode -ErrorAction SilentlyContinue).SearchboxTaskbarMode
$searchSettings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -ErrorAction SilentlyContinue
if ($advancedSearch -ne 0 -or
    $searchSettings.SearchboxTaskbarMode -ne 0 -or
    $searchSettings.SearchboxTaskbarModeCache -ne 0) {
  $failures.Add('Windows Search is still configured to appear in the native dock.')
}

$stuckRects = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3' -ErrorAction SilentlyContinue).Settings
if ($stuckRects -and $stuckRects.Length -gt 8 -and (($stuckRects[8] -band 1) -eq 1)) {
  $failures.Add('Native taskbar auto-hide is enabled; maximized apps can overlap the dock.')
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeShellProbe {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr FindWindow(string className, string windowName);
  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr window);
}
'@
$taskbarWindow = [NativeShellProbe]::FindWindow('Shell_TrayWnd', $null)
if ($taskbarWindow -eq [IntPtr]::Zero -or -not [NativeShellProbe]::IsWindowVisible($taskbarWindow)) {
  $failures.Add('The native taskbar window is not visible.')
}

foreach ($screen in [Windows.Forms.Screen]::AllScreens) {
  if ($screen.WorkingArea.Top -le $screen.Bounds.Top) {
    $failures.Add("$($screen.DeviceName) has no reserved top menu-bar work area.")
  }
  if ($screen.WorkingArea.Bottom -ge $screen.Bounds.Bottom) {
    $failures.Add("$($screen.DeviceName) has no reserved bottom dock work area.")
  }
}

$protocols = @(
  'macmakeover-apple-menu',
  'macmakeover-control-center',
  'macmakeover-network',
  'macmakeover-bluetooth',
  'macmakeover-notification-center'
)
foreach ($protocol in $protocols) {
  $command = (Get-ItemProperty -LiteralPath "Registry::HKEY_CURRENT_USER\Software\Classes\$protocol\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
  if ([string]::IsNullOrWhiteSpace($command)) {
    $failures.Add("Protocol is not registered: $protocol")
  } elseif ($command -match 'wscript|powershell') {
    $failures.Add("Protocol uses a visible or slow launcher: $protocol")
  } elseif ($protocol -ne 'macmakeover-notification-center' -and
            $command -notmatch [regex]::Escape((Join-Path $deploymentRoot 'MacMakeover.MenuHost.exe'))) {
    $failures.Add("Protocol does not use the deployed resident MenuHost: $protocol")
  }
}

$wallpaper = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
if ($wallpaper -notmatch 'MacMakeover\\wallpapers\\mac-wallpaper\.jpg$' -or -not (Test-Path -LiteralPath $wallpaper)) {
  $failures.Add('The Mac wallpaper is not applied from the managed local copy.')
}

$hotCornerProcesses = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
  Where-Object { $_.CommandLine -match 'hot-corners\.ps1' }
if ($hotCornerProcesses) {
  $failures.Add('The polling hot-corner helper is still running.')
}

$nativePins = @(Get-ChildItem -LiteralPath "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar" -Filter '*.lnk' -ErrorAction SilentlyContinue)
if ($nativePins.Count -lt 10) {
  $warnings.Add("Only $($nativePins.Count) native taskbar shortcuts were found.")
}

if ($menuBar.Count -eq 1 -and $menuBar[0].WorkingSet64 -gt 100MB) {
  $failures.Add("MenuBar memory exceeds 100 MB: $([math]::Round($menuBar[0].WorkingSet64 / 1MB, 1)) MB")
}
if ($menuHost.Count -eq 1 -and $menuHost[0].WorkingSet64 -gt 100MB) {
  $failures.Add("MenuHost memory exceeds 100 MB: $([math]::Round($menuHost[0].WorkingSet64 / 1MB, 1)) MB")
}

$menuBarLog = Join-Path $env:LOCALAPPDATA 'MacMakeover\menu-bar.log'
if (Test-Path -LiteralPath $menuBarLog) {
  $recentErrors = Get-Content -LiteralPath $menuBarLog -Tail 100 |
    Where-Object { $_ -match 'exception|failed' }
  if ($recentErrors) {
    $warnings.Add('Recent MenuBar diagnostics contain an error; inspect menu-bar.log.')
  }
}

foreach ($warning in $warnings) { Write-Warning $warning }
if ($failures.Count) {
  foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
  exit 1
}

$barMb = [math]::Round($menuBar[0].WorkingSet64 / 1MB, 1)
$hostMb = [math]::Round($menuHost[0].WorkingSet64 / 1MB, 1)
Write-Host ('PASS: native shell is coherent. MenuBar {0} MB; MenuHost {1} MB.' -f $barMb, $hostMb)
