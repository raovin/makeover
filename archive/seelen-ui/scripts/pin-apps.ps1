# Re-pins the user's old Windows taskbar apps into the Seelen UI dock (weg state.yml).
$weg = Join-Path $env:APPDATA 'com.seelen.seelen-ui\data\seelen-weg\state.yml'
if (-not (Test-Path $weg)) { throw "weg state.yml not found at $weg" }
Copy-Item $weg "$weg.bak" -Force

# Old pins resolved to their executables (File Explorer already in dock, so omitted). Ordered sensibly.
$apps = @(
  @{ n = 'Brave';                           p = 'C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe' }
  @{ n = 'Firefox';                         p = 'C:\Program Files\Mozilla Firefox\firefox.exe' }
  @{ n = 'Google Chrome';                   p = 'C:\Program Files\Google\Chrome\Application\chrome.exe' }
  @{ n = 'Cursor';                          p = 'C:\Users\VineethRao\AppData\Local\Programs\cursor\Cursor.exe' }
  @{ n = 'Sublime Text';                    p = 'C:\Program Files\Sublime Text\sublime_text.exe' }
  @{ n = 'JetBrains Rider 2026.1.1';        p = 'C:\Program Files\JetBrains\JetBrains Rider 2026.1.1\bin\rider64.exe' }
  @{ n = 'Visual Studio';                   p = 'C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\devenv.exe' }
  @{ n = 'SQL Server Management Studio 22'; p = 'C:\Program Files\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\SSMS.exe' }
  @{ n = 'Azure Storage Explorer';          p = 'C:\Users\VineethRao\AppData\Local\Programs\Microsoft Azure Storage Explorer\StorageExplorer.exe' }
  @{ n = 'Service Bus Explorer';            p = 'C:\Users\VineethRao\Tools\ServiceBusExplorer\ServiceBusExplorer.exe' }
  @{ n = 'Bruno';                           p = 'C:\Users\VineethRao\AppData\Local\Programs\Bruno\Bruno.exe' }
  @{ n = 'WireGuard';                       p = 'C:\Program Files\WireGuard\wireguard.exe' }
)

$lines = [System.Collections.Generic.List[string]]::new()
Get-Content $weg | ForEach-Object { $lines.Add($_) }

$rightIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^right:') { $rightIdx = $i; break } }
if ($rightIdx -lt 0) { $rightIdx = $lines.Count }  # append if no 'right:' section

$ins = [System.Collections.Generic.List[string]]::new()
$added = @(); $skipped = @()
foreach ($a in $apps) {
  if (Test-Path $a.p) {
    $guid = [guid]::NewGuid().ToString()
    $ins.Add('- type: AppOrFile')
    $ins.Add("  id: $guid")
    $ins.Add("  displayName: $($a.n)")
    $ins.Add('  umid: null')
    $ins.Add("  path: $($a.p)")
    $ins.Add('  pinned: true')
    $ins.Add('  preventPinning: false')
    $ins.Add('  relaunch:')
    $ins.Add("    command: $($a.p)")
    $ins.Add('    args: null')
    $ins.Add('    workingDir: null')
    $ins.Add('    icon: null')
    $added += $a.n
  } else {
    $skipped += "$($a.n) [$($a.p)]"
  }
}

$lines.InsertRange($rightIdx, $ins)
Set-Content -Path $weg -Value $lines -Encoding utf8

"Backed up to: $weg.bak"
"Added ($($added.Count)): $($added -join ', ')"
if ($skipped) { "Skipped - exe not found ($($skipped.Count)): $($skipped -join '; ')" }
