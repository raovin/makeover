[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$settingsPath = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\settings.json'
if (-not (Test-Path -LiteralPath $settingsPath)) {
  Write-Host 'PowerToys settings not found; nothing to disable.'
  return
}

$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
if ($null -eq $settings.enabled -or $null -eq $settings.enabled.Awake) {
  Write-Host 'PowerToys Awake setting not found; nothing to disable.'
  return
}

$settings.enabled.Awake = $false
[IO.File]::WriteAllText(
  $settingsPath,
  ($settings | ConvertTo-Json -Depth 20 -Compress),
  [Text.UTF8Encoding]::new($false))

Get-Process PowerToys.Awake -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'Disabled PowerToys Awake; other PowerToys modules remain enabled.'
