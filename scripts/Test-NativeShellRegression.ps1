[CmdletBinding()]
param(
  [switch]$SkipBuild,
  [switch]$IncludeInteractiveAltTab,
  [switch]$IncludeLiveRecovery,
  [switch]$SkipPerformanceSmoke,
  [string]$DeploymentRoot = (Join-Path $env:LOCALAPPDATA 'MacMakeover\bin'),
  [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'qa\regression')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
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

function Restore-LiveRecoveryTargets {
  param([int]$SessionId)

  $restored = $true
  foreach ($target in @(
      @{ ProcessName = 'MacMakeover.Supervisor'; TaskName = 'MacMakeover Shell - Supervisor'; Timeout = 90 },
      @{ ProcessName = 'MacMakeover.MenuHost'; TaskName = 'MacMakeover Shell - MenuHost'; Timeout = 15 }
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
  foreach ($required in 'MacMakeover.MenuHost', 'MacMakeover.Supervisor') {
    $instances = @(Get-Process -Name $required -ErrorAction SilentlyContinue |
      Where-Object { $_.SessionId -eq $sessionId })
    if ($instances.Count -ne 1) {
      Add-Result "Live recovery prerequisite: $required" $false "Expected one process; found $($instances.Count)." 0
      $recoveryReady = $false
    }
  }
  foreach ($taskName in 'MacMakeover Shell - MenuHost', 'MacMakeover Shell - Supervisor') {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task -or $task.State -eq 'Disabled') {
      Add-Result "Live recovery prerequisite: $taskName" $false 'Scheduled task is missing or disabled.' 0
      $recoveryReady = $false
    }
  }

  if ($recoveryReady) {
    try {
      $menuHostProcess = @(Get-Process -Name MacMakeover.MenuHost -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId } | Select-Object -First 1)
      $timer = [Diagnostics.Stopwatch]::StartNew()
      $oldId = $menuHostProcess.Id
      Stop-Process -Id $oldId -Force
      $replacement = Wait-ForReplacement -ProcessName 'MacMakeover.MenuHost' -PreviousId $oldId -TimeoutSeconds 12
      $timer.Stop()
      $replacementId = if ($replacement) { $replacement.Id } else { 'none' }
      Add-Result 'Supervisor recovers a crashed component' ($null -ne $replacement) "Automatic recovery only. Old PID $oldId; new PID $replacementId." $timer.Elapsed.TotalMilliseconds

      if ($replacement) {
        $supervisor = @(Get-Process -Name MacMakeover.Supervisor -ErrorAction SilentlyContinue |
          Where-Object { $_.SessionId -eq $sessionId } | Select-Object -First 1)
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $oldId = $supervisor.Id
        Stop-Process -Id $oldId -Force
        $replacement = Wait-ForReplacement -ProcessName 'MacMakeover.Supervisor' -PreviousId $oldId -TimeoutSeconds 90
        $timer.Stop()
        $replacementId = if ($replacement) { $replacement.Id } else { 'none' }
        Add-Result 'Scheduled watchdog recovers the Supervisor' ($null -ne $replacement) "Automatic recovery only. Old PID $oldId; new PID $replacementId." $timer.Elapsed.TotalMilliseconds

        if ($replacement) {
          $menuHostProcess = @(Get-Process -Name MacMakeover.MenuHost -ErrorAction SilentlyContinue |
            Where-Object { $_.SessionId -eq $sessionId } | Select-Object -First 1)
          if ($menuHostProcess) {
            $timer = [Diagnostics.Stopwatch]::StartNew()
            $oldHostId = $menuHostProcess.Id
            Stop-Process -Id $oldHostId -Force
            $hostReplacement = Wait-ForReplacement -ProcessName 'MacMakeover.MenuHost' -PreviousId $oldHostId -TimeoutSeconds 12
            $timer.Stop()
            $hostReplacementId = if ($hostReplacement) { $hostReplacement.Id } else { 'none' }
            Add-Result 'Recovered Supervisor resumes component monitoring' ($null -ne $hostReplacement) "Automatic recovery only. Old PID $oldHostId; new PID $hostReplacementId." $timer.Elapsed.TotalMilliseconds
          } else {
            Add-Result 'Recovered Supervisor resumes component monitoring' $false 'MenuHost was absent before the recovered Supervisor could be tested.' 0
          }
        }
      }
    } finally {
      $restoreTimer = [Diagnostics.Stopwatch]::StartNew()
      $restored = Restore-LiveRecoveryTargets -SessionId $sessionId
      $restoreTimer.Stop()
      Add-Result 'Live recovery cleanup leaves required components running' $restored 'Expected exactly one Supervisor and one MenuHost in the current session.' $restoreTimer.Elapsed.TotalMilliseconds
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
