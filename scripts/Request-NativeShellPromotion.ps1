[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Launch the promotion request from the normal user session.'
}

$pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
if (-not (Test-Path -LiteralPath $pwsh)) { throw 'PowerShell 7 is required.' }
$stateRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration'
$preparedPath = Join-Path $stateRoot 'user-profile-prepared.json'
$resultPath = Join-Path $stateRoot 'promotion-result.txt'
if (-not (Test-Path -LiteralPath $preparedPath)) {
  throw 'The unelevated user-profile preparation has not completed.'
}
$prepared = Get-Content -LiteralPath $preparedPath -Raw | ConvertFrom-Json
$promotionRunIdProperty = $prepared.PSObject.Properties['promotionRunId']
$promotionRunId = if ($promotionRunIdProperty) { [string]$promotionRunIdProperty.Value } else { '' }
if ([string]::IsNullOrWhiteSpace($promotionRunId)) {
  throw 'The prepared native-shell profile has no promotion run ID; rerun preparation before requesting elevation.'
}
if (-not [regex]::IsMatch($promotionRunId, '^[0-9a-fA-F]{32}$')) {
  throw 'The prepared native-shell profile has an invalid promotion run ID.'
}
[System.IO.File]::WriteAllText(
  $resultPath,
  "RUN_ID=$promotionRunId`nSTATE=REQUESTED`nREQUESTED_AT=$((Get-Date).ToUniversalTime().ToString('o'))`n",
  [Text.UTF8Encoding]::new($false))
$promotion = Join-Path $PSScriptRoot 'Invoke-NativeShellPromotion.ps1'
$process = Start-Process -FilePath $pwsh -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy', 'Bypass',
  '-File', ('"{0}"' -f $promotion),
  '-PromotionRunId', $promotionRunId
) -ErrorAction Stop
if ($process.ExitCode -ne 0) {
  throw "Privileged promotion failed with exit code $($process.ExitCode)."
}
