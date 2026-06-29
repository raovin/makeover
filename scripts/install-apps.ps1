[CmdletBinding()]
param(
  [switch]$IncludeRemoteTools
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Install-WingetPackage {
  param(
    [string]$Id,
    [string]$Name
  )

  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget was not found. Install App Installer from Microsoft Store first."
  }

  Write-Host "Installing/checking $Name ($Id)..."
  winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
}

Install-WingetPackage -Id "Microsoft.PowerToys" -Name "Microsoft PowerToys"
Install-WingetPackage -Id "Seelen.SeelenUI" -Name "Seelen UI"

if ($IncludeRemoteTools) {
  Install-WingetPackage -Id "Tailscale.Tailscale" -Name "Tailscale"
  Install-WingetPackage -Id "RustDesk.RustDesk" -Name "RustDesk"
}

Write-Host "Install step complete. Sign into Tailscale/RustDesk manually if installed."
