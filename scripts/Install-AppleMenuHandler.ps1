# Registers the `macmakeover-apple-menu:` protocol so the top-left Apple logo opens the
# custom Apple menu. This uses the same fast resident MenuHost pipe path as Control
# Center; the old PowerShell/WPF cold path was laggy and made click routing brittle.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$menuHostExe = Join-Path $repoRoot 'tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe'
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
