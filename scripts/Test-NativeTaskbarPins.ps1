[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'config\native-taskbar-pins.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$taskband = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
$taskbandText = [Text.Encoding]::Unicode.GetString(@($taskband.Favorites) + @($taskband.FavoritesResolve))
$shortcutRoot = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$results = foreach ($pin in $manifest.pins) {
  $foundInTaskband = @($pin.taskbandPatterns | Where-Object {
      $taskbandText.IndexOf([string]$_, [StringComparison]::OrdinalIgnoreCase) -ge 0
    }).Count -gt 0
  $foundShortcut = Test-Path -LiteralPath (Join-Path $shortcutRoot "$($pin.name).lnk")
  [pscustomobject]@{
    Name = [string]$pin.name
    Pinned = $foundInTaskband -or $foundShortcut
    Evidence = if ($foundInTaskband) { 'Taskband' } elseif ($foundShortcut) { 'Pinned shortcut' } else { 'Missing' }
  }
}

$results | Format-Table -AutoSize
$missing = @($results | Where-Object { -not $_.Pinned })
if ($missing.Count) {
  Write-Error ('Missing native taskbar pins: ' + (($missing.Name) -join ', '))
  exit 1
}
Write-Host "PASS: all $($results.Count) archived Seelen pins are present in the native taskbar."
