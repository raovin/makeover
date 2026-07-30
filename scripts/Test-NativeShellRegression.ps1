[CmdletBinding()]
param(
  [switch]$SkipBuild,
  [switch]$IncludeInteractiveAltTab,
  [switch]$IncludeLiveRecovery,
  [switch]$SkipPerformanceSmoke,
  [string]$DeploymentRoot = (Join-Path $env:LOCALAPPDATA 'MacMakeover\bin'),
  [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $repoRoot 'qa\regression'
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$evidencePath = Join-Path $OutputDirectory "$stamp-native-shell-regression.json"
$results = [Collections.Generic.List[object]]::new()

function Add-Result {
  param([string]$Name, [bool]$Passed, [string]$Detail, [double]$DurationMs)
  $results.Add([pscustomobject]@{
    name = $Name
    passed = $Passed
    detail = $Detail
    durationMs = [Math]::Round($DurationMs, 1)
  })
  $color = if ($Passed) { 'Green' } else { 'Red' }
  Write-Host ("{0}: {1} ({2} ms)" -f $(if ($Passed) { 'PASS' } else { 'FAIL' }), $Name, [Math]::Round($DurationMs, 1)) -ForegroundColor $color
}

function Invoke-CheckedProcess {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$ArgumentList = @(),
    [int]$TimeoutSeconds = 30
  )

  if (-not (Test-Path -LiteralPath $FilePath)) {
    Add-Result $Name $false "Missing executable: $FilePath" 0
    return $false
  }
  $timer = [Diagnostics.Stopwatch]::StartNew()
  $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden
  if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    $process.Kill($true)
    $process.WaitForExit()
    $timer.Stop()
    Add-Result $Name $false "Timed out after $TimeoutSeconds seconds." $timer.Elapsed.TotalMilliseconds
    $process.Dispose()
    return $false
  }
  $exitCode = $process.ExitCode
  $process.Dispose()
  $timer.Stop()
  Add-Result $Name ($exitCode -eq 0) "Exit code $exitCode." $timer.Elapsed.TotalMilliseconds
  return $exitCode -eq 0
}

function Wait-ForReplacement {
  param(
    [Parameter(Mandatory)][string]$ProcessName,
    [Parameter(Mandatory)][int]$PreviousId,
    [Parameter(Mandatory)][int]$TimeoutSeconds
  )

  $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 250
    $previous = Get-Process -Id $PreviousId -ErrorAction SilentlyContinue
    $replacement = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
      Where-Object { $_.SessionId -eq $sessionId -and $_.Id -ne $PreviousId })
    if (-not $previous -and $replacement.Count -eq 1) { return $replacement[0] }
  } while ([DateTime]::UtcNow -lt $deadline)
  return $null
}

function Test-ForceStopAndRecover {
  param(
    [Parameter(Mandatory)][string]$ProcessName,
    [Parameter(Mandatory)][int]$SessionId,
    [Parameter(Mandatory)][int]$TimeoutSeconds,
    [Parameter(Mandatory)][string]$ResultName
  )

  $process = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
    Where-Object { $_.SessionId -eq $SessionId } | Select-Object -First 1)
  if ($process.Count -eq 0) {
    Add-Result $ResultName $false "$ProcessName was absent before the recovery test." 0
    return $false
  }

  $timer = [Diagnostics.Stopwatch]::StartNew()
  $oldId = $process.Id
  Stop-Process -Id $oldId -Force
  $replacement = Wait-ForReplacement -ProcessName $ProcessName -PreviousId $oldId -TimeoutSeconds $TimeoutSeconds
  $timer.Stop()
  $replacementId = if ($replacement) { $replacement.Id } else { 'none' }
  Add-Result $ResultName ($null -ne $replacement) "Automatic recovery only. Old PID $oldId; new PID $replacementId." $timer.Elapsed.TotalMilliseconds
  return ($null -ne $replacement)
}

function Restore-LiveRecoveryTargets {
  param([int]$SessionId)

  # Start missing components only. Never kill duplicates; report failure instead.
  $restored = $true
  foreach ($target in @(
      @{ ProcessName = 'MacMakeover.Supervisor'; TaskName = 'MacMakeover Shell - Supervisor'; Timeout = 90 },
      @{ ProcessName = 'MacMakeover.MenuHost'; TaskName = 'MacMakeover Shell - MenuHost'; Timeout = 15 },
      @{ ProcessName = 'MacMakeover.MenuBar'; TaskName = 'MacMakeover Shell - MenuBar'; Timeout = 15 },
      @{ ProcessName = 'MacMakeover.Dock'; TaskName = 'MacMakeover Shell - Dock'; Timeout = 15 }
    )) {
    $instances = @(Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue |
      Where-Object { $_.SessionId -eq $SessionId })
    if ($instances.Count -eq 0) {
      Start-ScheduledTask -TaskName $target.TaskName -ErrorAction SilentlyContinue
      $deadline = [DateTime]::UtcNow.AddSeconds($target.Timeout)
      do {
        Start-Sleep -Milliseconds 250
        $instances = @(Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue |
          Where-Object { $_.SessionId -eq $SessionId })
      } until ($instances.Count -gt 0 -or [DateTime]::UtcNow -ge $deadline)
    }
    if ($instances.Count -ne 1) { $restored = $false }
  }
  return $restored
}

if (-not $SkipBuild) {
  $buildTimer = [Diagnostics.Stopwatch]::StartNew()
  & (Join-Path $PSScriptRoot 'Build-NativeShell.ps1')
  $buildExit = $LASTEXITCODE
  $buildTimer.Stop()
  Add-Result 'Build native shell' ($buildExit -eq 0) "Exit code $buildExit." $buildTimer.Elapsed.TotalMilliseconds
}

$releaseRoot = Join-Path $repoRoot 'tools'
$checks = @(
  @{
    Name = 'Dock Open, Close, context menu, and dynamic application'
    Path = Join-Path $releaseRoot 'MacMakeover.Dock\bin\Release\net10.0-windows\MacMakeover.Dock.exe'
    Args = @('--regression-test')
    Timeout = 20
  },
  @{
    Name = 'Menu bar mixed-DPI telemetry layout'
    Path = Join-Path $releaseRoot 'MacMakeover.MenuBar\bin\Release\net10.0-windows\MacMakeover.MenuBar.exe'
    Args = @('--self-test')
    Timeout = 15
  },
  @{
    Name = 'MenuHost Alt+Tab dismissal decision matrix'
    Path = Join-Path $releaseRoot 'MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe'
    Args = @('--regression-test')
    Timeout = 15
  },
  @{
    Name = 'Supervisor component manifest and session probe'
    Path = Join-Path $releaseRoot 'MacMakeover.Supervisor\bin\Release\net10.0-windows\MacMakeover.Supervisor.exe'
    Args = @('--self-test')
    Timeout = 15
  }
)

foreach ($check in $checks) {
  Invoke-CheckedProcess -Name $check.Name -FilePath $check.Path -ArgumentList $check.Args -TimeoutSeconds $check.Timeout | Out-Null
}

if ($IncludeInteractiveAltTab) {
  Invoke-CheckedProcess `
    -Name 'Alt+Tab closes a visible Apple panel' `
    -FilePath (Join-Path $releaseRoot 'MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe') `
    -ArgumentList @('--alt-tab-regression-test') `
    -TimeoutSeconds 15 | Out-Null
}

if (-not $SkipPerformanceSmoke) {
  $performanceOutput = Join-Path $OutputDirectory "$stamp-performance"
  $performanceTimer = [Diagnostics.Stopwatch]::StartNew()
  try {
    $performanceJson = & (Join-Path $PSScriptRoot 'Measure-ShellPerformance.ps1') `
      -Profile 'regression-missing-process' `
      -CustomProcessNames @('MacMakeover.Supervisor', 'MacMakeover.IntentionalMissingProcess') `
      -DurationSeconds 15 `
      -OutputDirectory $performanceOutput
    $summaryPath = Get-ChildItem -LiteralPath $performanceOutput -Filter '*-summary.json' |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1 -ExpandProperty FullName
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    $passed = -not $summary.allExpectedProcessesPresent -and
      $summary.customProcessNames -contains 'MacMakeover.Supervisor' -and
      $summary.missingProcessNames -contains 'MacMakeover.IntentionalMissingProcess'
    $performanceTimer.Stop()
    Add-Result 'Performance sampler tolerates missing processes and includes Supervisor' $passed $summaryPath $performanceTimer.Elapsed.TotalMilliseconds
  } catch {
    $performanceTimer.Stop()
    Add-Result 'Performance sampler tolerates missing processes and includes Supervisor' $false $_.Exception.Message $performanceTimer.Elapsed.TotalMilliseconds
  }
}

if ($IncludeLiveRecovery) {
  $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
  $recoveryReady = $true
  $liveRecoveryComponents = @(
    @{ ProcessName = 'MacMakeover.MenuHost'; TaskName = 'MacMakeover Shell - MenuHost'; TimeoutSeconds = 12 },
    @{ ProcessName = 'MacMakeover.MenuBar'; TaskName = 'MacMakeover Shell - MenuBar'; TimeoutSeconds = 12 },
    @{ ProcessName = 'MacMakeover.Dock'; TaskName = 'MacMakeover Shell - Dock'; TimeoutSeconds = 12 },
    @{ ProcessName = 'MacMakeover.Supervisor'; TaskName = 'MacMakeover Shell - Supervisor'; TimeoutSeconds = 90 }
  )

  foreach ($required in $liveRecoveryComponents) {
    $instances = @(Get-Process -Name $required.ProcessName -ErrorAction SilentlyContinue |
      Where-Object { $_.SessionId -eq $sessionId })
    if ($instances.Count -ne 1) {
      Add-Result "Live recovery prerequisite: $($required.ProcessName)" $false "Expected one process; found $($instances.Count)." 0
      $recoveryReady = $false
    }

    $task = Get-ScheduledTask -TaskName $required.TaskName -ErrorAction SilentlyContinue
    if (-not $task -or $task.State -eq 'Disabled') {
      Add-Result "Live recovery prerequisite: $($required.TaskName)" $false 'Scheduled task is missing or disabled.' 0
      $recoveryReady = $false
    }
  }

  if ($recoveryReady) {
    try {
      # Force-stop one supervised component at a time and require a different PID.
      $menuHostRecovered = Test-ForceStopAndRecover `
        -ProcessName 'MacMakeover.MenuHost' `
        -SessionId $sessionId `
        -TimeoutSeconds 12 `
        -ResultName 'Supervisor recovers crashed MacMakeover.MenuHost'

      $menuBarRecovered = Test-ForceStopAndRecover `
        -ProcessName 'MacMakeover.MenuBar' `
        -SessionId $sessionId `
        -TimeoutSeconds 12 `
        -ResultName 'Supervisor recovers crashed MacMakeover.MenuBar'

      $dockRecovered = Test-ForceStopAndRecover `
        -ProcessName 'MacMakeover.Dock' `
        -SessionId $sessionId `
        -TimeoutSeconds 12 `
        -ResultName 'Supervisor recovers crashed MacMakeover.Dock'

      # MenuBar/Dock own work-area AppBars; prove reservations after both restarts.
      if ($menuBarRecovered -and $dockRecovered) {
        $profileScript = Join-Path $PSScriptRoot 'Test-NativeShellProfile.ps1'
        $profileTimer = [Diagnostics.Stopwatch]::StartNew()
        $profilePassed = $false
        $profileDetail = 'Profile gate did not run.'
        try {
          Start-Sleep -Seconds 2
          foreach ($attempt in 1..3) {
            $null = & $profileScript 2>&1
            if ($LASTEXITCODE -eq 0) {
              $profilePassed = $true
              $profileDetail = "Test-NativeShellProfile.ps1 exit 0 after MenuBar/Dock recovery (attempt $attempt)."
              break
            }
            $profileDetail = "Test-NativeShellProfile.ps1 exit $LASTEXITCODE after MenuBar/Dock recovery (attempt $attempt)."
            if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
          }
        } catch {
          $profileDetail = "Profile gate threw after MenuBar/Dock recovery: $($_.Exception.Message)"
        }
        $profileTimer.Stop()
        Add-Result 'Live recovery profile gate after MenuBar and Dock restart' $profilePassed $profileDetail $profileTimer.Elapsed.TotalMilliseconds
      } else {
        Add-Result 'Live recovery profile gate after MenuBar and Dock restart' $false 'Skipped because MenuBar or Dock recovery failed.' 0
      }

      if ($menuHostRecovered -and $menuBarRecovered -and $dockRecovered) {
        $supervisorRecovered = Test-ForceStopAndRecover `
          -ProcessName 'MacMakeover.Supervisor' `
          -SessionId $sessionId `
          -TimeoutSeconds 90 `
          -ResultName 'Scheduled watchdog recovers MacMakeover.Supervisor'

        if ($supervisorRecovered) {
          $null = Test-ForceStopAndRecover `
            -ProcessName 'MacMakeover.MenuHost' `
            -SessionId $sessionId `
            -TimeoutSeconds 12 `
            -ResultName 'Recovered Supervisor resumes MacMakeover.MenuHost monitoring'
        } else {
          Add-Result 'Recovered Supervisor resumes MacMakeover.MenuHost monitoring' $false 'Skipped because Supervisor watchdog recovery failed.' 0
        }
      } else {
        Add-Result 'Scheduled watchdog recovers MacMakeover.Supervisor' $false 'Skipped because a supervised component recovery failed.' 0
        Add-Result 'Recovered Supervisor resumes MacMakeover.MenuHost monitoring' $false 'Skipped because a supervised component recovery failed.' 0
      }
    } finally {
      $restoreTimer = [Diagnostics.Stopwatch]::StartNew()
      $restored = Restore-LiveRecoveryTargets -SessionId $sessionId
      $restoreTimer.Stop()
      Add-Result 'Live recovery cleanup leaves required components running' $restored 'Expected exactly one MenuHost, MenuBar, Dock, and Supervisor in the current session. Missing tasks are started; duplicates are reported without killing.' $restoreTimer.Elapsed.TotalMilliseconds
    }
  }
}

$failed = @($results | Where-Object { -not $_.passed })
$evidence = [ordered]@{
  capturedAt = (Get-Date).ToString('o')
  computer = $env:COMPUTERNAME
  interactiveAltTab = [bool]$IncludeInteractiveAltTab
  liveRecovery = [bool]$IncludeLiveRecovery
  passed = ($failed.Count -eq 0)
  results = $results
}
$evidence | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $evidencePath -Encoding utf8
Write-Host "Evidence: $evidencePath"

if ($failed.Count -gt 0) {
  Write-Error "$($failed.Count) native-shell regression check(s) failed."
  exit 1
}

Write-Host "PASS: all requested native-shell regression checks passed." -ForegroundColor Green
exit 0
