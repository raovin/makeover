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
    [int]$Height
  )

  Add-Type -AssemblyName System.Drawing
  $image = [System.Drawing.Bitmap]::FromFile($Path)
  try {
    $yEnd = [Math]::Min($image.Height, $Y + $Height)
    $xStep = [Math]::Max(1, [int]($image.Width / 160))
    $yStep = [Math]::Max(1, [int](($yEnd - $Y) / 12))
    $total = 0.0
    $count = 0

    for ($yy = $Y; $yy -lt $yEnd; $yy += $yStep) {
      for ($xx = 0; $xx -lt $image.Width; $xx += $xStep) {
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
foreach ($path in @($SettingsPath, $ShortcutPath, $ToolbarPath, $ThemePath, $AppleMenuScriptPath, $AppleMenuInstallerPath, $ControlCenterScriptPath, $ControlCenterInstallerPath, $NetworkInstallerPath, $BluetoothInstallerPath, $NotificationCenterInstallerPath, $HotCornersScriptPath, $HotCornersConfigPath, $MenuHostProjectPath, $MenuHostExePath)) {
  if (Test-Path -LiteralPath $path) {
    "OK   {0}" -f $path
  } else {
    "MISS {0}" -f $path
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
  } elseif (-not ($appleMenuCommand -match "conhost\.exe" -and $appleMenuCommand -match "Show-MacAppleMenu\.ps1")) {
    Write-Warning "Apple menu is not registered to the conhost launcher. Re-run scripts\Install-AppleMenuHandler.ps1."
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
  } elseif (-not ($notificationCenterCommand -match "conhost\.exe" -and $notificationCenterCommand -match "Invoke-MacAction\.ps1" -and $notificationCenterCommand -match "NotificationCenter")) {
    Write-Warning "Notification Center is not registered to the conhost launcher. Re-run scripts\Install-MacNotificationCenterHandler.ps1."
    $VerificationFailed = $true
  }
} else {
  Write-Warning "Notification Center protocol handler is missing: macmakeover-notification-center:"
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

  if ($toolbarRaw -match 'open\("macmakeover-apple-menu:"\)') {
    Write-Warning "Apple-logo clicks are registered directly to the macmakeover URI protocol. Normal Apple clicks should be handled by start-hot-corners.ps1 (instant); the URI is fallback plumbing."
    $VerificationFailed = $true
  } else {
    Write-Host "  OK Apple clicks are helper-owned, not URI-launched from Seelen."
  }

  $shellPopupHideCount = ([regex]::Matches($toolbarRaw, 'Seelen UI.*ShellHost.*MacMakeover\\.MenuHost|helper\\.test\\(name\\).*helper\\.test\\(title\\)')).Count
  if ($shellPopupHideCount -lt 2) {
    Write-Warning "Focused-app labels should hide Seelen UI/ShellHost/MacMakeover.MenuHost helper surfaces by name and title. Otherwise menu popups pollute the Mac menu bar with implementation labels."
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

  # User requirement (explicit, 2026-07-06): keep the Mac menu bar center quiet.
  # CPU/RAM/NET/Battery in the center made the bar read like misplaced menu options.
  if ($toolbarRaw -match '(?s)center:\s*\n\s*-' -or $toolbarRaw -match '(?s)center:.*(Cpu|Memory|NetworkStatistics|macmakeover-battery-status).*right:') {
    Write-Warning "The center of the menu bar should stay quiet/empty. Do not put CPU/RAM/NET/Battery readouts in the middle."
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

  if (-not $hotCornersConfig.appleMenuClickEnabled) {
    Write-Warning "Helper-owned Apple click routing is disabled."
    $VerificationFailed = $true
  }

  foreach ($itemOwnedRoute in @(
    "networkFlyoutClickEnabled",
    "batteryQuickSettingsClickEnabled",
    "controlCenterClickEnabled",
    "notificationCenterClickEnabled",
    "calendarPopupClickEnabled"
  )) {
    $routeProperty = $hotCornersConfig.PSObject.Properties[$itemOwnedRoute]
    if ($routeProperty -and [bool]$routeProperty.Value) {
      Write-Warning "$itemOwnedRoute should be false. Right-side menu-bar controls are item-owned now, not pixel-zone-routed by the helper."
      $VerificationFailed = $true
    }
  }
}

if (Test-Path -LiteralPath $HotCornersScriptPath) {
  $hotCornersScript = Get-Content -LiteralPath $HotCornersScriptPath -Raw
  if ($hotCornersScript -match 'HashSet<IntPtr>\s+NudgedWindows|NudgedWindows\.Contains') {
    Write-Warning "The window-under-menu-bar nudge is one-shot per HWND again. Repeated app restores can still park a title bar under the menu bar."
    $VerificationFailed = $true
  }

  if ($hotCornersScript -match 'NudgeWindowsOutOfBar' -and ($hotCornersScript -notmatch 'LastNudgedWindows' -or $hotCornersScript -notmatch 'TotalMilliseconds\s*<\s*1200')) {
    Write-Warning "The window-under-menu-bar nudge should use a short cooldown, not a permanent per-window block."
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

  if ($ffmpeg) {
    & $ffmpeg.Source -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 1 -i desktop -vframes 1 $desktop
  } else {
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
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bmp.Size)
    $bmp.Save($desktop, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()
  }

  Add-Type -AssemblyName System.Drawing
  $image = [System.Drawing.Bitmap]::FromFile($desktop)
  try {
    $imageWidth = $image.Width
    $imageHeight = $image.Height
  } finally {
    $image.Dispose()
  }

  Save-Crop -Source $desktop -Destination $top -Rectangle ([System.Drawing.Rectangle]::FromLTRB(0, 0, $imageWidth, [Math]::Min(130, $imageHeight)))
  Save-Crop -Source $desktop -Destination $bottom -Rectangle ([System.Drawing.Rectangle]::FromLTRB(0, [Math]::Max(0, $imageHeight - 240), $imageWidth, $imageHeight))

  $lockProcesses = @(Get-Process -Name LockApp,LogonUI -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName)
  $topLuma = Get-ImageAverageLuma -Path $desktop -Y 0 -Height 38
  $bottomLuma = Get-ImageAverageLuma -Path $desktop -Y ([Math]::Max(0, $imageHeight - 92)) -Height 92

  Write-Host ""
  Write-Host "Visual QA capture:"
  Write-Host "  Full:   $desktop"
  Write-Host "  Top:    $top"
  Write-Host "  Bottom: $bottom"
  Write-Host "  Lock-screen processes: $($lockProcesses -join ', ')"
  Write-Host "  Top-strip average luminance: $topLuma"
  Write-Host "  Bottom-strip average luminance: $bottomLuma"

  if ($lockProcesses -contains "LogonUI") {
    Write-Warning "LogonUI is running. If the screenshot shows the lock screen, unlock and rerun for visual signoff."
  }

  if ($topLuma -and $topLuma -gt 150) {
    Write-Warning "Top strip is bright. That can mean the Seelen menu bar is missing, hidden, or the capture is the lock screen."
  }
}

if ($VerificationFailed) {
  throw "Mac makeover verification found blocking issues. Fix the warnings above and rerun verify.ps1."
}
