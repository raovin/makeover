[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run native-shell completion from a normal, non-administrator PowerShell session.'
}

$deploymentRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\bin'
$stateRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\migration'
$systemPath = Join-Path $stateRoot 'system-profile-enabled.json'
$resultPath = Join-Path $stateRoot 'promotion-result.txt'
if (-not (Test-Path -LiteralPath $systemPath)) { throw 'The privileged native-shell phase did not complete.' }
if (-not (Test-Path -LiteralPath $resultPath) -or (Get-Content -LiteralPath $resultPath -Raw) -notmatch 'EXIT=0') {
  throw 'The privileged native-shell phase did not report success.'
}

$dock = Join-Path $deploymentRoot 'MacMakeover.Dock.exe'
if (Test-Path -LiteralPath $dock) {
  Start-Process -FilePath $dock -ArgumentList '--shutdown' -Wait -WindowStyle Hidden
  Start-Sleep -Milliseconds 500
}
Get-Process MacMakeover.MenuBar, MacMakeover.MenuHost, MacMakeover.Dock, seelen-ui, slu-service, yasb -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
Start-Sleep -Seconds 4

$menuHost = Join-Path $deploymentRoot 'MacMakeover.MenuHost.exe'
$menuBar = Join-Path $deploymentRoot 'MacMakeover.MenuBar.exe'
Start-Process -FilePath $menuHost -WindowStyle Hidden
Start-Sleep -Milliseconds 500
Start-Process -FilePath $menuBar -WindowStyle Hidden
Start-Sleep -Milliseconds 500
Start-Process -FilePath $dock -WindowStyle Hidden
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
