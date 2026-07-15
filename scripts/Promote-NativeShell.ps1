[CmdletBinding()]
param(
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run Promote-NativeShell.ps1 from a normal PowerShell session, not an administrator window.'
}

& (Join-Path $PSScriptRoot 'Prepare-NativeShellUserProfile.ps1') -SkipBuild:$SkipBuild
& (Join-Path $PSScriptRoot 'Test-NativeShellPreflight.ps1')
& (Join-Path $PSScriptRoot 'Request-NativeShellPromotion.ps1')
& (Join-Path $PSScriptRoot 'Complete-NativeShellPromotion.ps1')
