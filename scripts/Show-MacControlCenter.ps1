param(
  [string]$Uri = "",
  [switch]$WarmUp
)

$scriptPath = $PSCommandPath
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
  $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  Start-Process -FilePath $powershell -WindowStyle Hidden -ArgumentList @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-STA",
    "-WindowStyle",
    "Hidden",
    "-File",
    $scriptPath,
    $Uri
  ) | Out-Null
  exit
}

Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase
if (-not ("MacMakeover.ControlCenterNative" -as [type])) {
  Add-Type -Namespace MacMakeover -Name ControlCenterNative -MemberDefinition @"
  [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
  public static extern System.IntPtr GetWindowLongPtr(System.IntPtr hWnd, int nIndex);

  [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
  public static extern System.IntPtr SetWindowLongPtr(System.IntPtr hWnd, int nIndex, System.IntPtr dwNewLong);

  [System.Runtime.InteropServices.DllImport("user32.dll")]
  public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);

  [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
  public struct POINT {
    public int X;
    public int Y;
  }

  [System.Runtime.InteropServices.DllImport("user32.dll")]
  public static extern bool GetCursorPos(out POINT lpPoint);

  [System.Runtime.InteropServices.DllImport("user32.dll")]
  public static extern short GetAsyncKeyState(int vKey);

  public delegate System.IntPtr LowLevelMouseProc(int nCode, System.IntPtr wParam, System.IntPtr lParam);

  [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
  public struct MSLLHOOKSTRUCT {
    public POINT pt;
    public uint mouseData;
    public uint flags;
    public uint time;
    public System.IntPtr dwExtraInfo;
  }

  [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
  public static extern System.IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, System.IntPtr hMod, uint dwThreadId);

  [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
  public static extern bool UnhookWindowsHookEx(System.IntPtr hhk);

  [System.Runtime.InteropServices.DllImport("user32.dll")]
  public static extern System.IntPtr CallNextHookEx(System.IntPtr hhk, int nCode, System.IntPtr wParam, System.IntPtr lParam);
"@
}

$ErrorActionPreference = "Stop"

if ($WarmUp) { return }

$createdNew = $false
$script:MenuMutex = New-Object System.Threading.Mutex($true, "Local\MacMakeoverControlCenter", [ref]$createdNew)
if (-not $createdNew) { exit }

function Brush([string]$hex) {
  return [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex)
}

function Start-Uri {
  param([string]$Target)
  Start-Process -FilePath $Target | Out-Null
}

function Start-Tool {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList = @()
  )

  if ($ArgumentList.Count -gt 0) {
    Start-Process -FilePath $FilePath -ArgumentList $ArgumentList | Out-Null
    return
  }

  Start-Process -FilePath $FilePath | Out-Null
}

function Confirm-Action {
  param(
    [string]$Title,
    [string]$Message
  )

  $result = [System.Windows.MessageBox]::Show(
    $Message,
    $Title,
    [System.Windows.MessageBoxButton]::YesNo,
    [System.Windows.MessageBoxImage]::Warning
  )

  return $result -eq [System.Windows.MessageBoxResult]::Yes
}

function Get-BatterySummary {
  try {
    $batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
    if (-not $batteries.Count) { return "Plugged in" }

    $average = [Math]::Round(($batteries | Measure-Object -Property EstimatedChargeRemaining -Average).Average)
    $charging = $batteries | Where-Object { $_.BatteryStatus -in @(2, 6, 7, 8, 9, 11) } | Select-Object -First 1
    if ($charging) { return "Battery $average% - charging" }
    return "Battery $average%"
  } catch {
    return "Power status"
  }
}

function Invoke-ControlAction {
  param([string]$Action)

  try {
    switch ($Action) {
      "settings" { Start-Uri "ms-settings:" }
      "battery" { Start-Uri "ms-settings:powersleep" }
      "network" { Start-Uri "ms-settings:network-status" }
      "desktop" { (New-Object -ComObject Shell.Application).ToggleDesktop() }
      "lock" { Start-Tool "$env:SystemRoot\System32\rundll32.exe" @("user32.dll,LockWorkStation") }
      "sleep" { Start-Tool "$env:SystemRoot\System32\rundll32.exe" @("powrprof.dll,SetSuspendState", "0,1,0") }
      "restart" {
        if (Confirm-Action "Restart" "Restart this PC now?") {
          Start-Tool "$env:SystemRoot\System32\shutdown.exe" @("/r", "/t", "0")
        }
      }
      "shutdown" {
        if (Confirm-Action "Shut Down" "Shut down this PC now?") {
          Start-Tool "$env:SystemRoot\System32\shutdown.exe" @("/s", "/t", "0")
        }
      }
    }
  } catch {
    [System.Windows.MessageBox]::Show(
      $_.Exception.Message,
      "Control Center",
      [System.Windows.MessageBoxButton]::OK,
      [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
  } finally {
    $script:Window.Close()
  }
}

$script:Window = New-Object System.Windows.Window
$script:Window.Title = "Control Center"
$script:Window.Width = 292
$script:Window.SizeToContent = [System.Windows.SizeToContent]::Height
$workArea = [System.Windows.SystemParameters]::WorkArea
$script:Window.Left = [Math]::Max(8, $workArea.Right - $script:Window.Width - 8)
$script:Window.Top = 30
$script:Window.WindowStyle = [System.Windows.WindowStyle]::None
$script:Window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$script:Window.AllowsTransparency = $true
$script:Window.Background = [System.Windows.Media.Brushes]::Transparent
$script:Window.Topmost = $true
$script:Window.ShowInTaskbar = $false
$script:Window.Focusable = $true
$script:Window.ShowActivated = $true
$script:Window.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
$script:Window.UseLayoutRounding = $true
[System.Windows.Media.TextOptions]::SetTextFormattingMode($script:Window, [System.Windows.Media.TextFormattingMode]::Ideal)

$bgBrush = New-Object System.Windows.Media.LinearGradientBrush
$bgBrush.StartPoint = New-Object System.Windows.Point(0, 0)
$bgBrush.EndPoint = New-Object System.Windows.Point(0, 1)
$bgBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString("#F02B303A")), 0.0)) | Out-Null
$bgBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString("#F01A1D25")), 1.0)) | Out-Null

$panel = New-Object System.Windows.Controls.Border
$panel.CornerRadius = New-Object System.Windows.CornerRadius(12)
$panel.BorderThickness = New-Object System.Windows.Thickness(1)
$panel.BorderBrush = (Brush "#2EFFFFFF")
$panel.Background = $bgBrush
$panel.Padding = New-Object System.Windows.Thickness(10)
$panel.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
  Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#000000")
  BlurRadius = 24
  ShadowDepth = 8
  Opacity = 0.48
}

$stack = New-Object System.Windows.Controls.StackPanel
$stack.Orientation = [System.Windows.Controls.Orientation]::Vertical
$panel.Child = $stack
$script:Window.Content = $panel

$textBrush = (Brush "#F4F7FA")
$mutedBrush = (Brush "#9CA7B4")
$hoverBrush = (Brush "#FF2C6BED")
$cardBrush = (Brush "#18FFFFFF")
$transparentBrush = [System.Windows.Media.Brushes]::Transparent

function Add-Text {
  param(
    [string]$Text,
    [double]$Size,
    [object]$Weight,
    [object]$Foreground
  )

  $block = New-Object System.Windows.Controls.TextBlock
  $block.Text = $Text
  $block.FontSize = $Size
  $block.FontWeight = $Weight
  $block.Foreground = $Foreground
  $block.Margin = New-Object System.Windows.Thickness(2, 0, 2, 0)
  $stack.Children.Add($block) | Out-Null
}

function Add-ActionRow {
  param(
    [string]$Label,
    [string]$Detail,
    [string]$Action
  )

  $row = New-Object System.Windows.Controls.Border
  $row.Height = 42
  $row.CornerRadius = New-Object System.Windows.CornerRadius(8)
  $row.Background = $cardBrush
  $row.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
  $row.Cursor = [System.Windows.Input.Cursors]::Arrow
  $row.Tag = $Action

  $inner = New-Object System.Windows.Controls.StackPanel
  $inner.Margin = New-Object System.Windows.Thickness(12, 5, 12, 5)
  $inner.Orientation = [System.Windows.Controls.Orientation]::Vertical

  $labelBlock = New-Object System.Windows.Controls.TextBlock
  $labelBlock.Text = $Label
  $labelBlock.Foreground = $textBrush
  $labelBlock.FontSize = 13
  $labelBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
  $inner.Children.Add($labelBlock) | Out-Null

  if ($Detail.Trim().Length -gt 0) {
    $detailBlock = New-Object System.Windows.Controls.TextBlock
    $detailBlock.Text = $Detail
    $detailBlock.Foreground = $mutedBrush
    $detailBlock.FontSize = 11
    $inner.Children.Add($detailBlock) | Out-Null
  }

  $row.Child = $inner
  $row.Add_MouseEnter({ param($sender, $eventArgs) $sender.Background = $hoverBrush })
  $row.Add_MouseLeave({ param($sender, $eventArgs) $sender.Background = $cardBrush })
  $row.Add_MouseLeftButtonUp({ param($sender, $eventArgs) Invoke-ControlAction $sender.Tag })
  $stack.Children.Add($row) | Out-Null
}

function Add-CompactAction {
  param(
    [string]$Label,
    [string]$Action
  )

  $row = New-Object System.Windows.Controls.Border
  $row.Height = 30
  $row.CornerRadius = New-Object System.Windows.CornerRadius(7)
  $row.Background = $transparentBrush
  $row.Cursor = [System.Windows.Input.Cursors]::Arrow
  $row.Tag = $Action

  $labelBlock = New-Object System.Windows.Controls.TextBlock
  $labelBlock.Text = $Label
  $labelBlock.Foreground = $textBrush
  $labelBlock.FontSize = 13
  $labelBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
  $labelBlock.Margin = New-Object System.Windows.Thickness(12, 0, 12, 0)
  $row.Child = $labelBlock

  $row.Add_MouseEnter({ param($sender, $eventArgs) $sender.Background = $hoverBrush })
  $row.Add_MouseLeave({ param($sender, $eventArgs) $sender.Background = $transparentBrush })
  $row.Add_MouseLeftButtonUp({ param($sender, $eventArgs) Invoke-ControlAction $sender.Tag })
  $stack.Children.Add($row) | Out-Null
}

Add-Text "Control Center" 15 ([System.Windows.FontWeights]::SemiBold) $textBrush
Add-Text (Get-BatterySummary) 11 ([System.Windows.FontWeights]::Normal) $mutedBrush
Add-ActionRow "Power & Battery Settings" "Open Windows power settings" "battery"
Add-ActionRow "Network Settings" "Open Network & Internet settings" "network"
Add-ActionRow "System Settings" "Open Windows settings" "settings"
Add-CompactAction "Show Desktop" "desktop"
Add-CompactAction "Lock Screen" "lock"
Add-CompactAction "Sleep" "sleep"
Add-CompactAction "Restart..." "restart"
Add-CompactAction "Shut Down..." "shutdown"

function Test-PointInsideWindow {
  param(
    [int]$X,
    [int]$Y
  )

  $left = [double]$script:Window.Left
  $top = [double]$script:Window.Top
  $right = $left + [double]$script:Window.ActualWidth
  $bottom = $top + [double]$script:Window.ActualHeight

  return $X -ge $left -and $X -le $right -and $Y -ge $top -and $Y -le $bottom
}

$script:OpenedAt = Get-Date
$script:IgnoreMouseUntil = $script:OpenedAt.AddMilliseconds(250)
$initialMouseState = [int][MacMakeover.ControlCenterNative]::GetAsyncKeyState(0x01)
$script:WasLeftMouseDown = ($initialMouseState -band 0x8000) -ne 0
$script:OutsideClickTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:OutsideClickTimer.Interval = [TimeSpan]::FromMilliseconds(20)
$script:OutsideClickTimer.Add_Tick({
  $mouseState = [int][MacMakeover.ControlCenterNative]::GetAsyncKeyState(0x01)
  $leftMouseDown = ($mouseState -band 0x8000) -ne 0
  $leftMousePressed = (($mouseState -band 0x0001) -ne 0) -or ($leftMouseDown -and -not $script:WasLeftMouseDown)
  $script:WasLeftMouseDown = $leftMouseDown

  if (-not $leftMousePressed -or (Get-Date) -lt $script:IgnoreMouseUntil) {
    return
  }

  $point = New-Object MacMakeover.ControlCenterNative+POINT
  [MacMakeover.ControlCenterNative]::GetCursorPos([ref]$point) | Out-Null

  if (-not (Test-PointInsideWindow $point.X $point.Y)) {
    $script:Window.Close()
  }
})

$script:MouseHook = [IntPtr]::Zero
$script:MouseHookCallback = [MacMakeover.ControlCenterNative+LowLevelMouseProc]{
  param([int]$nCode, [IntPtr]$wParam, [IntPtr]$lParam)

  try {
    $WM_LBUTTONDOWN = 0x0201
    if ($nCode -ge 0 -and $wParam.ToInt32() -eq $WM_LBUTTONDOWN -and (Get-Date) -ge $script:IgnoreMouseUntil) {
      $mouseInfo = [System.Runtime.InteropServices.Marshal]::PtrToStructure($lParam, [type][MacMakeover.ControlCenterNative+MSLLHOOKSTRUCT])
      if (-not (Test-PointInsideWindow $mouseInfo.pt.X $mouseInfo.pt.Y)) {
        $script:Window.Dispatcher.BeginInvoke([Action]{ $script:Window.Close() }) | Out-Null
      }
    }
  } catch {
    # Keep the hook non-fatal; the polling timer remains as a fallback.
  }

  return [MacMakeover.ControlCenterNative]::CallNextHookEx($script:MouseHook, $nCode, $wParam, $lParam)
}
$script:MouseHook = [MacMakeover.ControlCenterNative]::SetWindowsHookEx(14, $script:MouseHookCallback, [IntPtr]::Zero, 0)

$script:Window.Add_SourceInitialized({
  $helper = New-Object System.Windows.Interop.WindowInteropHelper($script:Window)
  $GWL_EXSTYLE = -20
  $WS_EX_TOOLWINDOW = 0x00000080
  $style = [MacMakeover.ControlCenterNative]::GetWindowLongPtr($helper.Handle, $GWL_EXSTYLE).ToInt64()
  $newStyle = [IntPtr]($style -bor $WS_EX_TOOLWINDOW)
  [MacMakeover.ControlCenterNative]::SetWindowLongPtr($helper.Handle, $GWL_EXSTYLE, $newStyle) | Out-Null
  [MacMakeover.ControlCenterNative]::ShowWindow($helper.Handle, 5) | Out-Null
})
$script:Window.Add_Deactivated({ $script:Window.Close() })
$script:Window.Add_Closed({
  if ($script:OutsideClickTimer) {
    $script:OutsideClickTimer.Stop()
  }
  if ($script:MouseHook -and $script:MouseHook -ne [IntPtr]::Zero) {
    [MacMakeover.ControlCenterNative]::UnhookWindowsHookEx($script:MouseHook) | Out-Null
    $script:MouseHook = [IntPtr]::Zero
  }
  if ($script:MenuMutex) {
    $script:MenuMutex.ReleaseMutex()
    $script:MenuMutex.Dispose()
  }
  [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvokeShutdown([System.Windows.Threading.DispatcherPriority]::Background)
})
$script:Window.Add_KeyDown({
  param($sender, $eventArgs)
  if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
    $script:Window.Close()
  }
})

$script:OutsideClickTimer.Start()
$script:Window.Show()
$script:Window.Activate() | Out-Null
[System.Windows.Threading.Dispatcher]::Run()
