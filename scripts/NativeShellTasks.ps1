Set-StrictMode -Version Latest

function Get-NativeShellTaskDefinitions {
  param(
    [Parameter(Mandatory)]
    [string]$DeploymentRoot
  )

  @(
    [ordered]@{ TaskName = 'MacMakeover Shell - MenuHost'; ProcessName = 'MacMakeover.MenuHost'; FileName = 'MacMakeover.MenuHost.exe' }
    [ordered]@{ TaskName = 'MacMakeover Shell - MenuBar'; ProcessName = 'MacMakeover.MenuBar'; FileName = 'MacMakeover.MenuBar.exe' }
    [ordered]@{ TaskName = 'MacMakeover Shell - Dock'; ProcessName = 'MacMakeover.Dock'; FileName = 'MacMakeover.Dock.exe' }
    [ordered]@{ TaskName = 'MacMakeover Shell - Awake'; ProcessName = 'AwakeAndAvailable'; FileName = 'AwakeAndAvailable.exe' }
    [ordered]@{ TaskName = 'MacMakeover Shell - Supervisor'; ProcessName = 'MacMakeover.Supervisor'; FileName = 'MacMakeover.Supervisor.exe' }
  ) | ForEach-Object {
    [pscustomobject]@{
      TaskName = $_.TaskName
      ProcessName = $_.ProcessName
      Executable = Join-Path $DeploymentRoot $_.FileName
    }
  }
}

function Register-NativeShellTasks {
  param(
    [Parameter(Mandatory)]
    [string]$DeploymentRoot
  )

  $definitions = @(Get-NativeShellTaskDefinitions -DeploymentRoot $DeploymentRoot)
  foreach ($definition in $definitions) {
    if (-not (Test-Path -LiteralPath $definition.Executable)) {
      throw "Cannot register $($definition.TaskName); executable is missing: $($definition.Executable)"
    }
  }

  $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  $previousTasks = @{}
  foreach ($definition in $definitions) {
    $existing = Get-ScheduledTask -TaskName $definition.TaskName -ErrorAction SilentlyContinue
    $previousTasks[$definition.TaskName] = if ($existing) {
      Export-ScheduledTask -TaskName $definition.TaskName
    } else {
      $null
    }
  }

  $registered = [Collections.Generic.List[string]]::new()
  try {
    foreach ($definition in $definitions) {
      # Create fresh CIM objects for every task; Scheduler object reuse is not reliable.
      $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
      $triggers = @($logonTrigger)
      if ($definition.ProcessName -eq 'MacMakeover.Supervisor') {
        # IgnoreNew makes this a cheap health check while the watchdog is healthy.
        $triggers += New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddMinutes(1)) `
          -RepetitionInterval (New-TimeSpan -Minutes 1) `
          -RepetitionDuration (New-TimeSpan -Days 3650)
      }
      $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
      $settings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -DontStopOnIdleEnd `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)
      $action = New-ScheduledTaskAction -Execute $definition.Executable
      Register-ScheduledTask -TaskName $definition.TaskName -Action $action -Trigger $triggers `
        -Principal $principal -Settings $settings -Force | Out-Null
      $registered.Add($definition.TaskName)
    }
  } catch {
    foreach ($taskName in $registered) {
      $previousXml = $previousTasks[$taskName]
      if ($previousXml) {
        Register-ScheduledTask -TaskName $taskName -Xml $previousXml -Force | Out-Null
      } else {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
      }
    }
    throw
  }
}

function Stop-NativeShellTasks {
  param(
    [Parameter(Mandatory)]
    [string]$DeploymentRoot
  )

  foreach ($definition in Get-NativeShellTaskDefinitions -DeploymentRoot $DeploymentRoot) {
    Stop-ScheduledTask -TaskName $definition.TaskName -ErrorAction SilentlyContinue
  }
  Start-Sleep -Milliseconds 300
  $processNames = (Get-NativeShellTaskDefinitions -DeploymentRoot $DeploymentRoot).ProcessName
  Get-Process -Name $processNames -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
}

function Start-NativeShellTasks {
  param(
    [Parameter(Mandatory)]
    [string]$DeploymentRoot
  )

  $definitions = @(Get-NativeShellTaskDefinitions -DeploymentRoot $DeploymentRoot)
  foreach ($definition in $definitions) {
    $task = Get-ScheduledTask -TaskName $definition.TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
      throw "Persistent native-shell task is missing: $($definition.TaskName)"
    }
    if ($task.State -eq 'Disabled') {
      throw "Persistent native-shell task is disabled: $($definition.TaskName)"
    }
  }

  try {
    foreach ($definition in $definitions) {
      Start-ScheduledTask -TaskName $definition.TaskName
      $deadline = [DateTime]::UtcNow.AddSeconds(8)
      do {
        Start-Sleep -Milliseconds 200
        $process = @(Get-Process -Name $definition.ProcessName -ErrorAction SilentlyContinue |
          Where-Object { $_.SessionId -eq [Diagnostics.Process]::GetCurrentProcess().SessionId })
      } until ($process.Count -gt 0 -or [DateTime]::UtcNow -ge $deadline)
      if ($process.Count -eq 0) {
        throw "$($definition.TaskName) did not start its interactive process within 8 seconds."
      }
    }
  } catch {
    foreach ($definition in $definitions) {
      Stop-ScheduledTask -TaskName $definition.TaskName -ErrorAction SilentlyContinue
    }
    Get-Process -Name $definitions.ProcessName -ErrorAction SilentlyContinue |
      Stop-Process -Force -ErrorAction SilentlyContinue
    throw
  }
}
