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
$LogPath = Join-Path $SeelenLocal "logs\Seelen UI.log"
$PowerToysSettingsPath = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\settings.json"
$PowerToysRunSettingsPath = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\PowerToys Run\settings.json"
$AppleMenuScriptPath = Join-Path $PackageRoot "scripts\Show-MacAppleMenu.ps1"
$AppleMenuInstallerPath = Join-Path $PackageRoot "scripts\Install-AppleMenuHandler.ps1"
$ControlCenterScriptPath = Join-Path $PackageRoot "scripts\Show-MacControlCenter.ps1"
$ControlCenterInstallerPath = Join-Path $PackageRoot "scripts\Install-MacControlCenterHandler.ps1"
$HotCornersScriptPath = Join-Path $PackageRoot "scripts\start-hot-corners.ps1"
$HotCornersConfigPath = Join-Path $PackageRoot "config\hot-corners.json"
$MenuHostProjectPath = Join-Path $PackageRoot "tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj"
$MenuHostExePath = Join-Path $PackageRoot "tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe"
$AppleMenuCommandPath = "HKCU:\Software\Classes\macmakeover-apple-menu\shell\open\command"
$ControlCenterCommandPath = "HKCU:\Software\Classes\macmakeover-control-center\shell\open\command"
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
foreach ($path in @($SettingsPath, $ShortcutPath, $ToolbarPath, $ThemePath, $AppleMenuScriptPath, $AppleMenuInstallerPath, $ControlCenterScriptPath, $ControlCenterInstallerPath, $HotCornersScriptPath, $HotCornersConfigPath, $MenuHostProjectPath, $MenuHostExePath)) {
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
    Write-Warning "Control Center is registered via wscript.exe, which is blocked by this PC's security policy. Re-run scripts\Install-MacControlCenterHandler.ps1 to switch to conhost."
    $VerificationFailed = $true
  } elseif (-not ($controlCenterCommand -match "conhost\.exe" -and $controlCenterCommand -match "Show-MacControlCenter\.ps1")) {
    Write-Warning "Control Center is not registered to the conhost launcher. Re-run scripts\Install-MacControlCenterHandler.ps1."
    $VerificationFailed = $true
  }
} else {
  Write-Warning "Control Center protocol handler is missing: macmakeover-control-center:"
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

  if ($toolbarRaw -match 'open\("macmakeover-(apple-menu|control-center):"\)') {
    Write-Warning "Toolbar clicks are registered directly to macmakeover URI protocols. Normal Apple/Control Center clicks should be handled by start-hot-corners.ps1 to avoid multi-second ShellExecute/PowerShell launch lag."
    $VerificationFailed = $true
  } else {
    Write-Host "  OK normal Apple/Control Center clicks are helper-owned, not URI-launched from Seelen."
  }

  if ($toolbarRaw -match 'Battery:|Charge rate:|return "Control Center";') {
    Write-Warning "Top-bar battery/control tooltips are enabled. They can overlap the custom Control Center popover."
    $VerificationFailed = $true
  }

  if ($toolbarRaw -notmatch 'LuWifi') {
    Write-Warning "Top-bar network affordance is missing. Keep the Wi-Fi/network glyph visible beside throughput numbers."
    $VerificationFailed = $true
  }
}

$menuHostSourcePath = Join-Path $PackageRoot "tools\MacMakeover.MenuHost\Program.cs"
if (Test-Path -LiteralPath $menuHostSourcePath) {
  $menuHostSource = Get-Content -LiteralPath $menuHostSourcePath -Raw
  if ($menuHostSource -notmatch 'Network Settings' -or $menuHostSource -notmatch 'ms-settings:network-status') {
    Write-Warning "MenuHost Control Center is missing the Network Settings action."
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

  if (-not $hotCornersConfig.appleMenuClickEnabled -or -not $hotCornersConfig.controlCenterClickEnabled) {
    Write-Warning "Helper-owned Apple/Control Center click routing is disabled."
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
