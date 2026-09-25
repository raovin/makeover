#Requires -RunAsAdministrator
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^[0-9a-fA-F]{32}$')]
  [string]$PromotionRunId
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
  $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
  if (-not (Test-Path -LiteralPath $pwsh)) {
    throw 'PowerShell 7 is required for the native-shell promotion.'
  }
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -PromotionRunId $PromotionRunId
  exit $LASTEXITCODE
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration'
$logPath = Join-Path $logRoot 'promotion-transcript.log'
$resultPath = Join-Path $logRoot 'promotion-result.txt'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
[System.IO.File]::WriteAllText(
  $resultPath,
  "RUN_ID=$PromotionRunId`nSTATE=RUNNING`nSTARTED_AT=$((Get-Date).ToUniversalTime().ToString('o'))`n",
  [Text.UTF8Encoding]::new($false))

Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
  & (Join-Path $PSScriptRoot 'Switch-To-NativeShell.ps1') -PromotionRunId $PromotionRunId
  [System.IO.File]::WriteAllText(
    $resultPath,
    "RUN_ID=$PromotionRunId`nSTATE=SUCCEEDED`nEXIT=0`nCOMPLETED_AT=$((Get-Date).ToUniversalTime().ToString('o'))`n",
    [Text.UTF8Encoding]::new($false))
}
catch {
  Write-Error $_ -ErrorAction Continue
  [System.IO.File]::WriteAllText(
    $resultPath,
    "RUN_ID=$PromotionRunId`nSTATE=FAILED`nEXIT=1`nERROR=$($_.Exception.Message)",
    [Text.UTF8Encoding]::new($false))
  exit 1
}
finally {
  Stop-Transcript | Out-Null
}
