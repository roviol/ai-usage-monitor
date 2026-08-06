param(
  [string]$Executable = (Join-Path $PSScriptRoot '..\build\windows-release\ai-usage-monitor.exe'),
  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\docs\screenshots')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class OverlayCaptureNative {
  public delegate bool EnumProc(IntPtr window, IntPtr state);
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr state);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int length);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
  public static IntPtr Find(uint processId) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((window, state) => {
      uint owner;
      GetWindowThreadProcessId(window, out owner);
      if (owner != processId) return true;
      var text = new StringBuilder(512);
      GetWindowText(window, text, text.Capacity);
      if (text.ToString().StartsWith("AI Usage Overlay")) { found = window; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@

$resolvedExecutable = (Resolve-Path $Executable).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$cases = @(
  @{ Name = 'overlay-minimal-light.png'; Theme = 'light'; Opacity = 100 },
  @{ Name = 'overlay-minimal-dark.png'; Theme = 'dark'; Opacity = 100 },
  @{ Name = 'overlay-minimal-low-opacity.png'; Theme = 'dark'; Opacity = 50 }
)

foreach ($case in $cases) {
  $data = Join-Path ([IO.Path]::GetTempPath()) ('ai-usage-overlay-capture-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $data | Out-Null
  $settings = '{"schemaVersion":1,"refreshMinutes":5,"alwaysOnTop":false,"overlay":{"enabled":true,"visible":true,"opacity":' + $case.Opacity + ',"locked":false,"corner":"top-right","monitor":"","margin":12,"suppressFullscreen":false},"providers":[]}'
  Set-Content -LiteralPath (Join-Path $data 'settings.json') -Value $settings -Encoding UTF8
  $env:AI_USAGE_DATA_DIR = $data
  $env:AI_USAGE_UI_FIXTURES = '1'
  $env:AI_USAGE_UI_OVERLAY = '1'
  $env:AI_USAGE_UI_THEME = $case.Theme
  $process = Start-Process -FilePath $resolvedExecutable -PassThru
  try {
    $window = [IntPtr]::Zero
    for ($attempt = 0; $attempt -lt 40 -and $window -eq [IntPtr]::Zero; $attempt++) {
      Start-Sleep -Milliseconds 200
      $window = [OverlayCaptureNative]::Find([uint32]$process.Id)
    }
    if ($window -eq [IntPtr]::Zero) { throw "Overlay window not found for $($case.Name)" }
    Start-Sleep -Milliseconds 600
    $rect = New-Object OverlayCaptureNative+Rect
    if (-not [OverlayCaptureNative]::GetWindowRect($window, [ref]$rect)) { throw 'Overlay geometry unavailable' }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
      $bitmap.Save((Join-Path $OutputDirectory $case.Name), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $graphics.Dispose()
      $bitmap.Dispose()
    }
  } finally {
    $process.Refresh()
    if (-not $process.HasExited) { Stop-Process -Id $process.Id }
    Remove-Item -LiteralPath $data -Recurse -Force
  }
}

Remove-Item Env:AI_USAGE_DATA_DIR,Env:AI_USAGE_UI_FIXTURES,Env:AI_USAGE_UI_OVERLAY,Env:AI_USAGE_UI_THEME -ErrorAction SilentlyContinue
Write-Output "Overlay screenshots captured in $OutputDirectory"
