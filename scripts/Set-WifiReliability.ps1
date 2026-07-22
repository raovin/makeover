[CmdletBinding()]
param(
    [string]$AdapterName = 'WiFi'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Set-WifiReliability.ps1 must be run from an elevated PowerShell process.'
}

$adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
$preferredBand = Get-NetAdapterAdvancedProperty -Name $AdapterName `
    -RegistryKeyword 'RoamingPreferredBandType' -AllProperties -ErrorAction Stop

$backupRoot = Join-Path $env:LOCALAPPDATA 'MacMakeover\reliability'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$backupPath = Join-Path $backupRoot 'wifi-policy-before-hardening.json'

[pscustomobject]@{
    CapturedAt = (Get-Date).ToString('o')
    AdapterName = $adapter.Name
    InterfaceDescription = $adapter.InterfaceDescription
    PreferredBandDisplayValue = $preferredBand.DisplayValue
    PreferredBandRegistryValue = @($preferredBand.RegistryValue)
    ActivePowerScheme = (& powercfg.exe /GETACTIVESCHEME | Out-String).Trim()
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $backupPath -Encoding utf8

# Intel maps RegistryValue 2 to "Prefer 5 GHz" for this AX211 driver.
Set-NetAdapterAdvancedProperty -Name $AdapterName `
    -RegistryKeyword 'RoamingPreferredBandType' -RegistryValue 2 -NoRestart

$wirelessSubgroup = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
$powerSavingSetting = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
& powercfg.exe /SETACVALUEINDEX SCHEME_CURRENT $wirelessSubgroup $powerSavingSetting 0
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set AC Wi-Fi power policy. Exit code: $LASTEXITCODE"
}
& powercfg.exe /SETDCVALUEINDEX SCHEME_CURRENT $wirelessSubgroup $powerSavingSetting 0
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set battery Wi-Fi power policy. Exit code: $LASTEXITCODE"
}
& powercfg.exe /SETACTIVE SCHEME_CURRENT
if ($LASTEXITCODE -ne 0) {
    throw "Failed to reactivate the current power scheme. Exit code: $LASTEXITCODE"
}

$currentBand = Get-NetAdapterAdvancedProperty -Name $AdapterName `
    -RegistryKeyword 'RoamingPreferredBandType' -ErrorAction Stop

$resultPath = Join-Path $backupRoot 'wifi-policy-result.json'
[pscustomobject]@{
    AppliedAt = (Get-Date).ToString('o')
    AdapterName = $adapter.Name
    PreferredBandDisplayValue = $currentBand.DisplayValue
    PreferredBandRegistryValue = @($currentBand.RegistryValue)
    RestartRequired = $true
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding utf8

Write-Host "Wi-Fi reliability policy applied to $($adapter.InterfaceDescription)."
Write-Host "Preferred band: $($currentBand.DisplayValue)"
Write-Host 'The preferred-band change takes effect after the next adapter or system restart.'
Write-Host "Rollback metadata: $backupPath"
Write-Host "Result: $resultPath"
