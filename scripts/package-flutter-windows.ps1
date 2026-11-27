# Builds the Windows release bundle and packages a portable ZIP.
#
# Usage (from a Windows developer shell):
#   powershell -File scripts/package-flutter-windows.ps1 [-Version 0.1.1]
#
# Output: dist/flutter-windows/<version>/ai-usage-monitor-flutter-win64.zip
param(
    [string]$Version = "0.1.1"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root "flutter_app")

flutter build windows --release

$bundleDir = "build\windows\x64\runner\Release"
$distDir = "..\dist\flutter-windows\$Version"
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$archive = Join-Path $distDir "ai-usage-monitor-flutter-win64-$Version.zip"

Compress-Archive -Path "$bundleDir\*" -DestinationPath $archive -Force
Write-Host "packaged: $archive"