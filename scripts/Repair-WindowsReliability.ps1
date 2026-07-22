[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Repair-WindowsReliability.ps1 must be run from an elevated PowerShell process.'
}

$logRoot = Join-Path $env:ProgramData 'MacMakeover\logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $logRoot "system-reliability-repair-$stamp.log"

Start-Transcript -Path $logPath -Force | Out-Null
try {
    Write-Host 'Repairing the Windows component store...'
    & dism.exe /Online /Cleanup-Image /RestoreHealth
    if ($LASTEXITCODE -ne 0) {
        throw "DISM failed with exit code $LASTEXITCODE."
    }

    Write-Host 'Verifying and repairing protected system files...'
    & sfc.exe /scannow
    if ($LASTEXITCODE -ne 0) {
        throw "SFC failed with exit code $LASTEXITCODE."
    }

    Write-Host 'Rebuilding Windows performance counter registrations...'
    & lodctr.exe /R
    if ($LASTEXITCODE -ne 0) {
        throw "lodctr failed with exit code $LASTEXITCODE."
    }

    Write-Host 'Resynchronizing WMI performance providers...'
    & winmgmt.exe /resyncperf
    if ($LASTEXITCODE -ne 0) {
        throw "winmgmt failed with exit code $LASTEXITCODE."
    }

    Write-Host "Reliability repair completed successfully. Log: $logPath"
}
finally {
    Stop-Transcript | Out-Null
}
