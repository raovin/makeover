# Registers the `macmakeover-apple-menu:` protocol. Opens the resident MenuHost Apple
# panel via the named pipe (fast, no window); falls back to starting MenuHost with
# --show apple if the pipe is gone. The old conhost+PowerShell+WPF chain is retired -
# it was the measured source of Apple-menu lag.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$menuHostExe = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin\MacMakeover.MenuHost.exe'
if (-not (Test-Path -LiteralPath $menuHostExe)) {
  $menuHostExe = Join-Path $repoRoot 'tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe'
}
if (-not (Test-Path $menuHostExe)) {
  Write-Warning "MenuHost is not built yet ($menuHostExe). Run: dotnet build tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj -c Release"
}

$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
$command = '"{0}" --headless "{1}" /c echo apple> \\.\pipe\MacMakeover.MenuHost || start "" "{2}" --show apple' -f $conhost, $cmd, $menuHostExe

$base = 'HKCU:\Software\Classes\macmakeover-apple-menu'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Mac Makeover Apple Menu'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Output "Registered macmakeover-apple-menu ->"
Write-Output "  $command"
