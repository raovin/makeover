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

function Read-HotCornerConfig {
  param([string]$Path)

  $defaults = [ordered]@{
    enabled = $true
    cornerSize = 14
    dwellMilliseconds = 750
    cooldownMilliseconds = 1800
    pollMilliseconds = 25
    clickEnabled = $true
    clickCornerSize = 16
    clickCooldownMilliseconds = 650
    topLeftClick = "ShowDesktop"
    topRightClick = "ShowDesktop"
    bottomLeftClick = "None"
    bottomRightClick = "None"
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

$activeCorner = $null
$enteredAt = Get-Date
$lastTriggered = @{}
$lastClickTriggered = @{}
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

  Start-Sleep -Milliseconds ([int]$config.pollMilliseconds)
}
