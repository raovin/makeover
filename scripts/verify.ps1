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
$AppleMenuLauncherPath = Join-Path $PackageRoot "scripts\Launch-MacAppleMenu.vbs"
$AppleMenuCommandPath = "HKCU:\Software\Classes\macmakeover-apple-menu\shell\open\command"

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
foreach ($path in @($SettingsPath, $ShortcutPath, $ToolbarPath, $ThemePath, $AppleMenuScriptPath, $AppleMenuLauncherPath)) {
  "{0}  {1}" -f ($(if (Test-Path -LiteralPath $path) { "OK " } else { "MISS" })), $path
}

Write-Host ""
Write-Host "Apple menu launcher:"
if (Test-Path -Path $AppleMenuCommandPath) {
  $appleMenuCommand = (Get-Item -Path $AppleMenuCommandPath).GetValue("")
  Write-Host "  $appleMenuCommand"
  if ($appleMenuCommand -match "wscript\.exe") {
    Write-Warning "Apple menu is registered via wscript.exe, which is blocked by this PC's security policy (the menu will not open). Re-run scripts\Install-AppleMenuHandler.ps1 to switch to conhost."
  } elseif ($appleMenuCommand -notmatch "conhost\.exe" -or $appleMenuCommand -notmatch "Show-MacAppleMenu\.ps1") {
    Write-Warning "Apple menu is not registered to the conhost launcher. Re-run scripts\Install-AppleMenuHandler.ps1."
  }
} else {
  Write-Warning "Apple menu protocol handler is missing: macmakeover-apple-menu:"
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
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -like "*start-hot-corners.ps1*" } |
  Select-Object ProcessId,CommandLine |
  Format-List

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
