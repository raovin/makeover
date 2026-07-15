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
$promotion = Join-Path $PSScriptRoot 'Invoke-NativeShellPromotion.ps1'
$process = Start-Process -FilePath $pwsh -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy', 'Bypass',
  '-File', ('"{0}"' -f $promotion)
)
if ($process.ExitCode -ne 0) {
  throw "Privileged promotion failed with exit code $($process.ExitCode)."
}
