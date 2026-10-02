# Registers the `macmakeover-apple-menu:` protocol. Launching MenuHost with --show
# routes to the resident host in this Windows session, or starts it here if needed.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$menuHostExe = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin\MacMakeover.MenuHost.exe'
if (-not (Test-Path -LiteralPath $menuHostExe)) {
  $menuHostExe = Join-Path $repoRoot 'tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe'
}
if (-not (Test-Path $menuHostExe)) {
  Write-Warning "MenuHost is not built yet ($menuHostExe). Run: dotnet build tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj -c Release"
}

$command = '"{0}" --show apple' -f $menuHostExe

$base = 'HKCU:\Software\Classes\macmakeover-apple-menu'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Mac Makeover Apple Menu'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Output "Registered macmakeover-apple-menu ->"
Write-Output "  $command"
