[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
$yasb = Get-Process yasb -ErrorAction SilentlyContinue
$seelen = Get-Process seelen-ui, slu-service -ErrorAction SilentlyContinue
$menuHost = Get-Process MacMakeover.MenuHost -ErrorAction SilentlyContinue
$seelenTask = Get-ScheduledTask -TaskPath '\Seelen\' -TaskName 'Seelen UI Service' -ErrorAction SilentlyContinue
$seelenTaskTarget = if ($seelenTask) { $seelenTask.Actions.Execute | Select-Object -First 1 } else { $null }

if (-not $yasb) { $failures.Add('YASB is not running.') }
if ($seelen) { $failures.Add('Seelen is still running alongside YASB.') }
if ($seelenTask -and $seelenTask.State -ne 'Disabled' -and $seelenTaskTarget -and (Test-Path -LiteralPath $seelenTaskTarget)) {
  $failures.Add('Seelen is still enabled at logon.')
} elseif ($seelenTask -and $seelenTask.State -ne 'Disabled') {
  Write-Warning 'An inert Seelen scheduled-task entry remains, but its executable is no longer installed.'
}
if (-not $menuHost) { $failures.Add('MenuHost is not running.') }

$stuckRects = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3' -ErrorAction SilentlyContinue).Settings
if ($stuckRects -and $stuckRects.Length -gt 8 -and (($stuckRects[8] -band 1) -eq 1)) {
  $failures.Add('Windows taskbar auto-hide is enabled; maximized apps can appear behind the dock.')
}

$configRoot = Join-Path $env:USERPROFILE '.config\yasb'
foreach ($required in @('config.yaml', 'styles.css', '.env', 'assets\apple-mark.svg')) {
  if (-not (Test-Path -LiteralPath (Join-Path $configRoot $required))) {
    $failures.Add("Missing live YASB file: $required")
  }
}

$liveConfig = Get-Content -LiteralPath (Join-Path $configRoot 'config.yaml') -Raw -ErrorAction SilentlyContinue
if ($liveConfig -notmatch '(?m)^watch_config:\s*false\s*$' -or
    $liveConfig -notmatch '(?m)^watch_stylesheet:\s*false\s*$') {
  $failures.Add('YASB production hot reload is enabled.')
}

$protocols = @(
  'macmakeover-apple-menu',
  'macmakeover-control-center',
  'macmakeover-network',
  'macmakeover-bluetooth'
)
foreach ($protocol in $protocols) {
  $command = (Get-ItemProperty -LiteralPath "Registry::HKEY_CURRENT_USER\Software\Classes\$protocol\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
  if ([string]::IsNullOrWhiteSpace($command)) {
    $failures.Add("Protocol is not registered: $protocol")
  } elseif ($command -match 'wscript|powershell') {
    $failures.Add("Protocol uses a visible/slow launcher: $protocol")
  }
}

$taskbar = Get-Process explorer -ErrorAction SilentlyContinue
if (-not $taskbar) { $failures.Add('Windows Explorer shell is not running.') }

if ($failures.Count) {
  $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
  exit 1
}

$yasbMb = [math]::Round((($yasb | Measure-Object WorkingSet64 -Sum).Sum / 1MB), 1)
$menuHostMb = [math]::Round((($menuHost | Measure-Object WorkingSet64 -Sum).Sum / 1MB), 1)
Write-Host "PASS: native-shell profile is coherent. YASB ${yasbMb} MB; MenuHost ${menuHostMb} MB."
