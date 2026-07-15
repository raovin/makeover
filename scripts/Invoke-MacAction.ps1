[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateSet("Spotlight", "TaskView", "ShowDesktop", "Lock", "Sleep", "ClipboardHistory", "NotificationCenter", "OpenMakeoverFolder", "VisualQa", "Backup")]
  [string]$Action
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot

$signature = @"
using System;
using System.Runtime.InteropServices;

public static class MacMakeoverKeys {
  [DllImport("user32.dll")]
  public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, UIntPtr dwExtraInfo);
}
"@
Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue

function Send-Hotkey {
  param([byte[]]$Keys)

  foreach ($key in $Keys) {
    [MacMakeoverKeys]::keybd_event($key, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 25
  }

  for ($i = $Keys.Length - 1; $i -ge 0; $i--) {
    [MacMakeoverKeys]::keybd_event($Keys[$i], 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 20
  }
}

switch ($Action) {
  "Spotlight" {
    Send-Hotkey ([byte[]](0x12, 0x20)) # Alt+Space
  }
  "TaskView" {
    Send-Hotkey ([byte[]](0x5B, 0x09)) # Win+Tab
  }
  "ShowDesktop" {
    Send-Hotkey ([byte[]](0x5B, 0x44)) # Win+D
  }
  "Lock" {
    Start-Process -FilePath "$env:windir\System32\rundll32.exe" -ArgumentList "user32.dll,LockWorkStation"
  }
  "Sleep" {
    Start-Process -FilePath "$env:windir\System32\rundll32.exe" -ArgumentList "powrprof.dll,SetSuspendState 0,1,0"
  }
  "ClipboardHistory" {
    Send-Hotkey ([byte[]](0x5B, 0x56)) # Win+V
  }
  "NotificationCenter" {
    Start-Process "ms-actioncenter:"
  }
  "OpenMakeoverFolder" {
    Start-Process -FilePath "$env:windir\explorer.exe" -ArgumentList "`"$PackageRoot`""
  }
  "VisualQa" {
    & (Join-Path $PSScriptRoot "verify.ps1") -CaptureScreenshot
  }
  "Backup" {
    & (Join-Path $PSScriptRoot "backup-current.ps1")
  }
}
