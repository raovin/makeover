[CmdletBinding()]
param(
  [switch]$SkipBuild,
  [switch]$InstallLegacyIntegrations
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($InstallLegacyIntegrations) {
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

    Write-Warning "Installing explicitly requested legacy integration: $($package.Name)."
    & winget install --id $package.Id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
      throw "$($package.Name) installation failed."
    }
  }
} else {
  Write-Host 'Native-only installation selected; retired YASB/Windhawk integrations were not installed.'
}

& (Join-Path $PSScriptRoot 'Promote-NativeShell.ps1') -SkipBuild:$SkipBuild

Write-Host ''
Write-Host 'Core native-shell profile installed.'
