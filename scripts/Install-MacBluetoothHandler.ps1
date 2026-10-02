# Registers the `macmakeover-bluetooth:` protocol. The toolbar Bluetooth item's
# onClick opens this URI and routes "bluetooth" through the MenuHost in this session.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$menuHostExe = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin\MacMakeover.MenuHost.exe'
if (-not (Test-Path -LiteralPath $menuHostExe)) {
  $menuHostExe = Join-Path $repoRoot 'tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe'
}
if (-not (Test-Path $menuHostExe)) {
  Write-Warning "MenuHost is not built yet ($menuHostExe). Run: dotnet build tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj -c Release"
}

$command = '"{0}" --show bluetooth' -f $menuHostExe

$base = 'HKCU:\Software\Classes\macmakeover-bluetooth'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Mac Makeover Bluetooth'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Output "Registered macmakeover-bluetooth ->"
Write-Output "  $command"
