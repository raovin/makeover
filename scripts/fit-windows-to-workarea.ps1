[CmdletBinding(SupportsShouldProcess)]
param(
  [int]$Tolerance = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

$signature = @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class MacMakeoverWorkAreaRepair {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct POINT {
    public int X;
    public int Y;
  }

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxLength);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxLength);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool IsIconic(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

  [DllImport("user32.dll")]
  public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);

  [DllImport("user32.dll")]
  public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern int GetWindowLong(IntPtr hWnd, int index);
}
"@
Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue

$candidates = New-Object System.Collections.Generic.List[object]

[MacMakeoverWorkAreaRepair]::EnumWindows({
  param($hWnd, $lParam)

  if (-not [MacMakeoverWorkAreaRepair]::IsWindowVisible($hWnd)) { return $true }
  if ([MacMakeoverWorkAreaRepair]::IsIconic($hWnd)) { return $true }

  $titleBuilder = New-Object System.Text.StringBuilder 256
  $classBuilder = New-Object System.Text.StringBuilder 256
  [MacMakeoverWorkAreaRepair]::GetWindowText($hWnd, $titleBuilder, 256) | Out-Null
  [MacMakeoverWorkAreaRepair]::GetClassName($hWnd, $classBuilder, 256) | Out-Null
  $title = $titleBuilder.ToString()
  $className = $classBuilder.ToString()

  if ([string]::IsNullOrWhiteSpace($title)) { return $true }
  if ($title -match '^(Dock/Taskbar|Fancy Toolbar|Flyouts|Apple Menu|Control Center|Network|Bluetooth|Tooltip|Windows Input Experience)$') { return $true }
  if ($className -in @("Shell_TrayWnd", "Progman", "WorkerW", "Tauri Window")) { return $true }

  $exStyle = [MacMakeoverWorkAreaRepair]::GetWindowLong($hWnd, -20)
  if (($exStyle -band 0x00000080) -ne 0) { return $true } # WS_EX_TOOLWINDOW

  $windowRect = New-Object MacMakeoverWorkAreaRepair+RECT
  $clientRect = New-Object MacMakeoverWorkAreaRepair+RECT
  [MacMakeoverWorkAreaRepair]::GetWindowRect($hWnd, [ref]$windowRect) | Out-Null
  [MacMakeoverWorkAreaRepair]::GetClientRect($hWnd, [ref]$clientRect) | Out-Null
  $clientOrigin = New-Object MacMakeoverWorkAreaRepair+POINT
  [MacMakeoverWorkAreaRepair]::ClientToScreen($hWnd, [ref]$clientOrigin) | Out-Null

  $windowWidth = $windowRect.Right - $windowRect.Left
  $clientBottom = $clientOrigin.Y + ($clientRect.Bottom - $clientRect.Top)
  $screen = [System.Windows.Forms.Screen]::FromHandle($hWnd)
  $fullWidthish = $windowWidth -ge [int]($screen.Bounds.Width * 0.9)
  $overlapsDockWorkArea = $clientBottom -gt ($screen.WorkingArea.Bottom + $Tolerance)

  if ($fullWidthish -and $overlapsDockWorkArea) {
    $candidates.Add([pscustomobject]@{
      Handle = $hWnd
      Title = $title
      Monitor = $screen.DeviceName
      Window = "$($windowRect.Left),$($windowRect.Top),$($windowRect.Right),$($windowRect.Bottom)"
      ClientBottom = $clientBottom
      WorkAreaBottom = $screen.WorkingArea.Bottom
    })
  }

  return $true
}, [IntPtr]::Zero) | Out-Null

foreach ($candidate in $candidates) {
  if ($PSCmdlet.ShouldProcess($candidate.Title, "restore/maximize to current work area")) {
    [MacMakeoverWorkAreaRepair]::ShowWindow($candidate.Handle, 9) | Out-Null  # SW_RESTORE
    Start-Sleep -Milliseconds 180
    [MacMakeoverWorkAreaRepair]::ShowWindow($candidate.Handle, 3) | Out-Null  # SW_MAXIMIZE
  }
}

$candidates |
  Select-Object Title,Monitor,Window,ClientBottom,WorkAreaBottom |
  Format-Table -AutoSize
