# Legacy experiment: generates a macOS-style gradient in Pictures and applies it.
# Production uses assets/wallpapers/mac-wallpaper.jpg (the archived Big Sur image).
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$w = [int]$bounds.Width
$h = [int]$bounds.Height
if ($w -lt 800) { $w = 1920 }
if ($h -lt 600) { $h = 1080 }

$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h

# Base diagonal gradient: deep indigo -> near black
$c1 = [System.Drawing.Color]::FromArgb(24, 20, 52)
$c2 = [System.Drawing.Color]::FromArgb(7, 7, 12)
$lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 55)
$g.FillRectangle($lg, $rect)

# Soft radial glow (upper area), like the macOS light-bloom wallpapers
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$radius = [int]([Math]::Min($w, $h) * 0.95)
$cx = [int]($w * 0.32)
$cy = [int]($h * 0.26)
$path.AddEllipse(($cx - $radius), ($cy - $radius), ($radius * 2), ($radius * 2))
$pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
$pgb.CenterColor = [System.Drawing.Color]::FromArgb(130, 86, 96, 210)
$pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 24, 20, 52))
$pgb.CenterPoint = New-Object System.Drawing.PointF($cx, $cy)
$g.FillRectangle($pgb, $rect)

# Second subtle warm glow lower-right for depth
$path2 = New-Object System.Drawing.Drawing2D.GraphicsPath
$radius2 = [int]([Math]::Min($w, $h) * 0.7)
$cx2 = [int]($w * 0.82)
$cy2 = [int]($h * 0.85)
$path2.AddEllipse(($cx2 - $radius2), ($cy2 - $radius2), ($radius2 * 2), ($radius2 * 2))
$pgb2 = New-Object System.Drawing.Drawing2D.PathGradientBrush($path2)
$pgb2.CenterColor = [System.Drawing.Color]::FromArgb(70, 150, 70, 130)
$pgb2.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 7, 7, 12))
$pgb2.CenterPoint = New-Object System.Drawing.PointF($cx2, $cy2)
$g.FillRectangle($pgb2, $rect)

$g.Dispose()

$dir = Join-Path $env:USERPROFILE 'Pictures\mac-makeover'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir 'mac-wallpaper.jpg'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$bmp.Dispose()

# Apply: fill style
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'

$sig = @'
using System.Runtime.InteropServices;
public class WallpaperSetter {
  [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
  public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
Add-Type -TypeDefinition $sig
# SPI_SETDESKWALLPAPER = 0x0014 (20); flags = SPIF_UPDATEINIFILE(1) | SPIF_SENDCHANGE(2)
[WallpaperSetter]::SystemParametersInfo(20, 0, $out, 3) | Out-Null

Write-Output "OK Wallpaper generated and applied: $out  (${w}x${h})"
