[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "config\hot-corners.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

$signature = @"
using System;
using System.Runtime.InteropServices;

public static class MacMakeoverHotCornersNative {
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT {
    public int X;
    public int Y;
  }

  [DllImport("user32.dll")]
  public static extern bool GetCursorPos(out POINT lpPoint);

  [DllImport("user32.dll")]
  public static extern short GetAsyncKeyState(int vKey);

  [DllImport("user32.dll")]
  public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, UIntPtr dwExtraInfo);
}
"@
Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue

$script:PackageRoot = Split-Path -Parent $PSScriptRoot
$script:AppleMenuScriptPath = Join-Path $PSScriptRoot "Show-MacAppleMenu.ps1"
$script:ControlCenterScriptPath = Join-Path $PSScriptRoot "Show-MacControlCenter.ps1"
$script:MenuHostProjectPath = Join-Path $script:PackageRoot "tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj"
$script:MenuHostExePath = Join-Path $script:PackageRoot "tools\MacMakeover.MenuHost\bin\Release\net10.0-windows\MacMakeover.MenuHost.exe"
$script:MenuHostPipeName = "MacMakeover.MenuHost"
$script:MenuInvocations = @()
$script:WarmMenuRunspaces = @{}

function Read-HotCornerConfig {
  param([string]$Path)

  $defaults = [ordered]@{
    enabled = $true
    cornerSize = 14
    dwellMilliseconds = 750
    cooldownMilliseconds = 1800
    pollMilliseconds = 30
    clickEnabled = $true
    clickCornerSize = 16
    clickCooldownMilliseconds = 650
    topLeftClick = "ShowDesktop"
    topRightClick = "ShowDesktop"
    bottomLeftClick = "None"
    bottomRightClick = "None"
    appleMenuClickEnabled = $true
    appleMenuZoneLeft = 24
    appleMenuZoneRight = 78
    appleMenuClickCooldownMilliseconds = 300
    controlCenterClickEnabled = $true
    topBarClickHeight = 40
    controlCenterRightButtonWidth = 72
    controlCenterPowerZoneLeftOffset = 245
    controlCenterPowerZoneRightOffset = 125
    controlCenterClickCooldownMilliseconds = 300
    topLeft = "None"
    topRight = "None"
    bottomLeft = "ShowDesktop"
    bottomRight = "Lock"
    logPath = "%LOCALAPPDATA%\MacMakeover\hot-corners.log"
  }

  if (Test-Path -LiteralPath $Path) {
    $fileConfig = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($property in $fileConfig.PSObject.Properties) {
      $defaults[$property.Name] = $property.Value
    }
  }

  [pscustomobject]$defaults
}

function Write-HotCornerLog {
  param(
    [object]$Config,
    [string]$Message
  )

  $logPath = [Environment]::ExpandEnvironmentVariables([string]$Config.logPath)
  $logDir = Split-Path -Parent $logPath
  if ($logDir) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  }

  $line = "{0} {1}" -f (Get-Date).ToString("s"), $Message
  Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
}

function Send-Hotkey {
  param([byte[]]$Keys)

  foreach ($key in $Keys) {
    [MacMakeoverHotCornersNative]::keybd_event($key, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 20
  }

  for ($i = $Keys.Length - 1; $i -ge 0; $i--) {
    [MacMakeoverHotCornersNative]::keybd_event($Keys[$i], 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 15
  }
}

function Invoke-HotCornerAction {
  param(
    [string]$Action,
    [object]$Config
  )

  switch ($Action) {
    "None" { return }
    "Spotlight" { Send-Hotkey ([byte[]](0x12, 0x20)) }
    "TaskView" { Send-Hotkey ([byte[]](0x5B, 0x09)) }
    "ShowDesktop" { Send-Hotkey ([byte[]](0x5B, 0x44)) }
    "Lock" { Start-Process -FilePath "$env:windir\System32\rundll32.exe" -ArgumentList "user32.dll,LockWorkStation" }
    "Sleep" { Start-Process -FilePath "$env:windir\System32\rundll32.exe" -ArgumentList "powrprof.dll,SetSuspendState 0,1,0" }
    "ClipboardHistory" { Send-Hotkey ([byte[]](0x5B, 0x56)) }
    default { Write-HotCornerLog $Config "Unknown action '$Action' ignored." }
  }
}

function Clear-CompletedMenuInvocations {
  if (-not $script:MenuInvocations.Count) { return }

  $active = @()
  foreach ($invocation in $script:MenuInvocations) {
    if ($invocation.Async.IsCompleted) {
      try {
        $invocation.PowerShell.EndInvoke($invocation.Async) | Out-Null
      } catch {
        Write-HotCornerLog $invocation.Config "Menu script failed: $($_.Exception.Message)"
      } finally {
        $invocation.PowerShell.Dispose()
        $invocation.Runspace.Dispose()
        Start-MacMakeoverMenuWarmRunspace -ScriptPath $invocation.ScriptPath -Config $invocation.Config
      }
    } else {
      $active += $invocation
    }
  }

  $script:MenuInvocations = $active
}

function New-MacMakeoverStaRunspace {
  $runspace = [runspacefactory]::CreateRunspace()
  $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
  $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
  $runspace.Open()
  return $runspace
}

function Start-MacMakeoverMenuWarmRunspace {
  param(
    [string]$ScriptPath,
    [object]$Config
  )

  if (-not (Test-Path -LiteralPath $ScriptPath)) {
    Write-HotCornerLog $Config "Menu warm-up skipped, missing script: $ScriptPath"
    return
  }

  if ($script:WarmMenuRunspaces.ContainsKey($ScriptPath)) { return }

  $runspace = New-MacMakeoverStaRunspace
  $powershell = [powershell]::Create()
  $powershell.Runspace = $runspace
  try {
    $powershell.AddCommand($ScriptPath).AddParameter("WarmUp") | Out-Null
    $powershell.Invoke() | Out-Null
    $script:WarmMenuRunspaces[$ScriptPath] = $runspace
  } catch {
    Write-HotCornerLog $Config "Menu warm-up failed for $ScriptPath`: $($_.Exception.Message)"
    $runspace.Dispose()
  } finally {
    $powershell.Dispose()
  }
}

function Use-MacMakeoverMenuRunspace {
  param([string]$ScriptPath)

  if ($script:WarmMenuRunspaces.ContainsKey($ScriptPath)) {
    $runspace = $script:WarmMenuRunspaces[$ScriptPath]
    $script:WarmMenuRunspaces.Remove($ScriptPath)
    return $runspace
  }

  return (New-MacMakeoverStaRunspace)
}

function Start-MacMakeoverMenuScript {
  param(
    [string]$ScriptPath,
    [string]$Argument,
    [object]$Config
  )

  Clear-CompletedMenuInvocations

  if (-not (Test-Path -LiteralPath $ScriptPath)) {
    Write-HotCornerLog $Config "Menu script missing: $ScriptPath"
    return
  }

  $runspace = Use-MacMakeoverMenuRunspace -ScriptPath $ScriptPath
  $powershell = [powershell]::Create()
  $powershell.Runspace = $runspace
  $powershell.AddCommand($ScriptPath) | Out-Null
  if (-not [string]::IsNullOrWhiteSpace($Argument)) {
    $powershell.AddArgument($Argument) | Out-Null
  }

  $async = $powershell.BeginInvoke()
  $script:MenuInvocations += [pscustomobject]@{
    PowerShell = $powershell
    Runspace = $runspace
    Async = $async
    Config = $Config
    ScriptPath = $ScriptPath
  }
}

function Build-MacMakeoverMenuHost {
  param([object]$Config)

  if (Test-Path -LiteralPath $script:MenuHostExePath) { return $true }
  if (-not (Test-Path -LiteralPath $script:MenuHostProjectPath)) {
    Write-HotCornerLog $Config "MenuHost build skipped, missing project: $script:MenuHostProjectPath"
    return $false
  }

  $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
  if (-not $dotnet) {
    Write-HotCornerLog $Config "MenuHost build skipped, dotnet was not found."
    return $false
  }

  try {
    $output = & $dotnet build $script:MenuHostProjectPath -c Release --nologo 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-HotCornerLog $Config "MenuHost build failed: $($output -join ' ')"
      return $false
    }

    return (Test-Path -LiteralPath $script:MenuHostExePath)
  } catch {
    Write-HotCornerLog $Config "MenuHost build error: $($_.Exception.Message)"
    return $false
  }
}

function Start-MacMakeoverMenuHost {
  param([object]$Config)

  if (-not (Build-MacMakeoverMenuHost -Config $Config)) { return $false }

  try {
    Start-Process -FilePath $script:MenuHostExePath -WindowStyle Hidden | Out-Null
    return $true
  } catch {
    Write-HotCornerLog $Config "MenuHost start failed: $($_.Exception.Message)"
    return $false
  }
}

function Send-MacMakeoverMenuHostCommand {
  param(
    [ValidateSet("apple", "control")]
    [string]$Command,
    [object]$Config
  )

  if (-not (Build-MacMakeoverMenuHost -Config $Config)) { return $false }

  for ($attempt = 0; $attempt -lt 4; $attempt++) {
    try {
      $client = [System.IO.Pipes.NamedPipeClientStream]::new(".", $script:MenuHostPipeName, [System.IO.Pipes.PipeDirection]::Out)
      try {
        $client.Connect(160)
        $writer = [System.IO.StreamWriter]::new($client, [System.Text.Encoding]::UTF8)
        try {
          $writer.AutoFlush = $true
          $writer.WriteLine($Command)
          return $true
        } finally {
          $writer.Dispose()
        }
      } finally {
        $client.Dispose()
      }
    } catch {
      if ($attempt -eq 0) {
        Start-MacMakeoverMenuHost -Config $Config | Out-Null
      }
      Start-Sleep -Milliseconds 140
    }
  }

  Write-HotCornerLog $Config "MenuHost command '$Command' failed after retries."
  return $false
}

function Start-MacMakeoverMenu {
  param(
    [ValidateSet("apple", "control")]
    [string]$Command,
    [object]$Config
  )

  if (Send-MacMakeoverMenuHostCommand -Command $Command -Config $Config) { return }

  if ($Command -eq "apple") {
    Start-MacMakeoverMenuScript -ScriptPath $script:AppleMenuScriptPath -Argument "" -Config $Config
    return
  }

  Start-MacMakeoverMenuScript -ScriptPath $script:ControlCenterScriptPath -Argument "macmakeover-control-center:" -Config $Config
}

function Invoke-MacMakeoverMenuWarmUp {
  param([object]$Config)

  Start-MacMakeoverMenuHost -Config $Config | Out-Null
}

function Test-AppleMenuClickZone {
  param(
    [int]$X,
    [int]$Y,
    [System.Drawing.Rectangle]$Bounds,
    [object]$Config
  )

  if (-not $Config.appleMenuClickEnabled) { return $false }
  if ($Y -gt ($Bounds.Top + [int]$Config.topBarClickHeight)) { return $false }

  $left = $Bounds.Left
  $top = $Bounds.Top
  $cornerSize = [int]$Config.clickCornerSize

  # Preserve the exact physical corner for Show Desktop.
  if ($X -le ($left + $cornerSize) -and $Y -le ($top + $cornerSize)) {
    return $false
  }

  return $X -ge ($left + [int]$Config.appleMenuZoneLeft) -and $X -le ($left + [int]$Config.appleMenuZoneRight)
}

function Test-ControlCenterClickZone {
  param(
    [int]$X,
    [int]$Y,
    [System.Drawing.Rectangle]$Bounds,
    [object]$Config
  )

  if (-not $Config.controlCenterClickEnabled) { return $false }
  if ($Y -gt ($Bounds.Top + [int]$Config.topBarClickHeight)) { return $false }

  $right = $Bounds.Right - 1
  $top = $Bounds.Top
  $cornerSize = [int]$Config.clickCornerSize

  # Preserve the exact physical corner for Show Desktop.
  if ($X -ge ($right - $cornerSize) -and $Y -le ($top + $cornerSize)) {
    return $false
  }

  $inRightButton = $X -ge ($right - [int]$Config.controlCenterRightButtonWidth)
  $powerZoneLeft = $right - [int]$Config.controlCenterPowerZoneLeftOffset
  $powerZoneRight = $right - [int]$Config.controlCenterPowerZoneRightOffset
  $inPowerZone = $X -ge $powerZoneLeft -and $X -le $powerZoneRight

  return $inRightButton -or $inPowerZone
}

function Get-CornerAtPoint {
  param(
    [int]$X,
    [int]$Y,
    [System.Drawing.Rectangle]$Bounds,
    [int]$CornerSize
  )

  $left = $Bounds.Left
  $top = $Bounds.Top
  $right = $Bounds.Right - 1
  $bottom = $Bounds.Bottom - 1

  if ($X -le ($left + $CornerSize) -and $Y -le ($top + $CornerSize)) { return "TopLeft" }
  if ($X -ge ($right - $CornerSize) -and $Y -le ($top + $CornerSize)) { return "TopRight" }
  if ($X -le ($left + $CornerSize) -and $Y -ge ($bottom - $CornerSize)) { return "BottomLeft" }
  if ($X -ge ($right - $CornerSize) -and $Y -ge ($bottom - $CornerSize)) { return "BottomRight" }

  $null
}

$config = Read-HotCornerConfig $ConfigPath
if (-not $config.enabled) {
  Write-HotCornerLog $config "Hot corners disabled in config."
  return
}

Write-HotCornerLog $config "Hot corners started from $PSCommandPath with config $ConfigPath."
Invoke-MacMakeoverMenuWarmUp $config

$activeCorner = $null
$enteredAt = Get-Date
$lastTriggered = @{}
$lastClickTriggered = @{}
$lastControlCenterClick = [datetime]::MinValue
$lastAppleMenuClick = [datetime]::MinValue
$wasLeftMouseDown = $false

while ($true) {
  try {
    $point = New-Object MacMakeoverHotCornersNative+POINT
    [MacMakeoverHotCornersNative]::GetCursorPos([ref]$point) | Out-Null

    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $corner = Get-CornerAtPoint -X $point.X -Y $point.Y -Bounds $bounds -CornerSize ([int]$config.cornerSize)
    $clickCorner = Get-CornerAtPoint -X $point.X -Y $point.Y -Bounds $bounds -CornerSize ([int]$config.clickCornerSize)
    $leftMouseState = [int][MacMakeoverHotCornersNative]::GetAsyncKeyState(0x01)
    $leftMouseDown = ($leftMouseState -band 0x8000) -ne 0
    $leftMousePressed = (($leftMouseState -band 0x0001) -ne 0) -or ($leftMouseDown -and -not $wasLeftMouseDown)
    $now = Get-Date

    if ($leftMousePressed -and (Test-AppleMenuClickZone -X $point.X -Y $point.Y -Bounds $bounds -Config $config)) {
      $appleMenuCooldownElapsed = ($now - $lastAppleMenuClick).TotalMilliseconds -ge [int]$config.appleMenuClickCooldownMilliseconds
      if ($appleMenuCooldownElapsed) {
        Write-HotCornerLog $config "TopBar click -> AppleMenu"
        Start-MacMakeoverMenu -Command "apple" -Config $config
        $lastAppleMenuClick = $now
      }
    }

    if ($leftMousePressed -and (Test-ControlCenterClickZone -X $point.X -Y $point.Y -Bounds $bounds -Config $config)) {
      $controlCenterCooldownElapsed = ($now - $lastControlCenterClick).TotalMilliseconds -ge [int]$config.controlCenterClickCooldownMilliseconds
      if ($controlCenterCooldownElapsed) {
        Write-HotCornerLog $config "TopBar click -> ControlCenter"
        Start-MacMakeoverMenu -Command "control" -Config $config
        $lastControlCenterClick = $now
      }
    }

    if ($config.clickEnabled -and $clickCorner -and $leftMousePressed) {
      $lastClick = if ($lastClickTriggered.ContainsKey($clickCorner)) { $lastClickTriggered[$clickCorner] } else { [datetime]::MinValue }
      $clickCooldownElapsed = ($now - $lastClick).TotalMilliseconds -ge [int]$config.clickCooldownMilliseconds

      if ($clickCooldownElapsed) {
        $clickAction = switch ($clickCorner) {
          "TopLeft" { $config.topLeftClick }
          "TopRight" { $config.topRightClick }
          "BottomLeft" { $config.bottomLeftClick }
          "BottomRight" { $config.bottomRightClick }
        }

        if ([string]$clickAction -ne "None") {
          Write-HotCornerLog $config "$clickCorner click -> $clickAction"
          Invoke-HotCornerAction -Action ([string]$clickAction) -Config $config
        }
        $lastClickTriggered[$clickCorner] = $now
        $lastTriggered[$clickCorner] = $now
      }
    }
    $wasLeftMouseDown = $leftMouseDown

    if ($corner -ne $activeCorner) {
      $activeCorner = $corner
      $enteredAt = $now
    }

    if ($corner) {
      $dwellElapsed = ($now - $enteredAt).TotalMilliseconds -ge [int]$config.dwellMilliseconds
      $last = if ($lastTriggered.ContainsKey($corner)) { $lastTriggered[$corner] } else { [datetime]::MinValue }
      $cooldownElapsed = ($now - $last).TotalMilliseconds -ge [int]$config.cooldownMilliseconds

      if ($dwellElapsed -and $cooldownElapsed) {
        $action = switch ($corner) {
          "TopLeft" { $config.topLeft }
          "TopRight" { $config.topRight }
          "BottomLeft" { $config.bottomLeft }
          "BottomRight" { $config.bottomRight }
        }

        if ([string]$action -ne "None") {
          Write-HotCornerLog $config "$corner -> $action"
          Invoke-HotCornerAction -Action ([string]$action) -Config $config
        }
        $lastTriggered[$corner] = Get-Date
      }
    }
  } catch {
    Write-HotCornerLog $config "Error: $($_.Exception.Message)"
    Start-Sleep -Seconds 2
  }

  Clear-CompletedMenuInvocations
  Start-Sleep -Milliseconds ([int]$config.pollMilliseconds)
}
