$ErrorActionPreference = "Stop"

$project = Join-Path $PSScriptRoot "StudyPilot.Windows\StudyPilot.Windows.csproj"
$output = Join-Path $PSScriptRoot "dist\win-x64"

if (Test-Path $output) { Remove-Item $output -Recurse -Force }
dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $output

Write-Host ""
Write-Host "StudyPilot for Windows is ready:" -ForegroundColor Green
Write-Host (Join-Path $output "StudyPilot.exe")
