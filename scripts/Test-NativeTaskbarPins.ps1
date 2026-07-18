[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'config\native-taskbar-pins.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$taskband = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
$taskbandText = [Text.Encoding]::Unicode.GetString(@($taskband.Favorites) + @($taskband.FavoritesResolve))
$shell = New-Object -ComObject Shell.Application
$appsFolder = $shell.Namespace('shell:AppsFolder')
$shortcutRoot = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$shortcutFolder = $shell.Namespace($shortcutRoot)
$results = foreach ($pin in $manifest.pins) {
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
  [pscustomobject]@{
    Name = [string]$pin.name
    Pinned = ($verbs -contains 'Unpin from taskbar') -or $foundInTaskband
    Evidence = if ($verbs -contains 'Unpin from taskbar') { 'Shell verb' } elseif ($foundInTaskband) { 'Taskband' } else { 'Missing' }
  }
}

$results | Format-Table -AutoSize
$missing = @($results | Where-Object { -not $_.Pinned })
if ($missing.Count) {
  Write-Error ('Missing native taskbar pins: ' + (($missing.Name) -join ', '))
  exit 1
}
Write-Host "PASS: all $($results.Count) archived Seelen pins are present in the native taskbar."
