$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$outputPath = Join-Path $projectRoot 'dist\win-x64'

dotnet publish (Join-Path $projectRoot 'AwakeAndAvailable.csproj') `
    --configuration Release `
    --runtime win-x64 `
    --self-contained false `
    -p:PublishSingleFile=true `
    --output $outputPath

Write-Host "Built: $(Join-Path $outputPath 'AwakeAndAvailable.exe')"
