[CmdletBinding()]
param(
  [string]$SourceProject = "C:\Users\VineethRao\source\repos\mac-makeover"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot
$SeelenRoot = Join-Path $env:APPDATA "com.seelen.seelen-ui"
$PowerToysRoot = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys"
$ConfigRoot = Join-Path $PackageRoot "config\seelen"
$PowerToysConfigRoot = Join-Path $PackageRoot "config\powertoys"
$CommandPaletteConfigRoot = Join-Path $PackageRoot "config\command-palette"
$AssetsRoot = Join-Path $PackageRoot "assets"
$RegistryRoot = Join-Path $PackageRoot "registry"

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
    $sourceFullPath = [System.IO.Path]::GetFullPath($Source)
    $destinationFullPath = [System.IO.Path]::GetFullPath($Destination)
    if ([string]::Equals($sourceFullPath, $destinationFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      return
    }

    Ensure-Directory (Split-Path -Parent $Destination)
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
  }
}

function Copy-TreeFiltered {
  param(
    [string]$Source,
    [string]$Destination,
    [string[]]$ExcludeNames = @(),
    [string[]]$ExcludeExtensions = @()
  )

  if (-not (Test-Path -LiteralPath $Source)) {
    return
  }

  $sourceFullPath = [System.IO.Path]::GetFullPath($Source).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $destinationFullPath = [System.IO.Path]::GetFullPath($Destination).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  if ([string]::Equals($sourceFullPath, $destinationFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    return
  }

  Ensure-Directory $Destination
  Get-ChildItem -LiteralPath $Source -Recurse -File | ForEach-Object {
    if ($ExcludeNames -contains $_.Name) { return }
    if ($ExcludeExtensions -contains $_.Extension) { return }
    if ($_.Name -like "*.bak*" -or $_.Name -like "*.log") { return }

    $relative = [System.IO.Path]::GetRelativePath($Source, $_.FullName)
    $target = Join-Path $Destination $relative
    Ensure-Directory (Split-Path -Parent $target)
    Copy-Item -LiteralPath $_.FullName -Destination $target -Force
  }
}

function Export-RegKeyIfExists {
  param(
    [string]$Key,
    [string]$Destination
  )

  $null = reg query $Key 2>$null
  if ($LASTEXITCODE -eq 0) {
    Ensure-Directory (Split-Path -Parent $Destination)
    $null = reg export $Key $Destination /y
  }
}

function Write-Utf8NoBom {
  param(
    [string]$Path,
    [string]$Value
  )

  [System.IO.File]::WriteAllText($Path, $Value, (New-Object System.Text.UTF8Encoding($false)))
}

function Sanitize-CopiedTextFile {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  $text = Get-Content -LiteralPath $Path -Raw
  $text = $text -replace "(?m)^- Mac is reachable as .*$", "- Mac tailnet host/IP intentionally not stored here. Sign into Tailscale on the new device manually."
  $text = $text -replace 'on the Mac `aether-eclipse`', "on the personal Mac"
  $text = $text -replace "aether-eclipse\.taile[0-9a-z]+\.ts\.net", "<tailnet-host-redacted>"
  $text = $text -replace "100\.88\.171\.108", "<tailnet-ip-redacted>"
  Write-Utf8NoBom -Path $Path -Value $text
}

Ensure-Directory $ConfigRoot
Ensure-Directory $PowerToysConfigRoot
Ensure-Directory $CommandPaletteConfigRoot
Ensure-Directory $AssetsRoot
Ensure-Directory $RegistryRoot

if (-not (Test-Path -LiteralPath $SeelenRoot)) {
  throw "Seelen config root was not found: $SeelenRoot"
}

Copy-FileIfExists (Join-Path $SeelenRoot "settings.json") (Join-Path $ConfigRoot "settings.json")
Copy-FileIfExists (Join-Path $SeelenRoot "settings_by_app.yml") (Join-Path $ConfigRoot "settings_by_app.yml")
Copy-FileIfExists (Join-Path $SeelenRoot "settings_shortcuts.json") (Join-Path $ConfigRoot "settings_shortcuts.json")

Copy-FileIfExists (Join-Path $SeelenRoot "data\seelen-fancy-toolbar\state.yml") (Join-Path $ConfigRoot "data\seelen-fancy-toolbar\state.yml")
Copy-FileIfExists (Join-Path $SeelenRoot "data\seelen-weg\state.yml") (Join-Path $ConfigRoot "data\seelen-weg\state.yml")
Copy-FileIfExists (Join-Path $SeelenRoot "data\seelen-apps-menu\favorites.json") (Join-Path $ConfigRoot "data\seelen-apps-menu\favorites.json")
Copy-FileIfExists (Join-Path $SeelenRoot "data\seelen-settings\welcomeModal.json") (Join-Path $ConfigRoot "data\seelen-settings\welcomeModal.json")

Copy-TreeFiltered (Join-Path $SeelenRoot "themes\macos-glass") (Join-Path $ConfigRoot "themes\macos-glass")

if (Test-Path -LiteralPath $PowerToysRoot) {
  Copy-FileIfExists (Join-Path $PowerToysRoot "settings.json") (Join-Path $PowerToysConfigRoot "settings.json")
  Copy-FileIfExists (Join-Path $PowerToysRoot "PowerToys Run\settings.json") (Join-Path $PowerToysConfigRoot "PowerToys Run\settings.json")
}

$commandPalettePackage = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "Packages") -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "Microsoft.CommandPalette_*" } |
  Select-Object -First 1
if ($commandPalettePackage) {
  Copy-FileIfExists (Join-Path $commandPalettePackage.FullName "LocalState\settings.json") (Join-Path $CommandPaletteConfigRoot "settings.json")
}

if (Test-Path -LiteralPath $SourceProject) {
  $handoverDestination = Join-Path $PackageRoot "docs\CODEX-HANDOVER.md"
  Copy-FileIfExists (Join-Path $SourceProject "CODEX-HANDOVER.md") $handoverDestination
  Sanitize-CopiedTextFile $handoverDestination

  Copy-FileIfExists (Join-Path $SourceProject "CLAUDE.md") (Join-Path $PackageRoot "docs\CLAUDE.mac-makeover.md")
  Copy-FileIfExists (Join-Path $SourceProject "make-wallpaper.ps1") (Join-Path $AssetsRoot "source-scripts\make-wallpaper.ps1")
  Copy-FileIfExists (Join-Path $SourceProject "pin-apps.ps1") (Join-Path $AssetsRoot "source-scripts\pin-apps.ps1")
  Copy-FileIfExists (Join-Path $SourceProject "convert.ps1") (Join-Path $AssetsRoot "source-scripts\convert.ps1")
  Copy-FileIfExists (Join-Path $SourceProject "scripts\Show-MacAppleMenu.ps1") (Join-Path $PackageRoot "scripts\Show-MacAppleMenu.ps1")
  Copy-FileIfExists (Join-Path $SourceProject "scripts\Install-AppleMenuHandler.ps1") (Join-Path $PackageRoot "scripts\Install-AppleMenuHandler.ps1")
  $legacyLauncher = Join-Path $PackageRoot "scripts\Launch-MacAppleMenu.vbs"
  if (Test-Path -LiteralPath $legacyLauncher) {
    Remove-Item -LiteralPath $legacyLauncher -Force
  }
  Copy-FileIfExists (Join-Path $SourceProject "mac-wallpaper.jpg") (Join-Path $AssetsRoot "wallpapers\mac-wallpaper.jpg")
  Copy-FileIfExists (Join-Path $SourceProject "mac-wallpaper.png") (Join-Path $AssetsRoot "wallpapers\mac-wallpaper.png")
  Copy-TreeFiltered (Join-Path $SourceProject "cursors") (Join-Path $AssetsRoot "cursors") -ExcludeExtensions @(".zip")
}

Export-RegKeyIfExists "HKCU\Control Panel\Cursors" (Join-Path $RegistryRoot "hkcu-control-panel-cursors.reg")
Export-RegKeyIfExists "HKCU\Control Panel\Desktop" (Join-Path $RegistryRoot "hkcu-control-panel-desktop.reg")
Export-RegKeyIfExists "HKCU\Software\Microsoft\Windows\DWM" (Join-Path $RegistryRoot "hkcu-dwm.reg")
Export-RegKeyIfExists "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" (Join-Path $RegistryRoot "hkcu-explorer-accent.reg")

$manifest = [ordered]@{
  generatedAt = (Get-Date).ToString("o")
  seelenRoot = "%APPDATA%\com.seelen.seelen-ui"
  powerToysRoot = "%LOCALAPPDATA%\Microsoft\PowerToys"
  commandPaletteRoot = "%LOCALAPPDATA%\Packages\Microsoft.CommandPalette_*\LocalState"
  hotCornersConfig = "config\hot-corners.json"
  spotlightShortcuts = "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Mac Makeover"
  appleMenuProtocol = "macmakeover-apple-menu:"
  appleMenuScript = "scripts\Show-MacAppleMenu.ps1"
  appleMenuHandlerInstaller = "scripts\Install-AppleMenuHandler.ps1"
  appleMenuLaunchMethod = "conhost.exe --headless (registered by Install-AppleMenuHandler.ps1; wscript/VBS is blocked on this machine and intentionally not packaged)"
  sourceProject = "local mac-makeover workspace, optional after backup"
  excluded = @(
    "RustDesk credentials/config",
    "Tailscale account/device keys",
    "Seelen logs",
    "Seelen .bak files",
    "Windows Security settings",
    "Browser/app sessions and tokens"
  )
}

Write-Utf8NoBom -Path (Join-Path $PackageRoot "manifest.json") -Value ($manifest | ConvertTo-Json -Depth 5)

Write-Host "Backed up portable mac-makeover package to: $PackageRoot"
