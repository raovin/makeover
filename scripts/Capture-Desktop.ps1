[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MacMakeover {
  public static class DpiCapture {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
  }
}
'@
[void][MacMakeover.DpiCapture]::SetProcessDpiAwarenessContext([IntPtr](-4))
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$target = [IO.Path]::GetFullPath($Path)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
$bounds = [Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
  $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
  $bitmap.Save($target, [Drawing.Imaging.ImageFormat]::Png)
} finally {
  $graphics.Dispose()
  $bitmap.Dispose()
}
Write-Host $target
