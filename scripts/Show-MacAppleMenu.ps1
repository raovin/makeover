param(
  [string]$Uri = ""
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

# Single-instance guard: a second Apple-logo click (or a click while the menu is still spinning
# up) must not stack a second window. Held by this STA process for the menu's lifetime; the OS
# releases it when the process exits. Placed AFTER the STA relaunch so the long-lived STA
# process owns the mutex, not the short-lived MTA parent that relaunches and exits.
$createdNew = $false
$script:MenuMutex = New-Object System.Threading.Mutex($true, "Local\MacMakeoverAppleMenu", [ref]$createdNew)
if (-not $createdNew) { exit }

Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase
Add-Type -Namespace MacMakeover -Name NativeWindow -MemberDefinition @"
  [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
  public static extern System.IntPtr GetWindowLongPtr(System.IntPtr hWnd, int nIndex);

  [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
  public static extern System.IntPtr SetWindowLongPtr(System.IntPtr hWnd, int nIndex, System.IntPtr dwNewLong);

  [System.Runtime.InteropServices.DllImport("user32.dll")]
  public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);

  [System.Runtime.InteropServices.DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(System.IntPtr hWnd);

  [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
  public struct POINT {
    public int X;
    public int Y;
  }

  [System.Runtime.InteropServices.DllImport("user32.dll")]
  public static extern bool GetCursorPos(out POINT lpPoint);

  [System.Runtime.InteropServices.DllImport("user32.dll")]
  public static extern short GetAsyncKeyState(int vKey);
"@

$ErrorActionPreference = "Stop"

function Conv([string]$hex) { return [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex) }

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

$currentUser = [Environment]::UserName
if ($currentUser -ieq "VineethRao") {
  $currentUser = "Vineeth Rao"
}

$script:Window = New-Object System.Windows.Window
$script:Window.Title = "Apple Menu"
$script:Window.Width = 244
$script:Window.SizeToContent = [System.Windows.SizeToContent]::Height
$script:Window.Left = 6
$script:Window.Top = 30
$script:Window.WindowStyle = [System.Windows.WindowStyle]::None
$script:Window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$script:Window.AllowsTransparency = $true
$script:Window.Background = [System.Windows.Media.Brushes]::Transparent
$script:Window.Topmost = $true
$script:Window.ShowInTaskbar = $false
$script:Window.Focusable = $true
$script:Window.ShowActivated = $false
$script:Window.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
$script:Window.UseLayoutRounding = $true
[System.Windows.Media.TextOptions]::SetTextFormattingMode($script:Window, [System.Windows.Media.TextFormattingMode]::Ideal)

# Frosted-glass gradient panel
$bgBrush = New-Object System.Windows.Media.LinearGradientBrush
$bgBrush.StartPoint = New-Object System.Windows.Point(0, 0)
$bgBrush.EndPoint = New-Object System.Windows.Point(0, 1)
$bgBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString("#EC2A2C34")), 0.0)) | Out-Null
$bgBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString("#EE181920")), 1.0)) | Out-Null

$windowBorder = New-Object System.Windows.Controls.Border
$windowBorder.CornerRadius = New-Object System.Windows.CornerRadius(9)
$windowBorder.BorderThickness = New-Object System.Windows.Thickness(1)
$windowBorder.BorderBrush = (Conv "#2BFFFFFF")
$windowBorder.Background = $bgBrush
$windowBorder.Padding = New-Object System.Windows.Thickness(6, 6, 6, 6)
$windowBorder.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
  Color = [System.Windows.Media.ColorConverter]::ConvertFromString("#000000")
  BlurRadius = 20
  ShadowDepth = 6
  Opacity = 0.5
}

$stack = New-Object System.Windows.Controls.StackPanel
$stack.Orientation = [System.Windows.Controls.Orientation]::Vertical
$windowBorder.Child = $stack
$script:Window.Content = $windowBorder

$textBrush = (Conv "#F3F5F8")
$mutedBrush = (Conv "#9AA3AF")
$hoverBrush = (Conv "#FF2C6BED")
$transparentBrush = [System.Windows.Media.Brushes]::Transparent

function Invoke-AppleMenuAction {
  param([string]$Action)

  try {
    switch ($Action) {
      "about" { Start-Uri "ms-settings:about" }
      "settings" { Start-Uri "ms-settings:" }
      "store" { Start-Uri "ms-windows-store:" }
      "recent" { Start-Tool "$env:SystemRoot\explorer.exe" @("shell:recent") }
      "force-quit" { Start-Tool "$env:SystemRoot\System32\Taskmgr.exe" }
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
      "lock" { Start-Tool "$env:SystemRoot\System32\rundll32.exe" @("user32.dll,LockWorkStation") }
      "logout" {
        if (Confirm-Action "Log Out" "Log out $currentUser now?") {
          Start-Tool "$env:SystemRoot\System32\shutdown.exe" @("/l")
        }
      }
    }
  } catch {
    [System.Windows.MessageBox]::Show(
      $_.Exception.Message,
      "Apple Menu",
      [System.Windows.MessageBoxButton]::OK,
      [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
  } finally {
    $script:Window.Close()
  }
}

function Add-Separator {
  $separator = New-Object System.Windows.Controls.Border
  $separator.Height = 1
  $separator.Margin = New-Object System.Windows.Thickness(9, 5, 9, 5)
  $separator.Background = (Conv "#1CFFFFFF")
  $stack.Children.Add($separator) | Out-Null
}

function Add-MenuItem {
  param(
    [string]$Label,
    [string]$Action,
    [string]$Shortcut = ""
  )

  $row = New-Object System.Windows.Controls.Border
  $row.Height = 26
  $row.CornerRadius = New-Object System.Windows.CornerRadius(5)
  $row.Background = $transparentBrush
  $row.Cursor = [System.Windows.Input.Cursors]::Arrow
  $row.Tag = $Action

  $grid = New-Object System.Windows.Controls.Grid
  $grid.Margin = New-Object System.Windows.Thickness(10, 0, 9, 0)

  $leftColumn = New-Object System.Windows.Controls.ColumnDefinition
  $leftColumn.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
  $rightColumn = New-Object System.Windows.Controls.ColumnDefinition
  $rightColumn.Width = [System.Windows.GridLength]::Auto
  $grid.ColumnDefinitions.Add($leftColumn)
  $grid.ColumnDefinitions.Add($rightColumn)

  $labelBlock = New-Object System.Windows.Controls.TextBlock
  $labelBlock.Text = $Label
  $labelBlock.Foreground = $textBrush
  $labelBlock.FontSize = 13
  $labelBlock.FontWeight = [System.Windows.FontWeights]::Normal
  $labelBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
  [System.Windows.Controls.Grid]::SetColumn($labelBlock, 0)
  $grid.Children.Add($labelBlock) | Out-Null

  if ($Shortcut.Trim().Length -gt 0) {
    $shortcutBlock = New-Object System.Windows.Controls.TextBlock
    $shortcutBlock.Text = $Shortcut
    $shortcutBlock.Foreground = $mutedBrush
    $shortcutBlock.FontSize = 12
    $shortcutBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($shortcutBlock, 1)
    $grid.Children.Add($shortcutBlock) | Out-Null
  }

  $row.Child = $grid
  $row.Add_MouseEnter({ param($sender, $eventArgs) $sender.Background = $hoverBrush })
  $row.Add_MouseLeave({ param($sender, $eventArgs) $sender.Background = $transparentBrush })
  $row.Add_MouseLeftButtonUp({ param($sender, $eventArgs) Invoke-AppleMenuAction $sender.Tag })

  $stack.Children.Add($row) | Out-Null
}

Add-MenuItem "About This Mac" "about"
Add-Separator
Add-MenuItem "System Settings..." "settings"
Add-MenuItem "App Store" "store"
Add-Separator
Add-MenuItem "Recent Items" "recent" ">"
Add-Separator
Add-MenuItem "Force Quit..." "force-quit" "Ctrl+Shift+Esc"
Add-Separator
Add-MenuItem "Sleep" "sleep"
Add-MenuItem "Restart..." "restart"
Add-MenuItem "Shut Down..." "shutdown"
Add-Separator
Add-MenuItem "Lock Screen" "lock"
Add-MenuItem "Log Out $currentUser..." "logout"

$script:Window.Add_Deactivated({ $script:Window.Close() })
$script:Window.Add_SourceInitialized({
  $helper = New-Object System.Windows.Interop.WindowInteropHelper($script:Window)
  $GWL_EXSTYLE = -20
  $WS_EX_NOACTIVATE = 0x08000000
  $WS_EX_TOOLWINDOW = 0x00000080
  $style = [MacMakeover.NativeWindow]::GetWindowLongPtr($helper.Handle, $GWL_EXSTYLE).ToInt64()
  $newStyle = [IntPtr]($style -bor $WS_EX_NOACTIVATE -bor $WS_EX_TOOLWINDOW)
  [MacMakeover.NativeWindow]::SetWindowLongPtr($helper.Handle, $GWL_EXSTYLE, $newStyle) | Out-Null
  [MacMakeover.NativeWindow]::ShowWindow($helper.Handle, 8) | Out-Null
})
$script:OpenedAt = Get-Date
$script:WasLeftMouseDown = $false
$script:OutsideClickTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:OutsideClickTimer.Interval = [TimeSpan]::FromMilliseconds(45)
$script:OutsideClickTimer.Add_Tick({
  $mouseState = [int][MacMakeover.NativeWindow]::GetAsyncKeyState(0x01)
  $leftMouseDown = ($mouseState -band 0x8000) -ne 0
  $leftMousePressed = (($mouseState -band 0x0001) -ne 0) -or ($leftMouseDown -and -not $script:WasLeftMouseDown)
  $script:WasLeftMouseDown = $leftMouseDown

  if (-not $leftMousePressed -or ((Get-Date) - $script:OpenedAt).TotalMilliseconds -lt 250) {
    return
  }

  $point = New-Object MacMakeover.NativeWindow+POINT
  [MacMakeover.NativeWindow]::GetCursorPos([ref]$point) | Out-Null

  $left = [double]$script:Window.Left
  $top = [double]$script:Window.Top
  $right = $left + [double]$script:Window.ActualWidth
  $bottom = $top + [double]$script:Window.ActualHeight
  $insideWindow = $point.X -ge $left -and $point.X -le $right -and $point.Y -ge $top -and $point.Y -le $bottom

  if (-not $insideWindow) {
    $script:Window.Close()
  }
})
$script:Window.Add_Closed({
  if ($script:OutsideClickTimer) {
    $script:OutsideClickTimer.Stop()
  }
  if ($script:MenuMutex) {
    $script:MenuMutex.ReleaseMutex()
    $script:MenuMutex.Dispose()
  }
})
$script:Window.Add_KeyDown({
  param($sender, $eventArgs)
  if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
    $script:Window.Close()
  }
})

$script:OutsideClickTimer.Start()
$script:Window.ShowDialog() | Out-Null
