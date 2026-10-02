# Registers the `macmakeover-network:` protocol. The toolbar Wi-Fi item's onClick
# opens this URI and routes "network" through the MenuHost in this Windows session.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$menuHostExe = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin\MacMakeover.MenuHost.exe'
if (-not (Test-Path -LiteralPath $menuHostExe)) {
  $menuHostExe = Join-Path $repoRoot 'tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe'
}
if (-not (Test-Path $menuHostExe)) {
  Write-Warning "MenuHost is not built yet ($menuHostExe). Run: dotnet build tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj -c Release"
}

$command = '"{0}" --show network' -f $menuHostExe

$base = 'HKCU:\Software\Classes\macmakeover-network'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Mac Makeover Network'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Output "Registered macmakeover-network ->"
Write-Output "  $command"
