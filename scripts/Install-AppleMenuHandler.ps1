# Registers the `macmakeover-apple-menu:` protocol so the top-left Apple logo opens the
# custom Apple menu. Launches via conhost --headless (NO wscript, NO terminal flash).
#
# Why conhost: this PC's security policy blocks wscript.exe from spawning PowerShell
# ("Windows Script Host failed - not enough memory resources"), which silently broke the
# old VBS launcher. conhost --headless runs PowerShell windowless and is not blocked.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$menuScript = Join-Path $repoRoot 'scripts\Show-MacAppleMenu.ps1'
if (-not (Test-Path $menuScript)) { throw "Menu script not found: $menuScript" }

$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$command = '"{0}" --headless "{1}" -NoProfile -ExecutionPolicy Bypass -STA -File "{2}" "%1"' -f $conhost, $powershell, $menuScript

$base = 'HKCU:\Software\Classes\macmakeover-apple-menu'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Mac Makeover Apple Menu'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Output "Registered macmakeover-apple-menu ->"
Write-Output "  $command"
