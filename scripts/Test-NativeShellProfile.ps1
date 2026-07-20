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
$dock = @(Get-Process MacMakeover.Dock -ErrorAction SilentlyContinue)
$seelen = @(Get-Process seelen-ui, slu-service -ErrorAction SilentlyContinue)
$yasb = @(Get-Process yasb -ErrorAction SilentlyContinue)

if ($menuBar.Count -ne 1) { $failures.Add("Expected one MenuBar process; found $($menuBar.Count).") }
if ($menuHost.Count -ne 1) { $failures.Add("Expected one MenuHost process; found $($menuHost.Count).") }
if ($dock.Count -ne 1) { $failures.Add("Expected one Dock process; found $($dock.Count).") }
if ($seelen.Count) { $failures.Add('Seelen is still running alongside the native shell.') }
if ($yasb.Count) { $failures.Add('YASB is still running alongside the native shell.') }
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { $failures.Add('Windows Explorer is not running.') }

foreach ($required in @(
    'MacMakeover.MenuBar.exe',
    'MacMakeover.MenuHost.exe',
    'MacMakeover.Dock.exe',
    'native-taskbar-pins.json',
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

$hostSelfTest = $null
foreach ($attempt in 1..3) {
  $hostSelfTest = Start-Process -FilePath (Join-Path $deploymentRoot 'MacMakeover.MenuHost.exe') `
    -ArgumentList '--self-test' -Wait -PassThru -WindowStyle Hidden
  if ($hostSelfTest.ExitCode -eq 0) { break }
  Start-Sleep -Milliseconds 400
}
if ($hostSelfTest.ExitCode -ne 0) {
  $failures.Add("MenuHost Core Audio self-test failed after three attempts with exit code $($hostSelfTest.ExitCode).")
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
if (-not $runValues -or $runValues.MacMakeoverDock -notmatch 'MacMakeover\.Dock\.exe') {
  $failures.Add('Dock is not registered at logon.')
}

$mod = Get-ItemProperty -LiteralPath $modRegistry -ErrorAction SilentlyContinue
if ($mod -and -not $mod.Disabled) {
  $failures.Add('Windows 11 Taskbar Styler must stay disabled while MacMakeover.Dock owns the production dock.')
}
$windhawkService = Get-Service -Name Windhawk -ErrorAction SilentlyContinue
if ($windhawkService -and ($windhawkService.Status -eq 'Running' -or $windhawkService.StartType -eq 'Automatic')) {
  $failures.Add('Windhawk service must remain stopped and non-automatic in the production profile.')
}
$windhawkUiTask = Get-ScheduledTask -TaskName 'WindhawkRunUITask' -ErrorAction SilentlyContinue
if ($windhawkUiTask -and $windhawkUiTask.State -ne 'Disabled') {
  $failures.Add('Windhawk UI recovery task must remain disabled in the production profile.')
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
  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetClassName(IntPtr window, System.Text.StringBuilder className, int maxCount);
  public delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);
}
'@
$taskbarWindows = [System.Collections.Generic.List[System.IntPtr]]::new()
$enumTaskbars = [NativeShellProbe+EnumWindowsProc]{
  param([IntPtr]$window, [IntPtr]$parameter)
  $className = [Text.StringBuilder]::new(64)
  [void][NativeShellProbe]::GetClassName($window, $className, $className.Capacity)
  if ($className.ToString() -in @('Shell_TrayWnd', 'Shell_SecondaryTrayWnd')) {
    $taskbarWindows.Add($window)
  }
  return $true
}
[void][NativeShellProbe]::EnumWindows($enumTaskbars, [IntPtr]::Zero)
if ($taskbarWindows.Count -lt [Windows.Forms.Screen]::AllScreens.Count) {
  $failures.Add('The native taskbar work-area owner is missing.')
}
foreach ($taskbarWindow in $taskbarWindows) {
  if ([NativeShellProbe]::IsWindowVisible($taskbarWindow)) {
    $failures.Add('A duplicate primary or secondary native taskbar is visible behind MacMakeover.Dock.')
  }
}

foreach ($screen in [Windows.Forms.Screen]::AllScreens) {
  if ($screen.WorkingArea.Top -le $screen.Bounds.Top) {
    $failures.Add("$($screen.DeviceName) has no reserved top menu-bar work area.")
  }
  if ($screen.WorkingArea.Bottom -ge $screen.Bounds.Bottom) {
    $failures.Add("$($screen.DeviceName) has no reserved bottom dock work area.")
  }
  $bottomReservation = $screen.Bounds.Bottom - $screen.WorkingArea.Bottom
  if ($bottomReservation -lt 56) {
    $failures.Add("$($screen.DeviceName) reserves only $bottomReservation px at the bottom; 56 px is required to keep maximized windows clear of the dock.")
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

$wallpaper = $null
$wallpaperProperty = Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue
if ($wallpaperProperty) {
  $wallpaper = $wallpaperProperty.PSObject.Properties['Wallpaper'].Value
}
if ($wallpaper -notmatch 'MacMakeover\\wallpapers\\mac-wallpaper\.jpg$' -or -not (Test-Path -LiteralPath $wallpaper)) {
  $failures.Add('The Mac wallpaper is not applied from the managed local copy.')
} else {
  $wallpaperAsset = Join-Path $repoRoot 'assets\wallpapers\mac-wallpaper.jpg'
  if ((Get-FileHash -LiteralPath $wallpaper -Algorithm SHA256).Hash -ne
      (Get-FileHash -LiteralPath $wallpaperAsset -Algorithm SHA256).Hash) {
    $failures.Add('The applied wallpaper differs from the repository-managed Big Sur (Day) asset.')
  }
}
$wallpaperPolicy = $null
$wallpaperPolicyProperty = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System' `
  -Name Wallpaper -ErrorAction SilentlyContinue
if ($wallpaperPolicyProperty) {
  $wallpaperPolicy = $wallpaperPolicyProperty.PSObject.Properties['Wallpaper'].Value
}
if (-not [string]::IsNullOrWhiteSpace($wallpaperPolicy)) {
  $failures.Add("A per-user policy still overrides the managed wallpaper: $wallpaperPolicy")
}
$virtualDesktopWallpapers = Get-ChildItem `
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops\Desktops' `
  -ErrorAction SilentlyContinue | ForEach-Object {
    $desktopWallpaperProperty = Get-ItemProperty -LiteralPath $_.PSPath -Name Wallpaper -ErrorAction SilentlyContinue
    if ($desktopWallpaperProperty) {
      $desktopWallpaperProperty.PSObject.Properties['Wallpaper'].Value
    }
  }
if ($virtualDesktopWallpapers | Where-Object { $_ -and $_ -ne $wallpaper }) {
  $failures.Add('One or more virtual desktops still override the managed Big Sur wallpaper.')
}

$hotCornerProcesses = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
  Where-Object { $_.CommandLine -match 'hot-corners\.ps1' }
if ($hotCornerProcesses) {
  $failures.Add('The polling hot-corner helper is still running.')
}

$pinManifest = Get-Content -LiteralPath (Join-Path $repoRoot 'config\native-taskbar-pins.json') -Raw |
  ConvertFrom-Json
$taskband = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -ErrorAction SilentlyContinue
$taskbandText = if ($taskband) {
  [Text.Encoding]::Unicode.GetString(@($taskband.Favorites) + @($taskband.FavoritesResolve))
} else { '' }
$shell = New-Object -ComObject Shell.Application
$appsFolder = $shell.Namespace('shell:AppsFolder')
$shortcutRoot = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$shortcutFolder = $shell.Namespace($shortcutRoot)
foreach ($pin in $pinManifest.pins) {
  $appVerbs = if ($pin.appId) {
    $item = $appsFolder.ParseName([string]$pin.appId)
    if ($item) { @($item.Verbs() | ForEach-Object { $_.Name.Replace('&', '') }) } else { @() }
  } else { @() }
  $shortcut = $shortcutFolder.ParseName("$($pin.name).lnk")
  $shortcutVerbs = if ($shortcut) {
    @($shortcut.Verbs() | ForEach-Object { $_.Name.Replace('&', '') })
  } else { @() }
  $verbs = @($appVerbs + $shortcutVerbs | Sort-Object -Unique)
  $foundInTaskband = @($pin.taskbandPatterns | Where-Object {
      $taskbandText.IndexOf([string]$_, [StringComparison]::OrdinalIgnoreCase) -ge 0
    }).Count -gt 0
  if (($verbs -notcontains 'Unpin from taskbar') -and -not $foundInTaskband) {
    $failures.Add("Required native taskbar pin is missing: $($pin.name)")
  }
}

if ($menuBar.Count -eq 1 -and $menuBar[0].WorkingSet64 -gt 100MB) {
  $failures.Add("MenuBar memory exceeds 100 MB: $([math]::Round($menuBar[0].WorkingSet64 / 1MB, 1)) MB")
}
if ($menuHost.Count -eq 1 -and $menuHost[0].WorkingSet64 -gt 100MB) {
  $failures.Add("MenuHost memory exceeds 100 MB: $([math]::Round($menuHost[0].WorkingSet64 / 1MB, 1)) MB")
}
if ($dock.Count -eq 1 -and $dock[0].WorkingSet64 -gt 120MB) {
  $failures.Add("Dock memory exceeds 120 MB: $([math]::Round($dock[0].WorkingSet64 / 1MB, 1)) MB")
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
$dockMb = [math]::Round($dock[0].WorkingSet64 / 1MB, 1)
Write-Host ('PASS: native shell is coherent. MenuBar {0} MB; MenuHost {1} MB; Dock {2} MB.' -f $barMb, $hostMb, $dockMb)
