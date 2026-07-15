[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packages = @(
  @{ Id = 'AmN.yasb'; Name = 'YASB' },
  @{ Id = 'RamenSoftware.Windhawk'; Name = 'Windhawk' }
)

foreach ($package in $packages) {
  $installed = winget list --id $package.Id --exact --accept-source-agreements 2>$null
  if ($LASTEXITCODE -eq 0 -and $installed -match [regex]::Escape($package.Id)) {
    Write-Host "$($package.Name) is already installed."
    continue
  }

  Write-Host "Installing $($package.Name)..."
  & winget install --id $package.Id --exact --silent --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    throw "$($package.Name) installation failed."
  }
}

& (Join-Path $PSScriptRoot 'Switch-To-NativeShell.ps1')

Write-Host ''
Write-Host 'Core native-shell profile installed.'
Write-Host 'Optional dock skin: install Windows 11 Taskbar Styler in Windhawk, then choose DockLike.'
