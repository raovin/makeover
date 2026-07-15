[CmdletBinding(DefaultParameterSetName = 'Enable')]
param(
  [Parameter(ParameterSetName = 'Enable')]
  [switch]$Enable,

  [Parameter(ParameterSetName = 'Disable')]
  [switch]$Disable,

  [switch]$ForceDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot 'config\windhawk\native-dock.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable
$windhawkRoot = Join-Path $env:ProgramData 'Windhawk'
$modSourceRoot = Join-Path $windhawkRoot 'ModsSource'
$modBinaryRoot = Join-Path $windhawkRoot 'Engine\Mods\64'
$modId = $config.modId
$targetDllName = '{0}_{1}_macmakeover.dll' -f $modId, $config.version
$targetDll = Join-Path $modBinaryRoot $targetDllName
$targetSource = Join-Path $modSourceRoot "$modId.wh.cpp"
$modRegistry = "HKLM:\Software\Windhawk\Engine\Mods\$modId"
$settingsRegistry = Join-Path $modRegistry 'Settings'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdministrator) {
  throw 'Installing the native dock requires an elevated PowerShell window.'
}
if (-not (Test-Path -LiteralPath $windhawkRoot)) {
  throw 'Windhawk is not installed.'
}

if ($Disable) {
  if (Test-Path -LiteralPath $modRegistry) {
    New-ItemProperty -LiteralPath $modRegistry -Name Disabled -Value 1 -PropertyType DWord -Force | Out-Null
    $changeTime = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    New-ItemProperty -LiteralPath $modRegistry -Name SettingsChangeTime -Value $changeTime -PropertyType DWord -Force | Out-Null
  }
  Write-Host 'Native dock styling disabled.'
  return
}

New-Item -ItemType Directory -Force -Path $modSourceRoot, $modBinaryRoot | Out-Null

$tempRoot = Join-Path $env:TEMP 'MacMakeover\windhawk'
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$tempDll = Join-Path $tempRoot $targetDllName
$tempSource = Join-Path $tempRoot "$modId.wh.cpp"

if ($ForceDownload -or -not (Test-Path -LiteralPath $targetDll)) {
  Invoke-WebRequest -Uri $config.binaryUrl -OutFile $tempDll -UseBasicParsing -TimeoutSec 60
  $actualHash = (Get-FileHash -LiteralPath $tempDll -Algorithm SHA256).Hash
  if ($actualHash -ne $config.binarySha256) {
    throw "Windhawk mod hash mismatch. Expected $($config.binarySha256); got $actualHash."
  }
  if ((Get-Item -LiteralPath $tempDll).Length -lt 100KB) {
    throw 'Downloaded Windhawk mod is unexpectedly small.'
  }
  Copy-Item -LiteralPath $tempDll -Destination $targetDll -Force
}

Invoke-WebRequest -Uri $config.sourceUrl -OutFile $tempSource -UseBasicParsing -TimeoutSec 60
$sourceHeader = (Get-Content -LiteralPath $tempSource -TotalCount 20) -join [Environment]::NewLine
if ($sourceHeader -notmatch [regex]::Escape("@id              $modId") -or
    $sourceHeader -notmatch [regex]::Escape("@version         $($config.version)")) {
  throw 'Downloaded Windhawk source metadata does not match the pinned mod.'
}
Copy-Item -LiteralPath $tempSource -Destination $targetSource -Force

New-Item -ItemType Directory -Force -Path $modRegistry, $settingsRegistry | Out-Null
$modValues = [ordered]@{
  LibraryFileName = $targetDllName
  Disabled = 0
  LoggingEnabled = 0
  DebugLoggingEnabled = 0
  Include = $config.include
  Exclude = ''
  IncludeCustom = ''
  ExcludeCustom = ''
  IncludeExcludeCustomOnly = 0
  PatternsMatchCriticalSystemProcesses = 0
  Architecture = $config.architecture
  Version = $config.version
}
foreach ($entry in $modValues.GetEnumerator()) {
  $type = if ($entry.Value -is [int]) { 'DWord' } else { 'String' }
  New-ItemProperty -LiteralPath $modRegistry -Name $entry.Key -Value $entry.Value -PropertyType $type -Force | Out-Null
}

$settingsKey = Get-Item -LiteralPath $settingsRegistry
foreach ($valueName in $settingsKey.GetValueNames()) {
  Remove-ItemProperty -LiteralPath $settingsRegistry -Name $valueName -Force
}
foreach ($entry in $config.settings.GetEnumerator()) {
  New-ItemProperty -LiteralPath $settingsRegistry -Name $entry.Key -Value ([string]$entry.Value) -PropertyType String -Force | Out-Null
}
$changeTime = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
New-ItemProperty -LiteralPath $modRegistry -Name SettingsChangeTime -Value $changeTime -PropertyType DWord -Force | Out-Null

$profilePath = Join-Path $windhawkRoot 'userprofile.json'
$profile = if (Test-Path -LiteralPath $profilePath) {
  Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json -AsHashtable
} else {
  @{}
}
if (-not $profile.ContainsKey('mods')) {
  $profile.mods = @{}
}
$profile.mods[$modId] = @{ version = $config.version }
$profileJson = $profile | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($profilePath, $profileJson, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Native dock styling installed and enabled: $modId $($config.version)"
