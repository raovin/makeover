[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$Profile,

  [Parameter(Mandatory)]
  [string[]]$CustomProcessNames,

  [ValidateRange(15, 1800)]
  [int]$DurationSeconds = 90,

  [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'qa\performance')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Percentile([double[]]$Values, [double]$Percentile) {
  if (-not $Values -or $Values.Count -eq 0) { return 0 }
  $sorted = @($Values | Sort-Object)
  $index = [Math]::Ceiling(($Percentile / 100) * $sorted.Count) - 1
  $index = [Math]::Max(0, [Math]::Min($sorted.Count - 1, $index))
  return [double]$sorted[$index]
}

function Get-ProcessSnapshot([string[]]$Names) {
  $snapshot = @{}
  foreach ($process in Get-Process -Name $Names -ErrorAction SilentlyContinue) {
    try {
      $snapshot[$process.Id] = [pscustomobject]@{
        Id = $process.Id
        Name = $process.ProcessName
        CpuSeconds = [double]$process.TotalProcessorTime.TotalSeconds
        WorkingSetBytes = [double]$process.WorkingSet64
        PrivateBytes = [double]$process.PrivateMemorySize64
        Threads = $process.Threads.Count
        Handles = $process.HandleCount
        Responding = $process.Responding
      }
    } catch {
      # A process can exit between enumeration and property access.
    }
  }
  return $snapshot
}

function Get-Sum($Snapshot, [string[]]$Names, [string]$Property) {
  $sum = 0.0
  foreach ($item in $Snapshot.Values) {
    if ($Names -contains $item.Name) { $sum += [double]$item.$Property }
  }
  return $sum
}

$logicalProcessors = [Environment]::ProcessorCount
$shellProcessNames = @('explorer', 'dwm')
$allProcessNames = @($CustomProcessNames + $shellProcessNames | Sort-Object -Unique)
$expectedCustomNames = @($CustomProcessNames | Sort-Object -Unique)
$counterNames = @(
  '\Processor(_Total)\% Processor Time',
  '\Memory\Available MBytes',
  '\Memory\Committed Bytes'
)

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$safeProfile = $Profile -replace '[^A-Za-z0-9_-]', '-'
$csvPath = Join-Path $OutputDirectory "$stamp-$safeProfile.csv"
$summaryPath = Join-Path $OutputDirectory "$stamp-$safeProfile-summary.json"

$previous = Get-ProcessSnapshot $allProcessNames
$previousCustomCpuSeconds = Get-Sum $previous $expectedCustomNames 'CpuSeconds'
$previousShellCpuSeconds = Get-Sum $previous $allProcessNames 'CpuSeconds'
$previousTime = [DateTime]::UtcNow
$rows = [System.Collections.Generic.List[object]]::new()
$samples = [Math]::Max(1, $DurationSeconds)

Write-Host "Sampling $Profile for $samples seconds..."
foreach ($sampleIndex in 1..$samples) {
  $counter = Get-Counter -Counter $counterNames -SampleInterval 1 -MaxSamples 1
  $now = [DateTime]::UtcNow
  $current = Get-ProcessSnapshot $allProcessNames
  $elapsed = ($now - $previousTime).TotalSeconds

  $customCpuSeconds = Get-Sum $current $expectedCustomNames 'CpuSeconds'
  $shellCpuSeconds = Get-Sum $current $allProcessNames 'CpuSeconds'
  $customCpuDelta = [Math]::Max(0.0, [double]($customCpuSeconds - $previousCustomCpuSeconds))
  $shellCpuDelta = [Math]::Max(0.0, [double]($shellCpuSeconds - $previousShellCpuSeconds))
  $customCpuPercent = if ($elapsed -gt 0) {
    100.0 * $customCpuDelta / $elapsed / $logicalProcessors
  } else { 0.0 }
  $shellCpuPercent = if ($elapsed -gt 0) {
    100.0 * $shellCpuDelta / $elapsed / $logicalProcessors
  } else { 0.0 }

  $counterMap = @{}
  foreach ($counterSample in $counter.CounterSamples) {
    $counterMap[$counterSample.Path.ToLowerInvariant()] = [double]$counterSample.CookedValue
  }
  $systemCpu = ($counterMap.GetEnumerator() | Where-Object Key -like '*processor(_total)*processor time').Value
  $availableMb = ($counterMap.GetEnumerator() | Where-Object Key -like '*memory*available mbytes').Value
  $committedBytes = ($counterMap.GetEnumerator() | Where-Object Key -like '*memory*committed bytes').Value

  $presentCustomNames = @($current.Values | Where-Object { $expectedCustomNames -contains $_.Name } |
    Select-Object -ExpandProperty Name -Unique)
  $missingCustomNames = @($expectedCustomNames | Where-Object { $_ -notin $presentCustomNames })
  $customItems = @($current.Values | Where-Object { $expectedCustomNames -contains $_.Name })
  $shellItems = @($current.Values | Where-Object { $allProcessNames -contains $_.Name })

  $rows.Add([pscustomobject]@{
    Profile = $Profile
    Sample = $sampleIndex
    TimestampUtc = $now.ToString('o')
    SystemCpuPercent = [Math]::Round($systemCpu, 3)
    AvailableMemoryMb = [Math]::Round($availableMb, 3)
    CommittedMemoryMb = [Math]::Round($committedBytes / 1MB, 3)
    CustomCpuPercent = [Math]::Round($customCpuPercent, 4)
    ShellCpuPercent = [Math]::Round($shellCpuPercent, 4)
    CustomCpuSeconds = [Math]::Round($customCpuSeconds, 6)
    ShellCpuSeconds = [Math]::Round($shellCpuSeconds, 6)
    CustomCpuDeltaSeconds = [Math]::Round($customCpuDelta, 6)
    ShellCpuDeltaSeconds = [Math]::Round($shellCpuDelta, 6)
    CustomWorkingSetMb = [Math]::Round((Get-Sum $current $expectedCustomNames 'WorkingSetBytes') / 1MB, 3)
    CustomPrivateMb = [Math]::Round((Get-Sum $current $expectedCustomNames 'PrivateBytes') / 1MB, 3)
    ShellWorkingSetMb = [Math]::Round((Get-Sum $current $allProcessNames 'WorkingSetBytes') / 1MB, 3)
    ShellPrivateMb = [Math]::Round((Get-Sum $current $allProcessNames 'PrivateBytes') / 1MB, 3)
    CustomThreads = [int](($customItems | Measure-Object Threads -Sum).Sum)
    CustomHandles = [int](($customItems | Measure-Object Handles -Sum).Sum)
    ShellThreads = [int](($shellItems | Measure-Object Threads -Sum).Sum)
    ShellHandles = [int](($shellItems | Measure-Object Handles -Sum).Sum)
    AllCustomProcessesPresent = ($missingCustomNames.Count -eq 0)
    AllResponsive = -not ($shellItems | Where-Object { -not $_.Responding })
    MissingCustomProcesses = ($missingCustomNames -join ',')
  })

  $previous = $current
  $previousCustomCpuSeconds = $customCpuSeconds
  $previousShellCpuSeconds = $shellCpuSeconds
  $previousTime = $now
}

$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
$steadyRows = @($rows | Select-Object -Skip ([Math]::Min(5, $rows.Count - 1)))
if (-not $steadyRows) { $steadyRows = @($rows) }

$metricNames = @(
  'SystemCpuPercent', 'AvailableMemoryMb', 'CommittedMemoryMb',
  'CustomCpuPercent', 'ShellCpuPercent', 'CustomWorkingSetMb',
  'CustomPrivateMb', 'ShellWorkingSetMb', 'ShellPrivateMb',
  'CustomThreads', 'CustomHandles', 'ShellThreads', 'ShellHandles'
)
$metrics = [ordered]@{}
foreach ($metricName in $metricNames) {
  $values = [double[]]@($steadyRows | ForEach-Object { [double]$_.$metricName })
  $metrics[$metricName] = [ordered]@{
    median = [Math]::Round((Get-Percentile $values 50), 3)
    p95 = [Math]::Round((Get-Percentile $values 95), 3)
    min = [Math]::Round(($values | Measure-Object -Minimum).Minimum, 3)
    max = [Math]::Round(($values | Measure-Object -Maximum).Maximum, 3)
  }
}

$summary = [ordered]@{
  profile = $Profile
  capturedAt = (Get-Date).ToString('o')
  durationSeconds = $DurationSeconds
  warmupSamplesExcluded = $rows.Count - $steadyRows.Count
  logicalProcessors = $logicalProcessors
  customProcessNames = $expectedCustomNames
  samples = $rows.Count
  allExpectedProcessesPresent = -not ($rows | Where-Object { -not $_.AllCustomProcessesPresent })
  allProcessesResponsive = -not ($rows | Where-Object { -not $_.AllResponsive })
  metrics = $metrics
  csv = $csvPath
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host "Samples: $csvPath"
Write-Host "Summary: $summaryPath"
$summary | ConvertTo-Json -Depth 8
