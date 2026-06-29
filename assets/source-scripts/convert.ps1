Add-Type -AssemblyName System.Drawing
$src = Join-Path $env:USERPROFILE 'Pictures\mac-makeover\mac-wallpaper.jpg'
$dst = Join-Path $env:USERPROFILE 'Pictures\mac-makeover\mac-wallpaper.png'
$img = [System.Drawing.Image]::FromFile($src)
$img.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose()
Write-Output ("PNG created: {0} ({1} KB)" -f $dst, [math]::Round((Get-Item $dst).Length / 1KB))
