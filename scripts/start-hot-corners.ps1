[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "config\hot-corners.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Single-instance guard: only one hot-corners helper may poll the mouse. A second copy
# (e.g. the Startup shortcut plus a manual launch) makes every menu/corner click fire
# twice, which flickers the Apple/Control Center popovers open-then-closed. Held for the
# process lifetime; Windows releases the named mutex when this process exits.
$hotCornerCreatedNew = $false
$script:HotCornerMutex = New-Object System.Threading.Mutex($true, "Local\MacMakeoverHotCorners", [ref]$hotCornerCreatedNew)
if (-not $hotCornerCreatedNew) { exit }

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

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int maxLength);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder text, int maxLength);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  // Seelen flyout popups are sticky: they do not dismiss on an outside click. Hide any
  // visible Tauri popup window ("Bluetooth Popup", "Calendar Popup", ..., and the
  // network panel which is titled just "Network") that does not contain the click
  // point, so they behave like normal menus. Seelen "Tooltip" windows are transient
  // hover labels that linger and overlap the bar - hide those on every click.
  public static void HideSeelenPopupsOutside(int x, int y) {
    EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
      if (!IsWindowVisible(hWnd)) return true;
      var titleBuilder = new System.Text.StringBuilder(128);
      GetWindowText(hWnd, titleBuilder, 128);
      var title = titleBuilder.ToString();
      bool isPopup = title.EndsWith(" Popup", StringComparison.Ordinal) || title == "Network";
      bool isTooltip = title == "Tooltip";
      if (!isPopup && !isTooltip) return true;
      var className = new System.Text.StringBuilder(128);
      GetClassName(hWnd, className, 128);
      if (className.ToString() != "Tauri Window") return true;
      if (isPopup) {
        RECT rect;
        GetWindowRect(hWnd, out rect);
        if (x >= rect.Left && x <= rect.Right && y >= rect.Top && y <= rect.Bottom) return true;
      }
      ShowWindow(hWnd, 0);
      return true;
    }, IntPtr.Zero);
  }

  [DllImport("user32.dll")]
  public static extern bool IsZoomed(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool IsIconic(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern int GetWindowLong(IntPtr hWnd, int index);

  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);

  [DllImport("user32.dll")]
  public static extern bool SystemParametersInfo(uint action, uint param, ref RECT rect, uint flags);

  private static readonly System.Collections.Generic.HashSet<IntPtr> NudgedWindows = new System.Collections.Generic.HashSet<IntPtr>();

  // The menu bar reserves the top work-area strip, which stops window DRAGGING from
  // going underneath - but apps that restore/position themselves programmatically
  // (Snipping Tool remembering an old spot, etc.) can still park their title bar
  // under the bar. macOS simply never allows that. Evict such windows once: normal
  // captioned app windows only; fullscreen surfaces, minimized/maximized windows,
  // tool windows and Seelen's own Tauri windows are exempt.
  public static void NudgeWindowsOutOfBar(int screenHeight) {
    RECT work = new RECT();
    if (!SystemParametersInfo(0x0030, 0, ref work, 0)) return; // SPI_GETWORKAREA
    int workTop = work.Top;
    if (workTop <= 0) return;
    EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
      if (!IsWindowVisible(hWnd) || IsIconic(hWnd) || IsZoomed(hWnd)) return true;
      RECT r;
      GetWindowRect(hWnd, out r);
      if (r.Top < 0 || r.Top >= workTop) return true;                   // not parked in the strip
      if ((r.Bottom - r.Top) >= (int)(screenHeight * 0.9)) return true; // fullscreen-ish, leave alone
      int exStyle = GetWindowLong(hWnd, -20);                           // GWL_EXSTYLE
      if ((exStyle & 0x00000080) != 0) return true;                     // WS_EX_TOOLWINDOW
      int style = GetWindowLong(hWnd, -16);                             // GWL_STYLE
      if ((style & 0x00C00000) == 0) return true;                       // only captioned app windows
      var cls = new System.Text.StringBuilder(128);
      GetClassName(hWnd, cls, 128);
      string className = cls.ToString();
      if (className == "Tauri Window" || className == "Tao Thread Event Target" || className == "Progman" || className == "WorkerW" || className == "Shell_TrayWnd") return true;
      if (NudgedWindows.Contains(hWnd)) return true;                    // one nudge per window
      NudgedWindows.Add(hWnd);
      SetWindowPos(hWnd, IntPtr.Zero, r.Left, workTop, 0, 0, 0x0001 | 0x0004 | 0x0010); // NOSIZE|NOZORDER|NOACTIVATE
      return true;
    }, IntPtr.Zero);
  }

  // Bar clicks must not dismiss the popup they are opening, but lingering hover
  // tooltips should still vanish the moment anything is clicked.
  public static void HideSeelenTooltips() {
    EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
      if (!IsWindowVisible(hWnd)) return true;
      var titleBuilder = new System.Text.StringBuilder(128);
      GetWindowText(hWnd, titleBuilder, 128);
      if (titleBuilder.ToString() != "Tooltip") return true;
      var className = new System.Text.StringBuilder(128);
      GetClassName(hWnd, className, 128);
      if (className.ToString() != "Tauri Window") return true;
      ShowWindow(hWnd, 0);
      return true;
    }, IntPtr.Zero);
  }
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
    networkFlyoutClickEnabled = $false
    networkFlyoutZoneLeftOffset = 355
    networkFlyoutZoneRightOffset = 310
    networkFlyoutClickCooldownMilliseconds = 300
    batteryQuickSettingsClickEnabled = $false
    batteryQuickSettingsZoneLeftOffset = 310
    batteryQuickSettingsZoneRightOffset = 222
    batteryQuickSettingsClickCooldownMilliseconds = 300
    controlCenterClickEnabled = $false
    topBarClickHeight = 40
    controlCenterStatusZoneLeftOffset = 222
    controlCenterStatusZoneRightOffset = 188
    controlCenterClickCooldownMilliseconds = 300
    notificationCenterClickEnabled = $false
    notificationCenterZoneLeftOffset = 186
    notificationCenterZoneRightOffset = 140
    notificationCenterClickCooldownMilliseconds = 300
    calendarPopupClickEnabled = $false
    calendarPopupZoneLeftOffset = 138
    calendarPopupZoneRightOffset = 24
    calendarPopupClickCooldownMilliseconds = 300
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

function Open-WindowsShellUri {
  param(
    [string]$Uri,
    [object]$Config
  )

  try {
    Start-Process -FilePath $Uri -ErrorAction Stop
    return $true
  } catch {
    Write-HotCornerLog $Config "Shell URI '$Uri' failed: $($_.Exception.Message)"
    return $false
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
    "NotificationCenter" { Send-Hotkey ([byte[]](0x5B, 0x4E)) }
    "NetworkFlyout" {
      Close-MacMakeoverMenuHostPanels -Config $Config
      if (-not (Open-WindowsShellUri -Uri "ms-availablenetworks:" -Config $Config)) {
        Send-Hotkey ([byte[]](0x5B, 0x41))
      }
    }
    "QuickSettings" {
      Close-MacMakeoverMenuHostPanels -Config $Config
      Send-Hotkey ([byte[]](0x5B, 0x41))
    }
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
  if (Get-Process -Name "MacMakeover.MenuHost" -ErrorAction SilentlyContinue) { return $true }

  try {
    $process = Start-Process -FilePath $script:MenuHostExePath -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 180
    if ($process.HasExited) {
      Write-HotCornerLog $Config "MenuHost exited during startup with code $($process.ExitCode)."
      return $false
    }
    return $true
  } catch {
    Write-HotCornerLog $Config "MenuHost start failed: $($_.Exception.Message)"
    return $false
  }
}

function Send-MacMakeoverMenuHostCommand {
  param(
    [ValidateSet("apple", "control", "close")]
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

function Close-MacMakeoverMenuHostPanels {
  param([object]$Config)

  Send-MacMakeoverMenuHostCommand -Command "close" -Config $Config | Out-Null
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

  $statusZoneLeft = $right - [int]$Config.controlCenterStatusZoneLeftOffset
  $statusZoneRight = $right - [int]$Config.controlCenterStatusZoneRightOffset
  return $X -ge $statusZoneLeft -and $X -le $statusZoneRight
}

function Test-NetworkFlyoutClickZone {
  param(
    [int]$X,
    [int]$Y,
    [System.Drawing.Rectangle]$Bounds,
    [object]$Config
  )

  if (-not $Config.networkFlyoutClickEnabled) { return $false }
  if ($Y -gt ($Bounds.Top + [int]$Config.topBarClickHeight)) { return $false }

  $right = $Bounds.Right - 1
  $top = $Bounds.Top
  $cornerSize = [int]$Config.clickCornerSize

  # Preserve the exact physical corner for Show Desktop.
  if ($X -ge ($right - $cornerSize) -and $Y -le ($top + $cornerSize)) {
    return $false
  }

  $networkZoneLeft = $right - [int]$Config.networkFlyoutZoneLeftOffset
  $networkZoneRight = $right - [int]$Config.networkFlyoutZoneRightOffset
  return $X -ge $networkZoneLeft -and $X -le $networkZoneRight
}

function Test-BatteryQuickSettingsClickZone {
  param(
    [int]$X,
    [int]$Y,
    [System.Drawing.Rectangle]$Bounds,
    [object]$Config
  )

  if (-not $Config.batteryQuickSettingsClickEnabled) { return $false }
  if ($Y -gt ($Bounds.Top + [int]$Config.topBarClickHeight)) { return $false }

  $right = $Bounds.Right - 1
  $top = $Bounds.Top
  $cornerSize = [int]$Config.clickCornerSize

  # Preserve the exact physical corner for Show Desktop.
  if ($X -ge ($right - $cornerSize) -and $Y -le ($top + $cornerSize)) {
    return $false
  }

  $batteryZoneLeft = $right - [int]$Config.batteryQuickSettingsZoneLeftOffset
  $batteryZoneRight = $right - [int]$Config.batteryQuickSettingsZoneRightOffset
  return $X -ge $batteryZoneLeft -and $X -le $batteryZoneRight
}

function Test-NotificationCenterClickZone {
  param(
    [int]$X,
    [int]$Y,
    [System.Drawing.Rectangle]$Bounds,
    [object]$Config
  )

  if (-not $Config.notificationCenterClickEnabled) { return $false }
  if ($Y -gt ($Bounds.Top + [int]$Config.topBarClickHeight)) { return $false }

  $right = $Bounds.Right - 1
  $top = $Bounds.Top
  $cornerSize = [int]$Config.clickCornerSize

  # Preserve the exact physical corner for Show Desktop.
  if ($X -ge ($right - $cornerSize) -and $Y -le ($top + $cornerSize)) {
    return $false
  }

  $notificationZoneLeft = $right - [int]$Config.notificationCenterZoneLeftOffset
  $notificationZoneRight = $right - [int]$Config.notificationCenterZoneRightOffset
  return $X -ge $notificationZoneLeft -and $X -le $notificationZoneRight
}

function Test-CalendarPopupClickZone {
  param(
    [int]$X,
    [int]$Y,
    [System.Drawing.Rectangle]$Bounds,
    [object]$Config
  )

  if (-not $Config.calendarPopupClickEnabled) { return $false }
  if ($Y -gt ($Bounds.Top + [int]$Config.topBarClickHeight)) { return $false }

  $right = $Bounds.Right - 1
  $top = $Bounds.Top
  $cornerSize = [int]$Config.clickCornerSize

  # Preserve the exact physical corner for Show Desktop.
  if ($X -ge ($right - $cornerSize) -and $Y -le ($top + $cornerSize)) {
    return $false
  }

  $calendarZoneLeft = $right - [int]$Config.calendarPopupZoneLeftOffset
  $calendarZoneRight = $right - [int]$Config.calendarPopupZoneRightOffset
  return $X -ge $calendarZoneLeft -and $X -le $calendarZoneRight
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
$lastNetworkFlyoutClick = [datetime]::MinValue
$lastBatteryQuickSettingsClick = [datetime]::MinValue
$lastControlCenterClick = [datetime]::MinValue
$lastNotificationCenterClick = [datetime]::MinValue
$lastCalendarPopupClick = [datetime]::MinValue
$lastAppleMenuClick = [datetime]::MinValue
$wasLeftMouseDown = $false
$script:NudgeCounter = 0

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

    # Click-away dismissal for sticky Seelen popups (Network/Bluetooth/Calendar/
    # Notifications): any click below the top bar hides popups that do not contain the
    # click point. Clicks ON the bar only clear lingering hover tooltips, so the popup
    # being opened by that click is never dismissed by us in the same instant.
    if ($leftMousePressed) {
      if ($point.Y -gt ($bounds.Top + [int]$config.topBarClickHeight)) {
        try { [MacMakeoverHotCornersNative]::HideSeelenPopupsOutside($point.X, $point.Y) } catch { }
      } else {
        try { [MacMakeoverHotCornersNative]::HideSeelenTooltips() } catch { }
      }
    }

    if ($leftMousePressed -and (Test-AppleMenuClickZone -X $point.X -Y $point.Y -Bounds $bounds -Config $config)) {
      $appleMenuCooldownElapsed = ($now - $lastAppleMenuClick).TotalMilliseconds -ge [int]$config.appleMenuClickCooldownMilliseconds
      if ($appleMenuCooldownElapsed) {
        Write-HotCornerLog $config "TopBar click -> AppleMenu"
        Start-MacMakeoverMenu -Command "apple" -Config $config
        $lastAppleMenuClick = $now
      }
    }

    if ($leftMousePressed -and (Test-NetworkFlyoutClickZone -X $point.X -Y $point.Y -Bounds $bounds -Config $config)) {
      $networkFlyoutCooldownElapsed = ($now - $lastNetworkFlyoutClick).TotalMilliseconds -ge [int]$config.networkFlyoutClickCooldownMilliseconds
      if ($networkFlyoutCooldownElapsed) {
        Write-HotCornerLog $config "TopBar click -> NetworkFlyout"
        Invoke-HotCornerAction -Action "NetworkFlyout" -Config $config
        $lastNetworkFlyoutClick = $now
      }
    }

    if ($leftMousePressed -and (Test-BatteryQuickSettingsClickZone -X $point.X -Y $point.Y -Bounds $bounds -Config $config)) {
      $batteryQuickSettingsCooldownElapsed = ($now - $lastBatteryQuickSettingsClick).TotalMilliseconds -ge [int]$config.batteryQuickSettingsClickCooldownMilliseconds
      if ($batteryQuickSettingsCooldownElapsed) {
        Write-HotCornerLog $config "TopBar click -> QuickSettings"
        Invoke-HotCornerAction -Action "QuickSettings" -Config $config
        $lastBatteryQuickSettingsClick = $now
      }
    }

    if ($leftMousePressed -and (Test-NotificationCenterClickZone -X $point.X -Y $point.Y -Bounds $bounds -Config $config)) {
      $notificationCenterCooldownElapsed = ($now - $lastNotificationCenterClick).TotalMilliseconds -ge [int]$config.notificationCenterClickCooldownMilliseconds
      if ($notificationCenterCooldownElapsed) {
        Write-HotCornerLog $config "TopBar click -> NotificationCenter"
        Close-MacMakeoverMenuHostPanels -Config $config
        Invoke-HotCornerAction -Action "NotificationCenter" -Config $config
        $lastNotificationCenterClick = $now
      }
    }

    if ($leftMousePressed -and (Test-CalendarPopupClickZone -X $point.X -Y $point.Y -Bounds $bounds -Config $config)) {
      $calendarPopupCooldownElapsed = ($now - $lastCalendarPopupClick).TotalMilliseconds -ge [int]$config.calendarPopupClickCooldownMilliseconds
      if ($calendarPopupCooldownElapsed) {
        Write-HotCornerLog $config "TopBar click -> CalendarPopup"
        Close-MacMakeoverMenuHostPanels -Config $config
        $lastCalendarPopupClick = $now
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

  # Every ~2s: evict app windows whose title bar restored itself under the menu bar
  # (the opaque bar would otherwise hide their caption; macOS never allows this).
  $script:NudgeCounter++
  if ($script:NudgeCounter -ge 35) {
    $script:NudgeCounter = 0
    try { [MacMakeoverHotCornersNative]::NudgeWindowsOutOfBar($bounds.Height) } catch { }
  }

  Clear-CompletedMenuInvocations
  Start-Sleep -Milliseconds ([int]$config.pollMilliseconds)
}
