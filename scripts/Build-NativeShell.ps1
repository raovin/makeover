[CmdletBinding()]
param(
  [string]$Configuration = 'Release',
  [string]$Destination = (Join-Path $env:LOCALAPPDATA 'MacMakeover\bin')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$projects = @(
  (Join-Path $repoRoot 'tools\MacMakeover.MenuHost\MacMakeover.MenuHost.csproj'),
  (Join-Path $repoRoot 'tools\MacMakeover.MenuBar\MacMakeover.MenuBar.csproj')
)
$publishRoot = Join-Path $env:TEMP 'MacMakeover\native-shell-publish'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
  throw 'The .NET 10 SDK is required to build the native shell.'
}

Remove-Item -LiteralPath $publishRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $publishRoot, $Destination | Out-Null

foreach ($project in $projects) {
  $name = [System.IO.Path]::GetFileNameWithoutExtension($project)
  $projectOutput = Join-Path $publishRoot $name
  $publishArgs = @(
    'publish', $project,
    '--configuration', $Configuration,
    '--runtime', 'win-x64',
    '--self-contained', 'false',
    '--output', $projectOutput,
    '-p:DebugType=None',
    '-p:DebugSymbols=false'
  )
  & dotnet @publishArgs
  if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed for $name."
  }

  Copy-Item -Path (Join-Path $projectOutput '*') -Destination $Destination -Recurse -Force
}

$required = @(
  'MacMakeover.MenuBar.exe',
  'MacMakeover.MenuHost.exe',
  'Assets\apple-mark.png',
  'Assets\Fonts\Manrope-Regular.ttf',
  'Assets\Fonts\Manrope-SemiBold.ttf',
  'Assets\Fonts\JetBrainsMono-Medium.ttf',
  'Assets\Fonts\OFL-Manrope.txt',
  'Assets\Fonts\OFL-JetBrainsMono.txt'
)
foreach ($item in $required) {
  if (-not (Test-Path -LiteralPath (Join-Path $Destination $item))) {
    throw "Native-shell publish is incomplete: $item"
  }
}

Write-Host "Native shell published to $Destination"
