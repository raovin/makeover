#Requires -RunAsAdministrator
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))

& (Join-Path $repoRoot 'scripts\Install-NativeDock.ps1') -Disable
$task = Get-ScheduledTask -TaskPath '\Seelen\' -TaskName 'Seelen UI Service' -ErrorAction SilentlyContinue
if ($task) {
  Enable-ScheduledTask -TaskPath '\Seelen\' -TaskName 'Seelen UI Service' -ErrorAction SilentlyContinue | Out-Null
  Start-ScheduledTask -TaskPath '\Seelen\' -TaskName 'Seelen UI Service' -ErrorAction SilentlyContinue
}
$hotCorners = Get-ScheduledTask -TaskName 'MacMakeover Hot Corners Keepalive' -ErrorAction SilentlyContinue
if ($hotCorners) { Enable-ScheduledTask -TaskName 'MacMakeover Hot Corners Keepalive' -ErrorAction SilentlyContinue | Out-Null }
Write-Host 'Privileged Seelen rollback completed.'
