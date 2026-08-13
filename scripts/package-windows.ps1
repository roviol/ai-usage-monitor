[CmdletBinding()]
param(
    [string]$BuildDirectory = "build/windows-release",
    [string]$OutputDirectory = "dist"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = [IO.Path]::GetFullPath((Join-Path $root $BuildDirectory))
$output = [IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
$executable = Join-Path $build "ai-usage-monitor.exe"
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Release executable not found: $executable"
}

$stage = Join-Path $output "AIUsageMonitor-0.1.1-Windows-x64"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath $executable -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $root "README.md") -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $root "LICENSE") -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $root "THIRD_PARTY_NOTICES.md") -Destination $stage -Force
& (Join-Path $root "scripts\test-application-icon.ps1") -Root $root -Executable (Join-Path $stage "ai-usage-monitor.exe")
$stageScreenshots = Join-Path $stage "docs\screenshots"
New-Item -ItemType Directory -Force -Path $stageScreenshots | Out-Null
Copy-Item -LiteralPath (Join-Path $root "docs\screenshots\dashboard-modern-light.png") -Destination $stageScreenshots -Force
Copy-Item -LiteralPath (Join-Path $root "docs\screenshots\dashboard-modern-dark.png") -Destination $stageScreenshots -Force
Copy-Item -LiteralPath (Join-Path $root "docs\screenshots\settings-modern-compact.png") -Destination $stageScreenshots -Force
Copy-Item -LiteralPath (Join-Path $root "docs\screenshots\overlay-minimal-light.png") -Destination $stageScreenshots -Force
Copy-Item -LiteralPath (Join-Path $root "docs\screenshots\overlay-minimal-dark.png") -Destination $stageScreenshots -Force
Copy-Item -LiteralPath (Join-Path $root "docs\screenshots\overlay-minimal-low-opacity.png") -Destination $stageScreenshots -Force

$zip = "$stage.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
$packageFiles = @(
    (Join-Path $stage "ai-usage-monitor.exe"),
    (Join-Path $stage "README.md"),
    (Join-Path $stage "LICENSE"),
    (Join-Path $stage "THIRD_PARTY_NOTICES.md"),
    (Join-Path $stage "docs")
)
Compress-Archive -LiteralPath $packageFiles -DestinationPath $zip -CompressionLevel Optimal
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $zip
Set-Content -LiteralPath "$zip.sha256" -Encoding ascii -NoNewline -Value "$($hash.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($zip))`n"

$size = (Get-Item -LiteralPath $executable).Length
if ($size -gt 15MB) { throw "Executable exceeds the 15 MiB release budget: $size bytes" }
Get-Item -LiteralPath $executable, $zip, "$zip.sha256" | Select-Object FullName, Length
