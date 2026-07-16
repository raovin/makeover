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
$configPath = Join-Path $repoRoot 'config\windhawk\native-dock.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable

foreach ($required in @(
    (Join-Path $DeploymentRoot 'MacMakeover.MenuBar.exe'),
    (Join-Path $DeploymentRoot 'MacMakeover.MenuHost.exe'),
    (Join-Path $DeploymentRoot 'Assets\apple-mark.png'),
    (Join-Path $DeploymentRoot 'Assets\Fonts\Manrope-Regular.ttf'),
    (Join-Path $DeploymentRoot 'Assets\Fonts\Manrope-SemiBold.ttf'),
    (Join-Path $DeploymentRoot 'Assets\Fonts\JetBrainsMono-Medium.ttf'),
    (Join-Path $DeploymentRoot 'Assets\Fonts\OFL-Manrope.txt'),
    (Join-Path $DeploymentRoot 'Assets\Fonts\OFL-JetBrainsMono.txt'),
    (Join-Path $repoRoot 'assets\wallpapers\mac-wallpaper.jpg'),
    (Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe')
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
$nativeSource = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\MacMakeover.MenuBar\NativeMethods.cs') -Raw
if ($menuBarSource -match 'EnsureNativeDockZOrder|MonitorNativeDockAsync' -or
    $nativeSource -match 'IsBorderlessFullscreen|FindTaskbarFor') {
  $failures.Add('A taskbar z-order monitor is present; Explorer must own dock z-order.')
}

if ($config.settings['controlStyles[1].styles[0]'] -notmatch '#FF[0-9A-Fa-f]{6}') {
  $failures.Add('The dock background is not configured as fully opaque.')
}
if ($config.settings['controlStyles[2].styles[0]'] -ne 'Visibility=Collapsed') {
  $failures.Add('The duplicate native system tray is not hidden from the dock profile.')
}
if ($config.settings['controlStyles[6].styles[0]'] -ne 'Visibility=Collapsed') {
  $failures.Add('The duplicate Start button is not hidden from the dock profile.')
}
if ($config.settings['controlStyles[7].styles[0]'] -ne 'Visibility=Collapsed' -or
    $config.settings['controlStyles[8].styles[0]'] -ne 'Visibility=Collapsed') {
  $failures.Add('Windows Search or Widgets is still exposed inside the dock profile.')
}
if ($config.settings['controlStyles[1].styles[2]'] -ne 'CornerRadius=12' -or
    $config.settings['controlStyles[1].styles[5]'] -ne 'BackgroundSizing=InnerBorderEdge') {
  $failures.Add('The dock shell does not use the approved graphite squircle geometry.')
}
if ($config.settings['controlStyles[0].styles[3]'] -ne 'Margin=120,7,120,3' -or
    $config.settings['controlStyles[1].styles[3]'] -notmatch '#C05A6672') {
  $failures.Add('The dock shell does not preserve the approved top-edge clearance and contrast.')
}
if ($config.settings['controlStyles[13].target'] -ne 'Rectangle#BackgroundStroke' -or
    $config.settings['controlStyles[13].styles[0]'] -ne 'Visibility=Collapsed') {
  $failures.Add('The full-width native taskbar stroke is still visible behind the floating dock.')
}
if ($config.settings['controlStyles[9].target'] -notmatch 'RunningIndicator' -or
    $config.settings['controlStyles[9].styles[3]'] -ne 'Height=2') {
  $failures.Add('The dock running indicator is not using the compact optical-alignment profile.')
}
if ($config.settings['controlStyles[10].target'] -notmatch 'Image#Icon' -or
    $config.settings['controlStyles[10].styles[0]'] -notmatch 'Y=\"1\"') {
  $failures.Add('The dock icon artwork offset is missing.')
}

$windhawkProfile = Join-Path $env:ProgramData 'Windhawk\userprofile.json'
if (Test-Path -LiteralPath $windhawkProfile) {
  $profile = Get-Content -LiteralPath $windhawkProfile -Raw | ConvertFrom-Json -AsHashtable
  if (-not $profile.ContainsKey('app') -or -not $profile.app.ContainsKey('version')) {
    $warnings.Add('Windhawk is installed, but its version metadata was not found.')
  }
} else {
  $failures.Add('Windhawk user profile was not found.')
}

if (-not $SkipDownloadCheck) {
  $tempRoot = Join-Path $env:TEMP 'MacMakeover\preflight'
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
  $tempDll = Join-Path $tempRoot 'taskbar-styler.dll'
  Invoke-WebRequest -Uri $config.binaryUrl -OutFile $tempDll -UseBasicParsing -TimeoutSec 60
  $actualHash = (Get-FileHash -LiteralPath $tempDll -Algorithm SHA256).Hash
  if ($actualHash -ne $config.binarySha256) {
    $failures.Add("Pinned Windhawk binary hash mismatch: $actualHash")
  }
}

$hostPath = Join-Path $DeploymentRoot 'MacMakeover.MenuHost.exe'
if (Test-Path -LiteralPath $hostPath) {
  $hostSelfTest = Start-Process -FilePath $hostPath -ArgumentList '--self-test' `
    -Wait -PassThru -WindowStyle Hidden
  if ($hostSelfTest.ExitCode -ne 0) {
    $failures.Add("MenuHost Core Audio self-test failed with exit code $($hostSelfTest.ExitCode).")
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
