# Registers the `macmakeover-control-center:` protocol so top-right toolbar controls open
# the custom mac-style control/power popover without showing Seelen's built-in flyout.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$controlScript = Join-Path $repoRoot 'scripts\Show-MacControlCenter.ps1'
if (-not (Test-Path $controlScript)) { throw "Control Center script not found: $controlScript" }

$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$command = '"{0}" --headless "{1}" -NoProfile -ExecutionPolicy Bypass -STA -File "{2}" "%1"' -f $conhost, $powershell, $controlScript

$base = 'HKCU:\Software\Classes\macmakeover-control-center'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Mac Makeover Control Center'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Output "Registered macmakeover-control-center ->"
Write-Output "  $command"
