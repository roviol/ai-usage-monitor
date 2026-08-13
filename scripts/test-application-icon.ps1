[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$Executable = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Assert-IconCondition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Test-RgbaPng([string]$Path, [int]$ExpectedSize) {
    Assert-IconCondition (Test-Path -LiteralPath $Path -PathType Leaf) "Missing PNG asset: $Path"
    $bitmap = [System.Drawing.Bitmap]::new($Path)
    try {
        Assert-IconCondition ($bitmap.RawFormat.Guid -eq [System.Drawing.Imaging.ImageFormat]::Png.Guid) "$Path is not PNG."
        Assert-IconCondition ($bitmap.Width -eq $ExpectedSize -and $bitmap.Height -eq $ExpectedSize) "$Path must be ${ExpectedSize}x${ExpectedSize}."
        $corners = @(
            $bitmap.GetPixel(0, 0).A,
            $bitmap.GetPixel($bitmap.Width - 1, 0).A,
            $bitmap.GetPixel(0, $bitmap.Height - 1).A,
            $bitmap.GetPixel($bitmap.Width - 1, $bitmap.Height - 1).A
        )
        Assert-IconCondition (($corners | Where-Object { $_ -ne 0 }).Count -eq 0) "$Path must have transparent corners."
    }
    finally {
        $bitmap.Dispose()
    }
}

function Get-IcoSizes([string]$Path) {
    Assert-IconCondition (Test-Path -LiteralPath $Path -PathType Leaf) "Missing ICO asset: $Path"
    $bytes = [IO.File]::ReadAllBytes($Path)
    Assert-IconCondition ($bytes.Length -ge 6) "$Path has an incomplete ICO header."
    Assert-IconCondition ([BitConverter]::ToUInt16($bytes, 0) -eq 0) "$Path has an invalid ICO reserved field."
    Assert-IconCondition ([BitConverter]::ToUInt16($bytes, 2) -eq 1) "$Path is not an ICO file."
    $count = [BitConverter]::ToUInt16($bytes, 4)
    Assert-IconCondition ($bytes.Length -ge 6 + (16 * $count)) "$Path has an incomplete ICO directory."
    $sizes = @()
    for ($index = 0; $index -lt $count; $index++) {
        $offset = 6 + (16 * $index)
        $width = if ($bytes[$offset] -eq 0) { 256 } else { [int]$bytes[$offset] }
        $height = if ($bytes[$offset + 1] -eq 0) { 256 } else { [int]$bytes[$offset + 1] }
        Assert-IconCondition ($width -eq $height) "$Path contains a non-square ${width}x${height} entry."
        $sizes += $width
    }
    return $sizes | Sort-Object -Unique
}

$master = Join-Path $Root 'assets\application-icon-1024.png'
$windowsIcon = Join-Path $Root 'assets\application-icon.ico'
$linuxIcon = Join-Path $Root 'packaging\linux\ai-usage-monitor.png'
Test-RgbaPng $master 1024
Test-RgbaPng $linuxIcon 512

$actualSizes = @(Get-IcoSizes $windowsIcon)
$requiredSizes = @(16, 24, 32, 48, 64, 128, 256)
foreach ($size in $requiredSizes) {
    Assert-IconCondition ($actualSizes -contains $size) "Windows ICO is missing the ${size}px entry."
}

if ($Executable) {
    $resolvedExecutable = (Resolve-Path -LiteralPath $Executable).Path
    if (-not ('ApplicationIconNative' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class ApplicationIconNative {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
  [DllImport("kernel32.dll")]
  public static extern bool FreeLibrary(IntPtr module);
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern IntPtr LoadImage(IntPtr instance, IntPtr name, uint type, int width, int height, uint flags);
  [DllImport("user32.dll")]
  public static extern bool DestroyIcon(IntPtr icon);
}
'@
    }
    $module = [ApplicationIconNative]::LoadLibraryEx($resolvedExecutable, [IntPtr]::Zero, 0x2)
    Assert-IconCondition ($module -ne [IntPtr]::Zero) "Could not inspect executable resources: $resolvedExecutable"
    try {
        foreach ($size in $requiredSizes) {
            $handle = [ApplicationIconNative]::LoadImage($module, [IntPtr]101, 1, $size, $size, 0)
            Assert-IconCondition ($handle -ne [IntPtr]::Zero) "Executable icon resource 101 could not supply ${size}px."
            [ApplicationIconNative]::DestroyIcon($handle) | Out-Null
        }
    }
    finally {
        [ApplicationIconNative]::FreeLibrary($module) | Out-Null
    }
}

Write-Output "Application icon validation passed: RGBA masters and ICO sizes $($actualSizes -join ', ')."
