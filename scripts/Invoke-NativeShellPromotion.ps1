#Requires -RunAsAdministrator
[CmdletBinding()]
param()

if ($PSVersionTable.PSVersion.Major -lt 7) {
  $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
  if (-not (Test-Path -LiteralPath $pwsh)) {
    throw 'PowerShell 7 is required for the native-shell promotion.'
  }
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
  exit $LASTEXITCODE
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration'
$logPath = Join-Path $logRoot 'promotion-transcript.log'
$resultPath = Join-Path $logRoot 'promotion-result.txt'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue

Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
  & (Join-Path $PSScriptRoot 'Switch-To-NativeShell.ps1')
  Set-Content -LiteralPath $resultPath -Value 'EXIT=0'
}
catch {
  Write-Error $_ -ErrorAction Continue
  Set-Content -LiteralPath $resultPath -Value ("EXIT=1`nERROR=" + $_.Exception.Message)
  exit 1
}
finally {
  Stop-Transcript | Out-Null
}
