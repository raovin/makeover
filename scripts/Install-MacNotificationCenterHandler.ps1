# Registers the `macmakeover-notification-center:` protocol. The toolbar bell and
# date items open this URI, which invokes Windows' native Notification Center
# without using Seelen's Flyouts widget.
$ErrorActionPreference = 'Stop'

$explorer = Join-Path $env:SystemRoot 'explorer.exe'
$command = '"{0}" "ms-actioncenter:"' -f $explorer

$base = 'HKCU:\Software\Classes\macmakeover-notification-center'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Mac Makeover Notification Center'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Output "Registered macmakeover-notification-center ->"
Write-Output "  $command"
