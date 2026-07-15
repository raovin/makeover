[CmdletBinding()]
param(
  [switch]$ApplyWallpaper,
  [switch]$ApplyCursors,
  [switch]$ApplyAccent,
  [switch]$SkipSearchTweaks,
  [switch]$SkipPowerToysRestore,
  [switch]$SkipHotCorners,
  [switch]$SkipSpotlightShortcuts,
  [switch]$SkipSeelenRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot
$ConfigRoot = Join-Path $PackageRoot "config\seelen"
$PowerToysConfigRoot = Join-Path $PackageRoot "config\powertoys"
$CommandPaletteConfigRoot = Join-Path $PackageRoot "config\command-palette"
$AssetsRoot = Join-Path $PackageRoot "assets"
$SeelenRoot = Join-Path $env:APPDATA "com.seelen.seelen-ui"
$BackupRoot = Join-Path $env:TEMP ("mac-makeover-seelen-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$PowerToysBackupRoot = Join-Path $env:TEMP ("mac-makeover-powertoys-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))

function Ensure-Directory {
  param([string]$Path)
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Copy-FileIfExists {
  param(
    [string]$Source,
    [string]$Destination
  )
  if (Test-Path -LiteralPath $Source) {
    Ensure-Directory (Split-Path -Parent $Destination)
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
  }
}

function Copy-TreeContents {
  param(
    [string]$Source,
    [string]$Destination
  )
  if (-not (Test-Path -LiteralPath $Source)) {
    return
  }

  Ensure-Directory $Destination
  Get-ChildItem -LiteralPath $Source -Recurse -File | ForEach-Object {
    $relative = [System.IO.Path]::GetRelativePath($Source, $_.FullName)
    $target = Join-Path $Destination $relative
    Ensure-Directory (Split-Path -Parent $target)
    Copy-Item -LiteralPath $_.FullName -Destination $target -Force
  }
}

function Save-JsonFile {
  param(
    [object]$Object,
    [string]$Path
  )

  # Write UTF-8 without a BOM. Windows PowerShell 5.1's `Set-Content -Encoding utf8` prepends a
  # BOM, which Seelen's serde JSON reader and some Command Palette/PowerToys parsers reject.
  $json = $Object | ConvertTo-Json -Depth 100
  [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Set-CommandPaletteSpotlightSettings {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  $settings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

  $settings.Hotkey = [pscustomobject]@{
    win = $false
    ctrl = $false
    alt = $true
    shift = $false
    code = 32
    key = ""
  }
  $settings.UseLowLevelGlobalHotkey = $true
  $settings.HighlightSearchOnActivate = $true
  $settings.KeepPreviousQuery = $false
  $settings.IgnoreShortcutWhenFullscreen = $true
  $settings.BackdropStyle = "Acrylic"
  $settings.BackdropOpacity = 100
  $settings.Theme = "Default"

  $allowedProviders = @(
    "Files",
    "WindowWalker",
    "AllApps",
    "com.microsoft.cmdpal.builtin.core",
    "com.microsoft.cmdpal.builtin.windowssettings",
    "Microsoft.PowerToys.SparseApp_8wekyb3d8bbwe!PowerToys.CmdPalExtension!PowerToys",
    "com.microsoft.cmdpal.builtin.calculator",
    "com.microsoft.cmdpal.builtin.system",
    "Windows.ClipboardHistory",
    "Bookmarks",
    "com.microsoft.cmdpal.builtin.run"
  )

  if ($settings.ProviderSettings) {
    foreach ($provider in $settings.ProviderSettings.PSObject.Properties) {
      $provider.Value.IsEnabled = $allowedProviders -contains $provider.Name
    }
  }

  if ($settings.Aliases -and $settings.Aliases.PSObject.Properties.Name -contains "??") {
    $settings.Aliases.PSObject.Properties.Remove("??")
  }

  Save-JsonFile -Object $settings -Path $Path
}

function Set-PowerToysRunSpotlightSettings {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  $settings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  $settings.properties.maximum_number_of_results = 8
  $settings.properties.clear_input_on_launch = $true
  $settings.properties.search_result_preference = "most_recently_used"
  $settings.properties.search_type_preference = "application_name"
  $settings.properties.search_wait_for_slow_results = $false
  $settings.properties.search_query_results_with_delay = $true
  $settings.properties.open_powerlauncher = [pscustomobject]@{
    win = $false
    ctrl = $false
    alt = $true
    shift = $false
    code = 32
    key = ""
  }

  $allowedPlugins = @(
    "Calculator",
    "Folder",
    "History",
    "Windows Search",
    "PowerToys",
    "Program",
    "Shell",
    "Windows System Commands",
    "Windows settings",
    "Window Walker"
  )

  foreach ($plugin in $settings.plugins) {
    $plugin.Disabled = -not ($allowedPlugins -contains $plugin.Name)
  }

  Save-JsonFile -Object $settings -Path $Path
}

function Register-MacMakeoverAppleMenu {
  # Register via conhost --headless. Do NOT use wscript.exe: this PC's security policy
  # blocks wscript from launching PowerShell ("Windows Script Host failed"), which silently
  # broke the old VBS launcher. The installer below registers the conhost handler.
  $installer = Join-Path $PSScriptRoot "Install-AppleMenuHandler.ps1"
  if (-not (Test-Path -LiteralPath $installer)) {
    Write-Warning "Apple menu handler installer was not found, so the protocol handler was not registered: $installer"
    return
  }

  & $installer
  Write-Host "Apple menu protocol registered (conhost --headless launcher): macmakeover-apple-menu:"
}

function Register-MacMakeoverControlCenter {
  $installer = Join-Path $PSScriptRoot "Install-MacControlCenterHandler.ps1"
  if (-not (Test-Path -LiteralPath $installer)) {
    Write-Warning "Control Center handler installer was not found, so the protocol handler was not registered: $installer"
    return
  }

  & $installer
  Write-Host "Control Center protocol registered (conhost --headless launcher): macmakeover-control-center:"
}

function Register-MacMakeoverNetwork {
  $installer = Join-Path $PSScriptRoot "Install-MacNetworkHandler.ps1"
  if (-not (Test-Path -LiteralPath $installer)) {
    Write-Warning "Network handler installer was not found, so the protocol handler was not registered: $installer"
    return
  }

  & $installer
  Write-Host "Network protocol registered (conhost --headless launcher): macmakeover-network:"
}

function Register-MacMakeoverBluetooth {
  $installer = Join-Path $PSScriptRoot "Install-MacBluetoothHandler.ps1"
  if (-not (Test-Path -LiteralPath $installer)) {
    Write-Warning "Bluetooth handler installer was not found, so the protocol handler was not registered: $installer"
    return
  }

  & $installer
  Write-Host "Bluetooth protocol registered (conhost --headless launcher): macmakeover-bluetooth:"
}

function Register-MacMakeoverNotificationCenter {
  $installer = Join-Path $PSScriptRoot "Install-MacNotificationCenterHandler.ps1"
  if (-not (Test-Path -LiteralPath $installer)) {
    Write-Warning "Notification Center handler installer was not found, so the protocol handler was not registered: $installer"
    return
  }

  & $installer
  Write-Host "Notification Center protocol registered (native ms-actioncenter launcher): macmakeover-notification-center:"
}

if (-not (Test-Path -LiteralPath $ConfigRoot)) {
  throw "Backup config was not found. Run scripts\backup-current.ps1 first. Missing: $ConfigRoot"
}

if (-not $SkipSeelenRestart) {
  Get-Process | Where-Object { $_.ProcessName -match "seelen|slu" } | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

if (Test-Path -LiteralPath $SeelenRoot) {
  Ensure-Directory $BackupRoot
  Copy-TreeContents $SeelenRoot $BackupRoot
  Write-Host "Existing Seelen config backed up to: $BackupRoot"
}

Ensure-Directory $SeelenRoot

Copy-FileIfExists (Join-Path $ConfigRoot "settings.json") (Join-Path $SeelenRoot "settings.json")
Copy-FileIfExists (Join-Path $ConfigRoot "settings_by_app.yml") (Join-Path $SeelenRoot "settings_by_app.yml")
Copy-FileIfExists (Join-Path $ConfigRoot "settings_shortcuts.json") (Join-Path $SeelenRoot "settings_shortcuts.json")

Copy-FileIfExists (Join-Path $ConfigRoot "data\seelen-fancy-toolbar\state.yml") (Join-Path $SeelenRoot "data\seelen-fancy-toolbar\state.yml")
Copy-FileIfExists (Join-Path $ConfigRoot "data\seelen-weg\state.yml") (Join-Path $SeelenRoot "data\seelen-weg\state.yml")
Copy-FileIfExists (Join-Path $ConfigRoot "data\seelen-apps-menu\favorites.json") (Join-Path $SeelenRoot "data\seelen-apps-menu\favorites.json")
Copy-FileIfExists (Join-Path $ConfigRoot "data\seelen-settings\welcomeModal.json") (Join-Path $SeelenRoot "data\seelen-settings\welcomeModal.json")
Copy-TreeContents (Join-Path $ConfigRoot "themes\macos-glass") (Join-Path $SeelenRoot "themes\macos-glass")
# User plugins (e.g. @vineeth/tb-network-status fallback). Keep copying them so old
# toolbar backups still restore, even though the current toolbar uses the custom
# MenuHost network panel for reliable click behavior.
Copy-TreeContents (Join-Path $ConfigRoot "plugins") (Join-Path $SeelenRoot "plugins")

# Hard guardrail: keep Seelen shortcuts disabled for normal Alt+Tab and lock-screen input behavior.
$shortcutsPath = Join-Path $SeelenRoot "settings_shortcuts.json"
[System.IO.File]::WriteAllText($shortcutsPath, '{"enabled":false,"shortcuts":{}}', (New-Object System.Text.UTF8Encoding($false)))

Register-MacMakeoverAppleMenu
Register-MacMakeoverControlCenter
Register-MacMakeoverNetwork
Register-MacMakeoverBluetooth
Register-MacMakeoverNotificationCenter

if ($ApplyAccent) {
  $accentReg = Join-Path $PackageRoot "registry\hkcu-explorer-accent.reg"
  $dwmReg = Join-Path $PackageRoot "registry\hkcu-dwm.reg"
  if (Test-Path -LiteralPath $accentReg) { reg import "$accentReg" | Out-Null }
  if (Test-Path -LiteralPath $dwmReg) { reg import "$dwmReg" | Out-Null }
}

if (-not $SkipSearchTweaks) {
  $searchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
  $settingsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
  New-Item -Path $searchKey -Force | Out-Null
  New-Item -Path $settingsKey -Force | Out-Null

  New-ItemProperty -Path $searchKey -Name "BingSearchEnabled" -PropertyType DWord -Value 0 -Force | Out-Null
  New-ItemProperty -Path $searchKey -Name "CortanaConsent" -PropertyType DWord -Value 0 -Force | Out-Null
  New-ItemProperty -Path $settingsKey -Name "IsWebSearchEnabled" -PropertyType DWord -Value 0 -Force | Out-Null
  New-ItemProperty -Path $settingsKey -Name "HasSetWebSearchEnabledStateOnUpdate" -PropertyType DWord -Value 1 -Force | Out-Null

  try {
    $policyKey = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    New-Item -Path $policyKey -Force | Out-Null
    New-ItemProperty -Path $policyKey -Name "DisableSearchBoxSuggestions" -PropertyType DWord -Value 1 -Force | Out-Null
  } catch {
    Write-Warning "Could not write the managed Search policy key. Normal per-user SearchSettings were still applied. Details: $($_.Exception.Message)"
  }

  Get-Process SearchHost -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

if (-not $SkipPowerToysRestore) {
  $powerToysRoot = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys"
  $commandPalettePackage = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "Packages") -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "Microsoft.CommandPalette_*" } |
    Select-Object -First 1

  if ((Test-Path -LiteralPath $PowerToysConfigRoot) -or (Test-Path -LiteralPath $CommandPaletteConfigRoot)) {
    Get-Process | Where-Object { $_.ProcessName -match "PowerToys|CmdPal|CommandPalette" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }

  if (Test-Path -LiteralPath $PowerToysConfigRoot) {
    if (Test-Path -LiteralPath $powerToysRoot) {
      Ensure-Directory $PowerToysBackupRoot
      Copy-TreeContents $powerToysRoot $PowerToysBackupRoot
      Write-Host "Existing PowerToys config backed up to: $PowerToysBackupRoot"
    }
    Copy-TreeContents $PowerToysConfigRoot $powerToysRoot
    Set-PowerToysRunSpotlightSettings -Path (Join-Path $powerToysRoot "PowerToys Run\settings.json")
  }

  if (Test-Path -LiteralPath (Join-Path $CommandPaletteConfigRoot "settings.json")) {
    if ($commandPalettePackage) {
      Copy-FileIfExists (Join-Path $CommandPaletteConfigRoot "settings.json") (Join-Path $commandPalettePackage.FullName "LocalState\settings.json")
      Set-CommandPaletteSpotlightSettings -Path (Join-Path $commandPalettePackage.FullName "LocalState\settings.json")
    } else {
      Write-Warning "Command Palette package was not found. Install or launch PowerToys Command Palette, then rerun restore if needed."
    }
  }

  $powerToysExe = Join-Path $env:LOCALAPPDATA "PowerToys\PowerToys.exe"
  if (Test-Path -LiteralPath $powerToysExe) {
    Start-Process -FilePath $powerToysExe -WindowStyle Hidden
  }
}

if (-not $SkipSpotlightShortcuts) {
  & (Join-Path $PSScriptRoot "install-spotlight-shortcuts.ps1")
}

if (-not $SkipHotCorners) {
  & (Join-Path $PSScriptRoot "install-hot-corners.ps1") -StartNow
}

if ($ApplyWallpaper) {
  $wallpaper = Join-Path $AssetsRoot "wallpapers\mac-wallpaper.jpg"
  if (Test-Path -LiteralPath $wallpaper) {
    $targetDir = Join-Path $env:USERPROFILE "Pictures\mac-makeover"
    Ensure-Directory $targetDir
    $target = Join-Path $targetDir "mac-wallpaper.jpg"
    Copy-Item -LiteralPath $wallpaper -Destination $target -Force

    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "10"
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value "0"

    $signature = @"
using System.Runtime.InteropServices;
public class WallpaperSetter {
  [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
  public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue
    [WallpaperSetter]::SystemParametersInfo(20, 0, $target, 3) | Out-Null
    Write-Host "Wallpaper applied: $target"
  }
}

if ($ApplyCursors) {
  $cursorSource = Join-Path $AssetsRoot "cursors\macOS-Regular-Windows"
  if (-not (Test-Path -LiteralPath $cursorSource)) {
    throw "Cursor source was not found: $cursorSource"
  }

  $cursorTarget = Join-Path $env:LOCALAPPDATA "MacMakeover\Cursors\macOS-Regular-Windows"
  Copy-TreeContents $cursorSource $cursorTarget

  $cursorMap = @{
    "" = "macOS-Regular Cursors"
    "Arrow" = "Pointer.cur"
    "Help" = "Help.cur"
    "AppStarting" = "Work.ani"
    "Wait" = "Busy.ani"
    "Crosshair" = "Cross.cur"
    "IBeam" = "Text.cur"
    "NWPen" = "Handwriting.cur"
    "SizeNS" = "Vert.cur"
    "SizeWE" = "Horz.cur"
    "SizeAll" = "Move.cur"
    "Grab" = "Move.cur"
    "UpArrow" = "Alternate.cur"
    "Hand" = "Link.cur"
    "Pin" = "Pin.cur"
    "Person" = "Person.cur"
    "Pan" = "Pan.cur"
    "Grabbing" = "Grabbing.cur"
    "Zoom-in" = "Zoom-in.cur"
    "Zoom-out" = "Zoom-out.cur"
    "No" = "Unavailiable.cur"
    "SizeNESW" = "Dng2.cur"
    "SizeNWSE" = "Dng1.cur"
  }

  foreach ($name in $cursorMap.Keys) {
    if ($name -eq "") {
      Set-Item "HKCU:\Control Panel\Cursors" -Value $cursorMap[$name]
    } else {
      Set-ItemProperty "HKCU:\Control Panel\Cursors" -Name $name -Value (Join-Path $cursorTarget $cursorMap[$name])
    }
  }

  rundll32.exe user32.dll,UpdatePerUserSystemParameters | Out-Null
  Write-Host "Cursor files copied and HKCU cursor values updated. A sign-out may be required."
}

if (-not $SkipSeelenRestart) {
  $task = Get-ScheduledTask -TaskPath "\Seelen\" -TaskName "Seelen UI Service" -ErrorAction SilentlyContinue
  if ($task) {
    Start-ScheduledTask -TaskPath "\Seelen\" -TaskName "Seelen UI Service"
    Start-Sleep -Seconds 10
  } else {
    Write-Warning "Seelen scheduled task was not found. Install or start Seelen UI manually."
  }
}

Write-Host "Restore complete."
