# Registers the `macmakeover-notification-center:` protocol. The toolbar bell and
# date items open this URI, which sends Win+N without using Seelen's Flyouts widget.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$invoke = Join-Path $repoRoot 'scripts\Invoke-MacAction.ps1'
if (-not (Test-Path $invoke)) {
  throw "Missing action script: $invoke"
}

$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$command = '"{0}" --headless "{1}" -NoProfile -ExecutionPolicy Bypass -File "{2}" -Action NotificationCenter' -f $conhost, $powershell, $invoke

$base = 'HKCU:\Software\Classes\macmakeover-notification-center'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Mac Makeover Notification Center'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Output "Registered macmakeover-notification-center ->"
Write-Output "  $command"
