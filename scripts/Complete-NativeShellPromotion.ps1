[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NativeShellTasks.ps1')

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run native-shell completion from a normal, non-administrator PowerShell session.'
}

$deploymentRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin'
$stateRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration'
$preparedPath = Join-Path $stateRoot 'user-profile-prepared.json'
$systemPath = Join-Path $stateRoot 'system-profile-enabled.json'
$resultPath = Join-Path $stateRoot 'promotion-result.txt'
if (-not (Test-Path -LiteralPath $preparedPath)) { throw 'The unelevated user-profile preparation is missing.' }
if (-not (Test-Path -LiteralPath $systemPath)) { throw 'The privileged native-shell phase did not complete.' }
if (-not (Test-Path -LiteralPath $resultPath)) {
  throw 'The privileged native-shell phase did not report a result for this promotion attempt.'
}
$prepared = Get-Content -LiteralPath $preparedPath -Raw | ConvertFrom-Json
$preparedRunIdProperty = $prepared.PSObject.Properties['promotionRunId']
$promotionRunId = if ($preparedRunIdProperty) { [string]$preparedRunIdProperty.Value } else { '' }
if ([string]::IsNullOrWhiteSpace($promotionRunId)) {
  throw 'The prepared profile has no promotion run ID; stale promotion state is not accepted.'
}
$result = Get-Content -LiteralPath $resultPath -Raw
$runPattern = '(?m)^RUN_ID=' + [regex]::Escape($promotionRunId) + '\s*$'
if ($result -notmatch $runPattern -or
    $result -notmatch '(?m)^STATE=SUCCEEDED\s*$' -or
    $result -notmatch '(?m)^EXIT=0\s*$') {
  throw 'The privileged native-shell phase did not report success for the current promotion run.'
}
$systemState = Get-Content -LiteralPath $systemPath -Raw | ConvertFrom-Json
$systemRunIdProperty = $systemState.PSObject.Properties['promotionRunId']
if (-not $systemRunIdProperty -or [string]$systemRunIdProperty.Value -ne $promotionRunId) {
  throw 'The privileged native-shell state belongs to a different promotion run.'
}

$dock = Join-Path $deploymentRoot 'MacMakeover.Dock.exe'
Stop-NativeShellTasks -DeploymentRoot $deploymentRoot
if (Test-Path -LiteralPath $dock) {
  $shutdown = Start-Process -FilePath $dock -ArgumentList '--shutdown' -Wait -PassThru -WindowStyle Hidden
  if ($shutdown.ExitCode -ne 0) {
    throw "Dock shutdown command failed with exit code $($shutdown.ExitCode)."
  }
  Start-Sleep -Milliseconds 500
}
Get-NativeShellCurrentSessionProcess -ProcessName @('MacMakeover.MenuBar', 'MacMakeover.MenuHost', 'MacMakeover.Dock', 'MacMakeover.Supervisor', 'AwakeAndAvailable', 'seelen-ui', 'slu-service', 'yasb') |
  Stop-Process -Force -ErrorAction SilentlyContinue
Get-NativeShellCurrentSessionProcess -ProcessName 'explorer' | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (-not (Get-NativeShellCurrentSessionProcess -ProcessName 'explorer')) { Start-Process explorer.exe }
Start-Sleep -Seconds 4

Start-NativeShellTasks -DeploymentRoot $deploymentRoot
Start-Sleep -Seconds 6

$profileScript = Join-Path $PSScriptRoot 'Test-NativeShellProfile.ps1'
$profilePassed = $false
$profileOutput = @()
foreach ($attempt in 1..4) {
  $profileOutput = @(& $profileScript 2>&1)
  if ($LASTEXITCODE -eq 0) {
    $profilePassed = $true
    break
  }
  if ($attempt -lt 4) { Start-Sleep -Seconds 3 }
}
$profileOutput | ForEach-Object { Write-Host ([string]$_) }
if (-not $profilePassed) {
  throw 'Native-shell profile verification failed after promotion.'
}

Write-Host 'Native replacement promoted and accepted.'
