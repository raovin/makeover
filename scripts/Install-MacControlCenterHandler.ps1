# Registers the `macmakeover-control-center:` protocol. The toolbar sliders item's
# onClick opens this URI, which makes the trigger position-independent (pixel click
# zones kept breaking whenever bar item widths drifted).
#
# Fast path: cmd (via conhost --headless, no window flash) echoes "control" straight
# into the resident MacMakeover.MenuHost named pipe (~50ms). If the pipe is missing
# (host died), the || fallback starts the host with --show control, which both heals
# the host and opens the panel. No PowerShell in the hot path.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$menuHostExe = Join-Path $repoRoot 'tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe'
if (-not (Test-Path $menuHostExe)) {
  Write-Warning "MenuHost is not built yet ($menuHostExe). Run: dotnet build tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj -c Release"
}

$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
$command = '"{0}" --headless "{1}" /c echo control> \\.\pipe\MacMakeover.MenuHost || start "" "{2}" --show control' -f $conhost, $cmd, $menuHostExe

$base = 'HKCU:\Software\Classes\macmakeover-control-center'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Mac Makeover Control Center'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Output "Registered macmakeover-control-center ->"
Write-Output "  $command"
