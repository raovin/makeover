# Registers the `macmakeover-control-center:` protocol. The toolbar sliders item's
# onClick opens this URI, which makes the trigger position-independent (pixel click
# zones kept breaking whenever bar item widths drifted).
#
# Launching MenuHost with --show routes to the resident host in this Windows
# session, or starts it here if needed. The menu command stays the same.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$menuHostExe = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin\MacMakeover.MenuHost.exe'
if (-not (Test-Path -LiteralPath $menuHostExe)) {
  $menuHostExe = Join-Path $repoRoot 'tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe'
}
if (-not (Test-Path $menuHostExe)) {
  Write-Warning "MenuHost is not built yet ($menuHostExe). Run: dotnet build tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj -c Release"
}

$command = '"{0}" --show control' -f $menuHostExe

$base = 'HKCU:\Software\Classes\macmakeover-control-center'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Mac Makeover Control Center'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Output "Registered macmakeover-control-center ->"
Write-Output "  $command"
