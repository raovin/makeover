[CmdletBinding()]
param(
    [datetime]$Since = (Get-Date).AddMinutes(-30),
    [ValidateRange(1, 120)]
    [int]$ProbeCount = 20,
    [switch]$SkipShellTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Invoke-PingSample {
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        [Parameter(Mandatory)]
        [int]$Count
    )

    $passed = 0
    foreach ($probe in 1..$Count) {
        if (Test-Connection -TargetName $Target -Count 1 -Quiet -TimeoutSeconds 2) {
            $passed++
        }
    }
    return $passed
}

$adapter = Get-NetAdapter -Name 'WiFi' -ErrorAction SilentlyContinue
if (-not $adapter -or $adapter.Status -ne 'Up') {
    $failures.Add('The WiFi adapter is not up.')
} else {
    $driver = Get-CimInstance Win32_PnPSignedDriver |
        Where-Object { $_.DeviceName -eq $adapter.InterfaceDescription } |
        Select-Object -First 1
    if (-not $driver) {
        $failures.Add('The active WiFi driver could not be identified.')
    } elseif ([version]$driver.DriverVersion -lt [version]'24.50.0.4') {
        $failures.Add("The Intel AX211 driver is older than the accepted 24.50.0.4 build: $($driver.DriverVersion)")
    } else {
        Write-Host "PASS: Intel AX211 driver $($driver.DriverVersion) ($($driver.InfName))."
    }

    $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
    $gateway = $ipConfig.IPv4DefaultGateway.NextHop
    if ([string]::IsNullOrWhiteSpace($gateway)) {
        $failures.Add('WiFi has no IPv4 default gateway.')
    } else {
        $gatewayPassed = Invoke-PingSample -Target $gateway -Count $ProbeCount
        if ($gatewayPassed -ne $ProbeCount) {
            $failures.Add("Gateway probes passed $gatewayPassed/$ProbeCount against $gateway.")
        } else {
            Write-Host "PASS: gateway probes $gatewayPassed/$ProbeCount against $gateway."
        }
    }

    $publicPassed = Invoke-PingSample -Target '1.1.1.1' -Count $ProbeCount
    if ($publicPassed -lt [math]::Ceiling($ProbeCount * 0.95)) {
        $failures.Add("Public probes passed $publicPassed/$ProbeCount against 1.1.1.1.")
    } elseif ($publicPassed -ne $ProbeCount) {
        $warnings.Add("Public probes passed $publicPassed/$ProbeCount against 1.1.1.1; ICMP can be deprioritized upstream.")
    } else {
        Write-Host "PASS: public probes $publicPassed/$ProbeCount against 1.1.1.1."
    }

    $dnsPassed = 0
    foreach ($probe in 1..5) {
        if (Resolve-DnsName 'www.microsoft.com' -DnsOnly -ErrorAction SilentlyContinue) {
            $dnsPassed++
        }
    }
    if ($dnsPassed -ne 5) {
        $failures.Add("DNS lookups passed $dnsPassed/5.")
    } else {
        Write-Host 'PASS: DNS lookups 5/5.'
    }
}

$driverEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $Since } -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -like 'Netwtw*' -and $_.Id -in @(5010, 6062) })
if ($driverEvents.Count) {
    $failures.Add("Found $($driverEvents.Count) Intel WiFi reset/invalid-value event(s) since $($Since.ToString('s')).")
} else {
    Write-Host "PASS: no Intel WiFi reset/invalid-value events since $($Since.ToString('s'))."
}

$operatingSystem = Get-CimInstance Win32_OperatingSystem
$totalGb = [math]::Round($operatingSystem.TotalVisibleMemorySize / 1MB, 2)
$usedGb = [math]::Round(($operatingSystem.TotalVisibleMemorySize - $operatingSystem.FreePhysicalMemory) / 1MB, 2)
$freeGb = [math]::Round($operatingSystem.FreePhysicalMemory / 1MB, 2)
Write-Host "INFO: physical memory $usedGb/$totalGb GB used; $freeGb GB available."
if ($freeGb -lt 1.5) {
    $warnings.Add("Only $freeGb GB physical memory is available; inspect active application families before a meeting.")
}

$bios = Get-CimInstance Win32_BIOS
$biosVersionMatch = [regex]::Match([string]$bios.SMBIOSBIOSVersion, '(?<version>\d+\.\d+\.\d+)$')
if (-not $biosVersionMatch.Success) {
    $warnings.Add("Could not parse the HP BIOS version: $($bios.SMBIOSBIOSVersion)")
} elseif ([version]$biosVersionMatch.Groups['version'].Value -lt [version]'01.04.03') {
    $warnings.Add("HP X70 BIOS is $($bios.SMBIOSBIOSVersion); staged critical update 01.04.03 is still pending.")
} else {
    Write-Host "PASS: HP X70 BIOS $($bios.SMBIOSBIOSVersion)."
}

$teamViewer = Get-Service TeamViewer -ErrorAction SilentlyContinue
if ($teamViewer) {
    $warnings.Add("TeamViewer remains installed ($($teamViewer.Status), $($teamViewer.StartType)); RustDesk is the intended replacement.")
}
$rustDesk = Get-Service RustDesk -ErrorAction SilentlyContinue
if (-not $rustDesk -or $rustDesk.Status -ne 'Running') {
    $warnings.Add('RustDesk service is not running.')
} else {
    Write-Host 'PASS: RustDesk service is running.'
}

if (-not $SkipShellTests) {
    foreach ($testPath in @(
        'Test-NativeShellPreflight.ps1',
        'Test-NativeShellProfile.ps1',
        'Test-NativeTaskbarPins.ps1'
    )) {
        if ($testPath -eq 'Test-NativeShellPreflight.ps1') {
            & (Join-Path $PSScriptRoot $testPath) -SkipDownloadCheck
        } else {
            & (Join-Path $PSScriptRoot $testPath)
        }
        if ($LASTEXITCODE -ne 0) {
            $failures.Add("$testPath failed with exit code $LASTEXITCODE.")
        }
    }
}

foreach ($warning in $warnings) {
    Write-Warning $warning
}
if ($failures.Count) {
    foreach ($failure in $failures) {
        Write-Error $failure
    }
    exit 1
}

Write-Host "PASS: system reliability acceptance completed with $($warnings.Count) warning(s)."
