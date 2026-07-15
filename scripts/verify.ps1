[CmdletBinding()]
param(
  [switch]$CaptureScreenshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot
$SeelenRoaming = Join-Path $env:APPDATA "com.seelen.seelen-ui"
$SeelenLocal = Join-Path $env:LOCALAPPDATA "com.seelen.seelen-ui"
$ShortcutPath = Join-Path $SeelenRoaming "settings_shortcuts.json"
$SettingsPath = Join-Path $SeelenRoaming "settings.json"
$ToolbarPath = Join-Path $SeelenRoaming "data\seelen-fancy-toolbar\state.yml"
$ThemePath = Join-Path $SeelenRoaming "themes\macos-glass\styles\fancy-toolbar.css"
$NetworkPluginPath = Join-Path $SeelenRoaming "plugins\macmakeover_network_status\metadata.yml"
$LogPath = Join-Path $SeelenLocal "logs\Seelen UI.log"
$PowerToysSettingsPath = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\settings.json"
$PowerToysRunSettingsPath = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\PowerToys Run\settings.json"
$AppleMenuScriptPath = Join-Path $PackageRoot "scripts\Show-MacAppleMenu.ps1"
$AppleMenuInstallerPath = Join-Path $PackageRoot "scripts\Install-AppleMenuHandler.ps1"
$ControlCenterScriptPath = Join-Path $PackageRoot "scripts\Show-MacControlCenter.ps1"
$ControlCenterInstallerPath = Join-Path $PackageRoot "scripts\Install-MacControlCenterHandler.ps1"
$NetworkInstallerPath = Join-Path $PackageRoot "scripts\Install-MacNetworkHandler.ps1"
$BluetoothInstallerPath = Join-Path $PackageRoot "scripts\Install-MacBluetoothHandler.ps1"
$NotificationCenterInstallerPath = Join-Path $PackageRoot "scripts\Install-MacNotificationCenterHandler.ps1"
$HotCornersScriptPath = Join-Path $PackageRoot "scripts\start-hot-corners.ps1"
$HotCornersConfigPath = Join-Path $PackageRoot "config\hot-corners.json"
$WorkAreaFitScriptPath = Join-Path $PackageRoot "scripts\fit-windows-to-workarea.ps1"
$MenuHostProjectPath = Join-Path $PackageRoot "tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj"
$MenuHostExePath = Join-Path $PackageRoot "tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe"
$AppleMenuCommandPath = "HKCU:\Software\Classes\macmakeover-apple-menu\shell\open\command"
$ControlCenterCommandPath = "HKCU:\Software\Classes\macmakeover-control-center\shell\open\command"
$NetworkCommandPath = "HKCU:\Software\Classes\macmakeover-network\shell\open\command"
$BluetoothCommandPath = "HKCU:\Software\Classes\macmakeover-bluetooth\shell\open\command"
$NotificationCenterCommandPath = "HKCU:\Software\Classes\macmakeover-notification-center\shell\open\command"
$VerificationFailed = $false

function Get-ImageAverageLuma {
  param(
    [string]$Path,
    [int]$Y,
    [int]$Height,
    [int]$X = 0,
    [int]$Width = 0
  )

  Add-Type -AssemblyName System.Drawing
  $image = [System.Drawing.Bitmap]::FromFile($Path)
  try {
    $xStart = [Math]::Max(0, $X)
    $xEnd = if ($Width -gt 0) { [Math]::Min($image.Width, $X + $Width) } else { $image.Width }
    $yEnd = [Math]::Min($image.Height, $Y + $Height)
    if ($xStart -ge $xEnd -or $Y -ge $yEnd) { return $null }

    $xStep = [Math]::Max(1, [int](($xEnd - $xStart) / 160))
    $yStep = [Math]::Max(1, [int](($yEnd - $Y) / 12))
    $total = 0.0
    $count = 0

    for ($yy = $Y; $yy -lt $yEnd; $yy += $yStep) {
      for ($xx = $xStart; $xx -lt $xEnd; $xx += $xStep) {
        $pixel = $image.GetPixel($xx, $yy)
        $total += (0.2126 * $pixel.R) + (0.7152 * $pixel.G) + (0.0722 * $pixel.B)
        $count++
      }
    }

    if ($count -eq 0) { return $null }
    [Math]::Round($total / $count, 1)
  } finally {
    $image.Dispose()
  }
}

function Save-Crop {
  param(
    [string]$Source,
    [string]$Destination,
    [System.Drawing.Rectangle]$Rectangle
  )

  Add-Type -AssemblyName System.Drawing
  $image = [System.Drawing.Bitmap]::FromFile($Source)
  try {
    $crop = New-Object System.Drawing.Bitmap($Rectangle.Width, $Rectangle.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($crop)
    try {
      $graphics.DrawImage($image, 0, 0, $Rectangle, [System.Drawing.GraphicsUnit]::Pixel)
      $crop.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $graphics.Dispose()
      $crop.Dispose()
    }
  } finally {
    $image.Dispose()
  }
}

Write-Host "Seelen processes:"
Get-Process | Where-Object { $_.ProcessName -match "seelen|slu" } | Select-Object ProcessName,Id,Responding,StartTime | Format-Table -AutoSize

Write-Host ""
Write-Host "PowerToys / launcher processes:"
Get-Process | Where-Object { $_.ProcessName -match "PowerToys|CmdPal|CommandPalette|PowerLauncher" } | Select-Object ProcessName,Id,Responding,StartTime | Format-Table -AutoSize

Write-Host ""
Write-Host "Core files:"
foreach ($path in @($SettingsPath, $ShortcutPath, $ToolbarPath, $ThemePath, $AppleMenuScriptPath, $AppleMenuInstallerPath, $ControlCenterScriptPath, $ControlCenterInstallerPath, $NetworkInstallerPath, $BluetoothInstallerPath, $NotificationCenterInstallerPath, $HotCornersScriptPath, $HotCornersConfigPath, $WorkAreaFitScriptPath, $MenuHostProjectPath, $MenuHostExePath)) {
  if (Test-Path -LiteralPath $path) {
    "OK   {0}" -f $path
  } else {
    "MISS {0}" -f $path
    $VerificationFailed = $true
  }
}

if (Test-Path -LiteralPath $SettingsPath) {
  Write-Host ""
  Write-Host "Seelen performance guard:"
  try {
    $seelenSettings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    $performanceMode = $seelenSettings.performanceMode
    $performanceMode | Format-List default,onBattery,onEnergySaver

    if ($performanceMode.onBattery -ne "Disabled" -or $performanceMode.onEnergySaver -ne "Disabled") {
      Write-Warning "Seelen performance modes can hide the top toolbar and bottom dock. Keep onBattery/onEnergySaver set to Disabled."
      $VerificationFailed = $true
    }

    if ($seelenSettings.byWidget.'@seelen/weg'.enabled -ne $true) {
      Write-Warning "Seelen WEG should be enabled. The native MenuHost appbar dock was removed because it interfered with maximize/work-area behavior."
      $VerificationFailed = $true
    }
  } catch {
    Write-Warning "Could not parse Seelen settings.json: $($_.Exception.Message)"
    $VerificationFailed = $true
  }
}

Write-Host ""
Write-Host "Apple menu launcher:"
if (Test-Path -Path $AppleMenuCommandPath) {
  $appleMenuCommand = (Get-Item -Path $AppleMenuCommandPath).GetValue("")
  Write-Host "  $appleMenuCommand"
  if ($appleMenuCommand -match "wscript\.exe") {
    Write-Warning "Apple menu is registered via wscript.exe, which is blocked by this PC's security policy (the menu will not open). Re-run scripts\Install-AppleMenuHandler.ps1 to switch to conhost."
    $VerificationFailed = $true
  } elseif (-not ($appleMenuCommand -match "MacMakeover\.MenuHost" -and $appleMenuCommand -match "echo apple")) {
    Write-Warning "Apple menu is not registered to the fast MenuHost pipe launcher (cmd echo into \\.\pipe\MacMakeover.MenuHost with a --show fallback). Re-run scripts\Install-AppleMenuHandler.ps1."
    $VerificationFailed = $true
  }
} else {
  Write-Warning "Apple menu protocol handler is missing: macmakeover-apple-menu:"
  $VerificationFailed = $true
}

Write-Host ""
Write-Host "Control Center launcher:"
if (Test-Path -Path $ControlCenterCommandPath) {
  $controlCenterCommand = (Get-Item -Path $ControlCenterCommandPath).GetValue("")
  Write-Host "  $controlCenterCommand"
  if ($controlCenterCommand -match "wscript\.exe") {
    Write-Warning "Control Center is registered via wscript.exe, which is blocked by this PC's security policy. Re-run scripts\Install-MacControlCenterHandler.ps1 to switch to the pipe launcher."
    $VerificationFailed = $true
  } elseif (-not ($controlCenterCommand -match "MacMakeover\.MenuHost" -and $controlCenterCommand -match "echo control")) {
    Write-Warning "Control Center is not registered to the fast MenuHost pipe launcher (cmd echo into \\.\pipe\MacMakeover.MenuHost with a --show fallback). Re-run scripts\Install-MacControlCenterHandler.ps1."
    $VerificationFailed = $true
  }
} else {
  Write-Warning "Control Center protocol handler is missing: macmakeover-control-center:"
  $VerificationFailed = $true
}

Write-Host ""
Write-Host "Network launcher:"
if (Test-Path -Path $NetworkCommandPath) {
  $networkCommand = (Get-Item -Path $NetworkCommandPath).GetValue("")
  Write-Host "  $networkCommand"
  if ($networkCommand -match "wscript\.exe") {
    Write-Warning "Network panel is registered via wscript.exe, which is blocked by this PC's security policy. Re-run scripts\Install-MacNetworkHandler.ps1 to switch to the pipe launcher."
    $VerificationFailed = $true
  } elseif (-not ($networkCommand -match "MacMakeover\.MenuHost" -and $networkCommand -match "echo network")) {
    Write-Warning "Network panel is not registered to the fast MenuHost pipe launcher (cmd echo into \\.\pipe\MacMakeover.MenuHost with a --show fallback). Re-run scripts\Install-MacNetworkHandler.ps1."
    $VerificationFailed = $true
  }
} else {
  Write-Warning "Network protocol handler is missing: macmakeover-network:"
  $VerificationFailed = $true
}

Write-Host ""
Write-Host "Bluetooth launcher:"
if (Test-Path -Path $BluetoothCommandPath) {
  $bluetoothCommand = (Get-Item -Path $BluetoothCommandPath).GetValue("")
  Write-Host "  $bluetoothCommand"
  if ($bluetoothCommand -match "wscript\.exe") {
    Write-Warning "Bluetooth panel is registered via wscript.exe, which is blocked by this PC's security policy. Re-run scripts\Install-MacBluetoothHandler.ps1 to switch to the pipe launcher."
    $VerificationFailed = $true
  } elseif (-not ($bluetoothCommand -match "MacMakeover\.MenuHost" -and $bluetoothCommand -match "echo bluetooth")) {
    Write-Warning "Bluetooth panel is not registered to the fast MenuHost pipe launcher (cmd echo into \\.\pipe\MacMakeover.MenuHost with a --show fallback). Re-run scripts\Install-MacBluetoothHandler.ps1."
    $VerificationFailed = $true
  }
} else {
  Write-Warning "Bluetooth protocol handler is missing: macmakeover-bluetooth:"
  $VerificationFailed = $true
}

Write-Host ""
Write-Host "Notification Center launcher:"
if (Test-Path -Path $NotificationCenterCommandPath) {
  $notificationCenterCommand = (Get-Item -Path $NotificationCenterCommandPath).GetValue("")
  Write-Host "  $notificationCenterCommand"
  if ($notificationCenterCommand -match "wscript\.exe") {
    Write-Warning "Notification Center is registered via wscript.exe, which is blocked by this PC's security policy. Re-run scripts\Install-MacNotificationCenterHandler.ps1."
    $VerificationFailed = $true
  } elseif (-not ($notificationCenterCommand -match "explorer\.exe" -and $notificationCenterCommand -match "ms-actioncenter:")) {
    Write-Warning "Notification Center is not registered to the native ms-actioncenter launcher. Re-run scripts\Install-MacNotificationCenterHandler.ps1."
    $VerificationFailed = $true
  }
} else {
  Write-Warning "Notification Center protocol handler is missing: macmakeover-notification-center:"
  $VerificationFailed = $true
}

$notificationActionRaw = Get-Content -LiteralPath (Join-Path $PackageRoot "scripts\Invoke-MacAction.ps1") -Raw
if ($notificationActionRaw -notmatch '"NotificationCenter"\s*\{\s*Start-Process\s+"ms-actioncenter:"') {
  Write-Warning "Notification Center is not using the native ms-actioncenter URI. Simulated Win+N is unreliable on this Windows build."
  $VerificationFailed = $true
}

if (Test-Path -LiteralPath $ToolbarPath) {
  Write-Host ""
  Write-Host "Top-bar click latency guard:"
  $toolbarRaw = Get-Content -LiteralPath $ToolbarPath -Raw
  if ($toolbarRaw -match "@seelen/tb-quick-settings") {
    Write-Warning "Seelen quick settings is back in the toolbar. That restores the old clunky power/options flyout."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -notmatch 'isReorderDisabled:\s*true') {
    Write-Warning "Toolbar reordering is enabled. Seelen can expose a black edit/reorder mini-toolbar over the center stats in normal desktop use."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -notmatch 'open\("macmakeover-apple-menu:"\)') {
    Write-Warning "Apple-logo clicks must be item-owned via macmakeover-apple-menu:. Broad helper pixel zones can fire while clicking maximized app chrome."
    $VerificationFailed = $true
  } else {
    Write-Host "  OK Apple clicks are item-owned and position-independent."
  }

  $shellPopupHideCount = ([regex]::Matches($toolbarRaw, 'Seelen UI.*ShellHost.*MacMakeover\\.MenuHost|helper\\.test\\(name\\).*helper\\.test\\(title\\)')).Count
  if ($shellPopupHideCount -lt 2) {
    Write-Warning "Focused-app labels should hide Seelen UI/ShellHost/MacMakeover.MenuHost helper surfaces by name and title. Otherwise menu popups pollute the Mac menu bar with implementation labels."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -notmatch 'Windows Shell Experience Host\|ShellExperienceHost') {
    Write-Warning "Focused-app labels should hide Windows Shell Experience Host. Native notification and calendar surfaces must not leak implementation names into the menu bar."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -notmatch 'Windows Explorer\|File Explorer\|Explorer\|Program Manager' -or $toolbarRaw -notmatch 'return "Finder"') {
    Write-Warning "Focused-app labels should map desktop/File Explorer shell focus to Finder. Otherwise minimized/show-desktop states leak 'Windows Explorer' into the Mac menu bar."
    $VerificationFailed = $true
  } else {
    Write-Host "  OK desktop/File Explorer shell focus maps to Finder."
  }

  if ($toolbarRaw -notmatch 'open\("macmakeover-control-center:"\)') {
    Write-Warning "The Control Center sliders item has lost its onClick. It must open via the macmakeover-control-center: URI (fast MenuHost pipe echo) so it never depends on pixel positions."
    $VerificationFailed = $true
  } else {
    Write-Host "  OK Control Center opens via its item onClick (position-independent)."
  }

  if ($toolbarRaw -match 'Battery:|Charge rate:|return "Control Center";') {
    Write-Warning "Top-bar battery/control tooltips are enabled. They can overlap the custom Control Center popover."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -match 'f3a7c1e2-9b4d-4e6a-8c1f-2d5e7a9b0c11|energyRate') {
    Write-Warning "Top-bar battery charging state has split back into a separate charge-rate item. Keep it merged into one battery readout (a charging bolt inside the merged item is fine)."
    $VerificationFailed = $true
  }

  # The network icon is the @vineeth/tb-network-status plugin (connection-aware);
  # its onClickV2 (in the plugin file) opens macmakeover-network:. Checked further down.
  if ($toolbarRaw -notmatch '@vineeth/tb-network-status') {
    Write-Warning "The network status item must be the @vineeth/tb-network-status plugin (connection-aware icon: VPN shield / Wi-Fi / ethernet / tether)."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -match '@seelen/tb-bluetooth-popup' -or $toolbarRaw -notmatch 'open\("macmakeover-bluetooth:"\)') {
    Write-Warning "Bluetooth should be a stable custom toolbar item opening macmakeover-bluetooth:, not Seelen's bundled popup which can collapse/disappear."
    $VerificationFailed = $true
  }

  # User requirement (explicit, 2026-07-14): CPU/RAM/NET are informational center
  # readouts. They must remain non-clickable; battery stays in the right system cluster.
  if ($toolbarRaw -notmatch '(?s)center:.*- Cpu.*- Memory.*- NetworkStatistics.*right:') {
    Write-Warning "The center telemetry cluster must contain CPU, RAM, and NET readouts."
    $VerificationFailed = $true
  }

  $centerBlock = [regex]::Match($toolbarRaw, '(?s)center:(.*?)right:').Groups[1].Value
  if ($centerBlock -match '(?m)^\s*onClick:\s*(?!null\s*$)\S+') {
    Write-Warning "CPU/RAM/NET are informational readouts and must not be clickable."
    $VerificationFailed = $true
  }

  # Battery/charging should be one merged right-side system-status item, not a separate
  # charge-rate glyph and not a center telemetry readout.
  if ($toolbarRaw -notmatch '(?s)right:.*macmakeover-battery-status') {
    Write-Warning "The merged battery/charging readout must live in the RIGHT system status cluster."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -match 'macmakeover-power') {
    Write-Warning "A separate top-bar power icon is present. Power actions belong inside the custom Control Center, not as a dead/fake right-side button."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -match '@seelen/tb-notifications|@seelen/tb-calendar-popup') {
    Write-Warning "Top-bar calendar/notification items are using Seelen Flyouts again. Use macmakeover-date and macmakeover-notification-center instead."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -notmatch 'macmakeover-notification-center' -or $toolbarRaw -notmatch 'open\("macmakeover-notification-center:"\)') {
    Write-Warning "Top-bar notification bell is missing or not routed through the custom Notification Center protocol."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -notmatch '(?s)id:\s*macmakeover-notification-center.*?badge:\s*null.*?open\("macmakeover-notification-center:"\)') {
    Write-Warning "Notification counts must render inline inside the bell target. A Seelen badge at the y=0 screen edge will be clipped."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -notmatch 'macmakeover-date' -or $toolbarRaw -notmatch '(?s)right:\s*.*macmakeover-date') {
    Write-Warning "Date/time should live on the right side of the menu bar, macOS-style, without Seelen Flyouts."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -match 'return \[icon\("LuWifi"\), " ", "↓"') {
    Write-Warning "Top-bar Wi-Fi has expanded back into a throughput readout. Keep the MacBook-style right-side cluster compact."
    $VerificationFailed = $true
  }
}

if (Test-Path -LiteralPath $SettingsPath) {
  $seelenSettings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
  if ([string]$seelenSettings.dateFormat -ne "ddd D MMM HH:mm") {
    Write-Warning "Seelen dateFormat should match the Mac-style menu bar shape: ddd D MMM HH:mm."
    $VerificationFailed = $true
  }
}

if (Test-Path -LiteralPath $ThemePath) {
  $toolbarCss = Get-Content -LiteralPath $ThemePath -Raw
  if ($toolbarCss -notmatch 'MacBook-flat status strip' -or $toolbarCss -match '\.ft-bar-right:has') {
    Write-Warning "Right-side system controls should use the MacBook-flat status strip styling and must not share a hover group via :has()."
    $VerificationFailed = $true
  }

  if ($toolbarCss -match '--mm-visible-width-scale|calc\(100vw\s*\*\s*var\(') {
    Write-Warning "The toolbar width is DPI-scaled/truncated. The menu bar must span the full physical screen width (100vw), not a scaled fraction."
    $VerificationFailed = $true
  }

  function Get-CssDeclarationValue {
    param(
      [string]$Body,
      [string]$Property
    )

    $match = [regex]::Match($Body, "(?m)(?:^|;)\s*$([regex]::Escape($Property))\s*:\s*(?<value>[^;]+);")
    if (-not $match.Success) { return "" }
    return $match.Groups["value"].Value.Trim()
  }

  $centerBarBlock = [regex]::Match($toolbarCss, '(?s)\.ft-bar-center\s*\{(?<body>.*?)\}').Groups["body"].Value
  $rightBarMatches = [regex]::Matches($toolbarCss, '(?s)\.ft-bar-right\s*\{(?<body>.*?)\}')
  $rightBarBlock = if ($rightBarMatches.Count) { $rightBarMatches[$rightBarMatches.Count - 1].Groups["body"].Value } else { "" }
  $centerHasCapsule =
    ((Get-CssDeclarationValue $centerBarBlock "background") -notmatch '^(|transparent|none)\b') -or
    ((Get-CssDeclarationValue $centerBarBlock "border") -notmatch '^(|0|none)\b') -or
    ((Get-CssDeclarationValue $centerBarBlock "box-shadow") -notmatch '^(|none)\b')
  $rightHasCapsule =
    ((Get-CssDeclarationValue $rightBarBlock "background") -notmatch '^(|transparent|none)\b') -or
    ((Get-CssDeclarationValue $rightBarBlock "border") -notmatch '^(|0|none)\b') -or
    ((Get-CssDeclarationValue $rightBarBlock "box-shadow") -notmatch '^(|none)\b')
  if ($centerHasCapsule -or $rightHasCapsule) {
    Write-Warning "The center/right menu-bar clusters have persistent capsule backgrounds again. Keep them flat like a MacBook menu bar."
    $VerificationFailed = $true
  }

  if ($toolbarCss -match 'inset\s+0\s+-1px|box-shadow:\s*[^;]*-1px') {
    Write-Warning "The toolbar has a bottom hairline/shadow again. That reads as the ugly black divider under the Mac menu bar."
    $VerificationFailed = $true
  }

  # The network icon must NOT be pinned to a static glyph in CSS - the whole point
  # of @vineeth/tb-network-status is that the icon changes with the connection type.
  if ($toolbarCss -match 'first-child .ft-bar-item-content::before' -and $toolbarCss -match 'ft-bar-right > .ft-bar-item:first-child .ft-bar-item-content > svg') {
    Write-Warning "The network icon is visually pinned via CSS, which erases the VPN/Wi-Fi/ethernet/tether distinction. Remove the pinned-glyph override."
    $VerificationFailed = $true
  }
}

$WegThemePath = Join-Path $SeelenRoaming "themes\macos-glass\styles\weg.css"
if (Test-Path -LiteralPath $WegThemePath) {
  $wegCss = Get-Content -LiteralPath $WegThemePath -Raw
  $taskbarBlock = [regex]::Match($wegCss, '(?s)\.taskbar\s*\{(?<body>.*?)\}').Groups["body"].Value
  $opaqueStops = [regex]::Matches($taskbarBlock, 'rgba\([^\)]*,\s*1\)')
  if ($opaqueStops.Count -lt 2) {
    Write-Warning "The dock capsule has become translucent again. Keep WEG dock background fully opaque so app content does not show through it."
    $VerificationFailed = $true
  }
}

if ((Test-Path -LiteralPath $NetworkPluginPath) -and (Test-Path -LiteralPath $ToolbarPath) -and ((Get-Content -LiteralPath $ToolbarPath -Raw) -match '@vineeth/tb-network-status')) {
  $networkPluginRaw = Get-Content -LiteralPath $NetworkPluginPath -Raw
  if ($networkPluginRaw -notmatch 'open\("macmakeover-network:"\)') {
    Write-Warning "The custom network status fallback is not opening the custom MenuHost Network panel."
    $VerificationFailed = $true
  }

  # User requirement (explicit): distinguish VPN from Wi-Fi/ethernet/tethering in the
  # ICON itself. The shield for active tunnels is that distinction - keep it.
  if ($networkPluginRaw -notmatch 'return icon\("LuShieldCheck"\)') {
    Write-Warning "The network status plugin lost its VPN shield branch. Active tunnels (PROP_VIRTUAL/TUNNEL/PPP or VPN-named adapters) must show LuShieldCheck."
    $VerificationFailed = $true
  }
}

if (Test-Path -LiteralPath $WorkAreaFitScriptPath) {
  $workAreaFitRaw = Get-Content -LiteralPath $WorkAreaFitScriptPath -Raw
  if ($workAreaFitRaw -notmatch 'Screen\]::FromHandle') {
    Write-Warning "fit-windows-to-workarea.ps1 must repair windows against each window's own monitor work area, not only the primary monitor."
    $VerificationFailed = $true
  }
}

$menuHostSourcePath = Join-Path $PackageRoot "tools\MacMakeover.MenuHost\Program.cs"
if (Test-Path -LiteralPath $menuHostSourcePath) {
  $menuHostSource = Get-Content -LiteralPath $menuHostSourcePath -Raw
  if ($menuHostSource -notmatch 'Wi-Fi' -or $menuHostSource -notmatch 'ms-settings:network-wifi') {
    Write-Warning "MenuHost Control Center is missing the Wi-Fi live tile/action."
    $VerificationFailed = $true
  }

  if ($menuHostSource -notmatch 'CreateNetwork' -or $menuHostSource -notmatch 'ReadWifiNetworks') {
    Write-Warning "MenuHost is missing the custom Network panel. Wi-Fi clicks should not depend on Seelen's brittle network popup or the native Windows taskbar flyout."
    $VerificationFailed = $true
  }

  if ($menuHostSource -match 'DockForm|SHAppBarMessage|SetBottomAppBar') {
    Write-Warning "MenuHost contains native dock/appbar code again. That path interfered with maximize/work-area behavior; keep the dock owned by Seelen WEG."
    $VerificationFailed = $true
  }

  # Topmost-while-open is REQUIRED for visibility: a no-activate popup cannot rise
  # above the user's active window via HWND_TOP (panels opened behind the app -
  # useless), and activation is denied to a background pipe server by the foreground
  # lock. The lingering hazard (R-04) is controlled by the dismissal pair below:
  # topmost is only acceptable together with Alt/foreground-change dismissal.
  if ($menuHostSource -notmatch 'HwndTopMost') {
    Write-Warning "MenuHost panels are not topmost-while-open, so they open BEHIND the active window. Show with HWND_TOPMOST + SWP_NOACTIVATE and rely on foreground-change dismissal (R-04)."
    $VerificationFailed = $true
  }

  if ($menuHostSource -notmatch 'WaitForExitAsync' -or $menuHostSource -notmatch 'Kill\(entireProcessTree:\s*true\)' -or $menuHostSource -notmatch '_lifetimeCts') {
    Write-Warning "MenuHost background probes do not have a real timeout and per-panel cancellation. Rapid Control Center churn can retain processes and handles."
    $VerificationFailed = $true
  }

  if ($menuHostSource -match 'SetForegroundWindow|form\.Activate\(\)|ShowWithoutActivation\s*=>\s*false') {
    Write-Warning "MenuHost popups are taking foreground focus again. They must show without activation so native Alt+Tab and the active app keep working."
    $VerificationFailed = $true
  }

  if ($menuHostSource -notmatch 'CloseIfSystemSwitcherStarts' -or $menuHostSource -notmatch 'IsAltPressed' -or $menuHostSource -notmatch 'GetForegroundWindowHandle') {
    Write-Warning "MenuHost popups must close when Alt/system switching starts or foreground ownership changes, otherwise topmost menus can make Alt+Tab feel broken."
    $VerificationFailed = $true
  }

  if ($menuHostSource -match 'Screen\.PrimaryScreen' -or $menuHostSource -notmatch 'Screen\.FromPoint') {
    Write-Warning "MenuHost popups must anchor to the display under the initiating pointer. Hard-wiring Screen.PrimaryScreen breaks toolbar actions on secondary monitors."
    $VerificationFailed = $true
  }
}

if (Test-Path -LiteralPath $HotCornersConfigPath) {
  Write-Host ""
  Write-Host "Hot-corners responsiveness config:"
  $hotCornersConfig = Get-Content -LiteralPath $HotCornersConfigPath -Raw | ConvertFrom-Json
  $hotCornersConfig |
    Select-Object pollMilliseconds,appleMenuClickEnabled,appleMenuZoneLeft,appleMenuZoneRight,controlCenterClickEnabled,topBarClickHeight |
    Format-List

  if ([int]$hotCornersConfig.pollMilliseconds -lt 25) {
    Write-Warning "Hot-corners pollMilliseconds is below the measured safe range and can waste CPU. Keep it between 25ms and 40ms."
    $VerificationFailed = $true
  } elseif ([int]$hotCornersConfig.pollMilliseconds -gt 40) {
    Write-Warning "Hot-corners pollMilliseconds is above the measured responsive range and can make Apple/Control Center clicks feel laggy. Keep it between 25ms and 40ms."
    $VerificationFailed = $true
  }

  if ($hotCornersConfig.appleMenuClickEnabled) {
    Write-Warning "Helper-owned Apple pixel routing is enabled. Keep Apple clicks item-owned via macmakeover-apple-menu: to avoid firing while clicking app chrome."
    $VerificationFailed = $true
  }

  foreach ($dwellCorner in @("topLeft", "topRight", "bottomLeft", "bottomRight")) {
    $cornerProperty = $hotCornersConfig.PSObject.Properties[$dwellCorner]
    if ($cornerProperty -and [string]$cornerProperty.Value -ne "None") {
      Write-Warning "$dwellCorner dwell action should be None. Dwell hot corners were too easy to trigger accidentally during normal window navigation."
      $VerificationFailed = $true
    }
  }

  if ([int]$hotCornersConfig.topBarClickHeight -gt 19) {
    Write-Warning "Top-bar fallback routing extends into application title bars. Keep topBarClickHeight at or below the actual 19px toolbar."
    $VerificationFailed = $true
  }

  foreach ($fallbackRoute in @(
    "networkFlyoutClickEnabled",
    "bluetoothClickEnabled",
    "batteryQuickSettingsClickEnabled",
    "controlCenterClickEnabled",
    "notificationCenterClickEnabled",
    "calendarPopupClickEnabled"
  )) {
    $routeProperty = $hotCornersConfig.PSObject.Properties[$fallbackRoute]
    if (-not $routeProperty -or -not [bool]$routeProperty.Value) {
      Write-Warning "$fallbackRoute should be true so right-side controls remain usable when Seelen renders a click-through toolbar on a DPI-scaled monitor."
      $VerificationFailed = $true
    }
  }

  $fallbackZones = @(
    [pscustomobject]@{ Name = "Network"; LeftOffset = [int]$hotCornersConfig.networkFlyoutZoneLeftOffset; RightOffset = [int]$hotCornersConfig.networkFlyoutZoneRightOffset },
    [pscustomobject]@{ Name = "Bluetooth"; LeftOffset = [int]$hotCornersConfig.bluetoothZoneLeftOffset; RightOffset = [int]$hotCornersConfig.bluetoothZoneRightOffset },
    [pscustomobject]@{ Name = "Battery"; LeftOffset = [int]$hotCornersConfig.batteryQuickSettingsZoneLeftOffset; RightOffset = [int]$hotCornersConfig.batteryQuickSettingsZoneRightOffset },
    [pscustomobject]@{ Name = "Control Center"; LeftOffset = [int]$hotCornersConfig.controlCenterStatusZoneLeftOffset; RightOffset = [int]$hotCornersConfig.controlCenterStatusZoneRightOffset },
    [pscustomobject]@{ Name = "Notifications"; LeftOffset = [int]$hotCornersConfig.notificationCenterZoneLeftOffset; RightOffset = [int]$hotCornersConfig.notificationCenterZoneRightOffset },
    [pscustomobject]@{ Name = "Date"; LeftOffset = [int]$hotCornersConfig.calendarPopupZoneLeftOffset; RightOffset = [int]$hotCornersConfig.calendarPopupZoneRightOffset }
  )

  for ($zoneIndex = 0; $zoneIndex -lt $fallbackZones.Count; $zoneIndex++) {
    $zone = $fallbackZones[$zoneIndex]
    if ($zone.LeftOffset -le $zone.RightOffset) {
      Write-Warning "$($zone.Name) top-bar fallback zone has an empty or reversed range."
      $VerificationFailed = $true
    }
    if ($zoneIndex -gt 0) {
      $previousZone = $fallbackZones[$zoneIndex - 1]
      if ($previousZone.RightOffset -le $zone.LeftOffset) {
        Write-Warning "$($previousZone.Name) and $($zone.Name) top-bar fallback zones overlap; one click could launch two actions."
        $VerificationFailed = $true
      }
    }
  }
}

if (Test-Path -LiteralPath $HotCornersScriptPath) {
  $hotCornersScript = Get-Content -LiteralPath $HotCornersScriptPath -Raw
  if ($hotCornersScript -match 'NudgeWindowsOutOfBar\(') {
    Write-Warning "Hot-corners helper is moving app windows again. Do not nudge/SetWindowPos normal windows from the background helper; it caused maximize/navigation regressions."
    $VerificationFailed = $true
  }

  if ($hotCornersScript -match '\[System\.Windows\.Forms\.Screen\]::PrimaryScreen\.Bounds' -or $hotCornersScript -notmatch 'Screen\]::FromPoint') {
    Write-Warning "Hot-corner click detection is primary-monitor-only. Negative-coordinate app clicks can be mistaken for the top-left Show Desktop corner."
    $VerificationFailed = $true
  }

  if ($hotCornersScript -notmatch '\$X -lt \$left.*\$X -gt \$right.*\$Y -lt \$top.*\$Y -gt \$bottom') {
    Write-Warning "Hot-corner detection does not reject points outside the selected monitor bounds. Ordinary app clicks may trigger Show Desktop."
    $VerificationFailed = $true
  }

  if ($hotCornersScript -notmatch 'IsFancyToolbarAtPoint' -or $hotCornersScript -notmatch '\$fallbackTopBarClick') {
    Write-Warning "Top-bar fallback routing cannot distinguish a working Seelen hit target from a click-through one. This can double-fire responsive toolbar items."
    $VerificationFailed = $true
  }

  if ($hotCornersScript -notmatch 'SetThreadDpiAwarenessContext' -or $hotCornersScript -notmatch '\$physicalTopBarPixels' -or $hotCornersScript -notmatch '\$topBarHorizontalScale') {
    Write-Warning "Top-bar fallback routing is not DPI-coordinate-safe. GetCursorPos uses physical pixels, so monitor bounds, toolbar height, and horizontal offsets must use the same per-monitor coordinate space."
    $VerificationFailed = $true
  }
}

if (Test-Path -LiteralPath $ShortcutPath) {
  Write-Host ""
  Write-Host "settings_shortcuts.json:"
  Get-Content -LiteralPath $ShortcutPath
}

Write-Host ""
Write-Host "Windows Search web-result suppression:"
Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -ErrorAction SilentlyContinue |
  Select-Object BingSearchEnabled,CortanaConsent | Format-List
Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -ErrorAction SilentlyContinue |
  Select-Object IsWebSearchEnabled,HasSetWebSearchEnabledStateOnUpdate | Format-List

if (Test-Path -LiteralPath $PowerToysSettingsPath) {
  Write-Host ""
  Write-Host "PowerToys launcher module state:"
  (Get-Content -LiteralPath $PowerToysSettingsPath -Raw | ConvertFrom-Json).enabled |
    Select-Object "PowerToys Run", CmdPal | Format-List
}

if (Test-Path -LiteralPath $PowerToysRunSettingsPath) {
  Write-Host ""
  Write-Host "PowerToys Run hotkey:"
  (Get-Content -LiteralPath $PowerToysRunSettingsPath -Raw | ConvertFrom-Json).properties |
    Select-Object maximum_number_of_results,clear_input_on_launch,open_powerlauncher | Format-List

  Write-Host "PowerToys Run enabled Spotlight providers:"
  Get-Content -LiteralPath $PowerToysRunSettingsPath -Raw |
    ConvertFrom-Json |
    Select-Object -ExpandProperty plugins |
    Where-Object { -not $_.Disabled } |
    Select-Object Name,ActionKeyword,IsGlobal |
    Format-Table -AutoSize
}

$commandPalettePackage = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "Packages") -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "Microsoft.CommandPalette_*" } |
  Select-Object -First 1
if ($commandPalettePackage) {
  $commandPaletteSettingsPath = Join-Path $commandPalettePackage.FullName "LocalState\settings.json"
  if (Test-Path -LiteralPath $commandPaletteSettingsPath) {
    Write-Host ""
    $commandPaletteSettings = Get-Content -LiteralPath $commandPaletteSettingsPath -Raw | ConvertFrom-Json
    Write-Host "Command Palette hotkey and summon behavior:"
    $commandPaletteSettings | Select-Object Hotkey,SummonOn,BackdropStyle,Theme | Format-List
    Write-Host "Command Palette enabled Spotlight providers:"
    $commandPaletteSettings.ProviderSettings.PSObject.Properties |
      Where-Object { $_.Value.IsEnabled } |
      Select-Object Name |
      Format-Table -AutoSize
    Write-Host "Command Palette web search provider:"
    $commandPaletteSettings.ProviderSettings.'com.microsoft.cmdpal.builtin.websearch' |
      Select-Object IsEnabled |
      Format-List
  }
}

Write-Host ""
Write-Host "Hot corners startup:"
$hotCornerStartup = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\Mac Makeover Hot Corners.lnk"
if (Test-Path -LiteralPath $hotCornerStartup) {
  Write-Host "Hot corners Startup shortcut: $hotCornerStartup"
} else {
  Write-Host "Hot corners Startup shortcut not found."
}
$hotCornerProcesses = @(
  Get-CimInstance Win32_Process |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "*start-hot-corners.ps1*" }
)
$hotCornerProcesses |
  Select-Object ProcessId,Name,CommandLine |
  Format-List

$menuHostProcesses = @(Get-Process -Name MacMakeover.MenuHost -ErrorAction SilentlyContinue)
if ($menuHostProcesses.Count) {
  Write-Host "MenuHost resident process:"
  $menuHostProcesses | Select-Object Id,Responding,CPU,StartTime | Format-Table -AutoSize
} else {
  Write-Warning "MacMakeover.MenuHost is not running. Start/restart hot corners so Apple/Control Center clicks do not cold-launch."
  $VerificationFailed = $true
}

foreach ($hotCornerProcess in $hotCornerProcesses) {
  if ($hotCornerProcess.Name -ieq "pwsh.exe") {
    Write-Warning "Hot-corners/top-bar helper is running under pwsh.exe. WPF popovers rendered invisibly from pwsh runspaces during QA; run scripts\install-hot-corners.ps1 -StartNow to use Windows PowerShell."
    $VerificationFailed = $true
  }
}

Write-Host ""
Write-Host "Spotlight custom shortcuts:"
$shortcutDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Mac Makeover"
if (Test-Path -LiteralPath $shortcutDir) {
  Get-ChildItem -LiteralPath $shortcutDir -Filter "*.lnk" |
    Select-Object Name,LastWriteTime |
    Format-Table -AutoSize
} else {
  Write-Host "Shortcut folder not found: $shortcutDir"
}

if (Test-Path -LiteralPath $LogPath) {
  Write-Host ""
  Write-Host "Recent Seelen log health lines:"
  Get-Content -LiteralPath $LogPath -Tail 120 |
    Select-String -Pattern "SerdeYaml|error|failed|panic|Ready|fancy-toolbar" -CaseSensitive:$false
}

if ($CaptureScreenshot) {
  $qaDir = Join-Path $PackageRoot ("qa\visual-qa-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
  New-Item -ItemType Directory -Force -Path $qaDir | Out-Null
  $desktop = Join-Path $qaDir "desktop.png"
  $top = Join-Path $qaDir "top-130.png"
  $bottom = Join-Path $qaDir "bottom-240.png"
  $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue

  $dpiSignature = @"
using System;
using System.Runtime.InteropServices;

public static class MacMakeoverVerifyDpi {
  [DllImport("user32.dll")]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
}
"@
  Add-Type -TypeDefinition $dpiSignature -ErrorAction SilentlyContinue
  [MacMakeoverVerifyDpi]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $screens = @(
    [System.Windows.Forms.Screen]::AllScreens |
      Sort-Object -Property @{Expression = "Primary"; Descending = $true}, DeviceName
  )
  $virtualBounds = [System.Windows.Forms.SystemInformation]::VirtualScreen

  if ($ffmpeg) {
    & $ffmpeg.Source -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 1 -i desktop -vframes 1 $desktop
  } else {
    $bmp = New-Object System.Drawing.Bitmap $virtualBounds.Width, $virtualBounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($virtualBounds.X, $virtualBounds.Y, 0, 0, $bmp.Size)
    $bmp.Save($desktop, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()
  }

  $image = [System.Drawing.Bitmap]::FromFile($desktop)
  try {
    $imageWidth = $image.Width
    $imageHeight = $image.Height
  } finally {
    $image.Dispose()
  }

  if ($imageWidth -ne $virtualBounds.Width -or $imageHeight -ne $virtualBounds.Height) {
    Write-Warning "Captured virtual desktop is ${imageWidth}x${imageHeight}, but DPI-aware virtual bounds are $($virtualBounds.Width)x$($virtualBounds.Height). Per-monitor crops would be unreliable."
    $VerificationFailed = $true
  }

  $screenCaptures = @()
  for ($index = 0; $index -lt $screens.Count; $index++) {
    $screen = $screens[$index]
    $role = if ($screen.Primary) { "primary" } else { "secondary" }
    $prefix = "monitor-{0:D2}-{1}" -f ($index + 1), $role
    $screenFull = Join-Path $qaDir ($prefix + "-desktop.png")
    $screenTop = Join-Path $qaDir ($prefix + "-top-130.png")
    $screenBottom = Join-Path $qaDir ($prefix + "-bottom-240.png")
    $screenX = $screen.Bounds.Left - $virtualBounds.Left
    $screenY = $screen.Bounds.Top - $virtualBounds.Top
    $screenRect = [System.Drawing.Rectangle]::FromLTRB(
      $screenX,
      $screenY,
      $screenX + $screen.Bounds.Width,
      $screenY + $screen.Bounds.Height
    )
    $screenTopRect = [System.Drawing.Rectangle]::FromLTRB(
      $screenRect.Left,
      $screenRect.Top,
      $screenRect.Right,
      $screenRect.Top + [Math]::Min(130, $screenRect.Height)
    )
    $screenBottomRect = [System.Drawing.Rectangle]::FromLTRB(
      $screenRect.Left,
      $screenRect.Bottom - [Math]::Min(240, $screenRect.Height),
      $screenRect.Right,
      $screenRect.Bottom
    )

    Save-Crop -Source $desktop -Destination $screenFull -Rectangle $screenRect
    Save-Crop -Source $desktop -Destination $screenTop -Rectangle $screenTopRect
    Save-Crop -Source $desktop -Destination $screenBottom -Rectangle $screenBottomRect

    $screenCaptures += [pscustomobject]@{
      Device = $screen.DeviceName
      Primary = $screen.Primary
      Bounds = $screen.Bounds
      Full = $screenFull
      Top = $screenTop
      Bottom = $screenBottom
      TopLuma = Get-ImageAverageLuma -Path $desktop -X $screenRect.Left -Width $screenRect.Width -Y $screenRect.Top -Height ([Math]::Min(38, $screenRect.Height))
      BottomLuma = Get-ImageAverageLuma -Path $desktop -X $screenRect.Left -Width $screenRect.Width -Y ([Math]::Max($screenRect.Top, $screenRect.Bottom - 92)) -Height ([Math]::Min(92, $screenRect.Height))
    }
  }

  $primaryCapture = $screenCaptures | Where-Object Primary | Select-Object -First 1
  if (-not $primaryCapture) {
    throw "No primary display was found while creating visual QA crops."
  }
  Copy-Item -LiteralPath $primaryCapture.Top -Destination $top -Force
  Copy-Item -LiteralPath $primaryCapture.Bottom -Destination $bottom -Force

  $lockProcesses = @(Get-Process -Name LockApp,LogonUI -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName)
  $topLuma = $primaryCapture.TopLuma
  $bottomLuma = $primaryCapture.BottomLuma

  Write-Host ""
  Write-Host "Visual QA capture:"
  Write-Host "  Full virtual desktop: $desktop"
  Write-Host "  Primary top:          $top"
  Write-Host "  Primary bottom:       $bottom"
  foreach ($capture in $screenCaptures) {
    Write-Host "  $($capture.Device) primary=$($capture.Primary) bounds=$($capture.Bounds)"
    Write-Host "    Full:   $($capture.Full)"
    Write-Host "    Top:    $($capture.Top)"
    Write-Host "    Bottom: $($capture.Bottom)"
    Write-Host "    Luma:   top=$($capture.TopLuma), bottom=$($capture.BottomLuma)"
  }
  Write-Host "  Lock-screen processes: $($lockProcesses -join ', ')"
  Write-Host "  Primary top-strip average luminance: $topLuma"
  Write-Host "  Primary bottom-strip average luminance: $bottomLuma"

  if ($lockProcesses -contains "LogonUI") {
    Write-Warning "LogonUI is running. If the screenshot shows the lock screen, unlock and rerun for visual signoff."
  }

  foreach ($capture in $screenCaptures) {
    if ($capture.TopLuma -and $capture.TopLuma -gt 150) {
      Write-Warning "$($capture.Device) top strip is bright. That can mean the Seelen menu bar is missing, hidden, or the capture is the lock screen."
    }
  }
}

if ($VerificationFailed) {
  throw "Mac makeover verification found blocking issues. Fix the warnings above and rerun verify.ps1."
}
