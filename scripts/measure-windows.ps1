[CmdletBinding()]
param(
    [string]$Executable = "build/windows-release/ai-usage-monitor.exe",
    [int]$WarmupSeconds = 60,
    [int]$CpuSampleSeconds = 300,
    [int]$NetworkPollMilliseconds = 500,
    [switch]$OverlayEnabled
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$exe = [IO.Path]::GetFullPath((Join-Path $root $Executable))
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Executable not found: $exe" }

$existingIds = @(Get-Process ai-usage-monitor -ErrorAction SilentlyContinue | ForEach-Object Id)
if ($existingIds.Count -ne 0) { throw "Close the existing AI Usage Monitor instance before measuring" }
$measurementData = Join-Path ([IO.Path]::GetTempPath()) ("ai-usage-monitor-measure-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $measurementData | Out-Null
$previousDataOverride = $env:AI_USAGE_DATA_DIR
$env:AI_USAGE_DATA_DIR = $measurementData
$overlay = if ($OverlayEnabled) { ',"overlay":{"enabled":true,"visible":true,"opacity":78,"locked":true,"corner":"top-right","monitor":"","margin":12,"suppressFullscreen":false}' } else { '' }
$settings = '{"schemaVersion":1,"refreshMinutes":5,"alwaysOnTop":false' + $overlay + ',"providers":[{"id":"idle-fixture","name":"Idle fixture","kind":"openai-compatible","enabled":false}]}'
Set-Content -LiteralPath (Join-Path $measurementData "settings.json") -Value $settings -Encoding UTF8
$readySignal = Join-Path $measurementData "ready.signal"
$startedAt = [Diagnostics.Stopwatch]::StartNew()
Start-Process -FilePath $exe | Out-Null
try {
    $process = $null
    while (-not (Test-Path -LiteralPath $readySignal -PathType Leaf)) {
        if ($startedAt.ElapsedMilliseconds -gt 5000) { throw "Application did not publish its tray-ready signal" }
        Start-Sleep -Milliseconds 20
        $process = Get-Process ai-usage-monitor -ErrorAction SilentlyContinue |
            Sort-Object WorkingSet64 -Descending | Select-Object -First 1
        if ($null -eq $process) { continue }
    }
    $startupMs = $startedAt.ElapsedMilliseconds
    $residentIds = @(Get-Process ai-usage-monitor -ErrorAction SilentlyContinue | ForEach-Object Id)
    Start-Process -FilePath $exe | Out-Null
    Start-Sleep -Seconds 1
    $afterSecondLaunch = @(Get-Process ai-usage-monitor -ErrorAction SilentlyContinue | ForEach-Object Id)
    $unexpectedInstances = @($afterSecondLaunch | Where-Object { $residentIds -notcontains $_ })
    if ($unexpectedInstances.Count -ne 0) { throw "Single-instance gate failed" }
    Start-Sleep -Seconds $WarmupSeconds
    $process.Refresh()
    $beforeCpu = $process.TotalProcessorTime.TotalMilliseconds
    $networkConnections = @()
    $sampleTimer = [Diagnostics.Stopwatch]::StartNew()
    while ($sampleTimer.Elapsed.TotalSeconds -lt $CpuSampleSeconds) {
        $networkConnections += @(Get-NetTCPConnection -OwningProcess $process.Id -ErrorAction SilentlyContinue |
            Where-Object { $_.State -ne "Listen" -and $_.RemoteAddress -notin @("0.0.0.0", "::") } |
            Select-Object -First 1)
        Start-Sleep -Milliseconds $NetworkPollMilliseconds
        $process.Refresh()
        if ($process.HasExited) { throw "Application exited during idle measurement" }
    }
    $process.Refresh()
    $workingSetMiB = [Math]::Round($process.WorkingSet64 / 1MB, 2)
    $cpuPercent = [Math]::Round((($process.TotalProcessorTime.TotalMilliseconds - $beforeCpu) / ($sampleTimer.Elapsed.TotalMilliseconds)) * 100, 3)
    $sizeMiB = [Math]::Round((Get-Item -LiteralPath $exe).Length / 1MB, 2)
    $networkQuiet = $networkConnections.Count -eq 0
    [pscustomobject]@{ OverlayEnabled = [bool]$OverlayEnabled; SizeMiB = $sizeMiB; StartupMs = $startupMs; WorkingSetMiB = $workingSetMiB; IdleCpuPercent = $cpuPercent; SingleInstance = $true; NetworkQuiet = $networkQuiet }
    if ($sizeMiB -gt 15) { throw "Size gate failed" }
    if ($workingSetMiB -gt 35) { throw "Working-set gate failed" }
    if ($cpuPercent -gt 0.2) { throw "Idle CPU gate failed" }
    if ($startupMs -gt 750) { throw "Startup gate failed" }
    if (-not $networkQuiet) { throw "Network-idle gate failed" }
} finally {
    Get-Process ai-usage-monitor -ErrorAction SilentlyContinue |
        Where-Object { $existingIds -notcontains $_.Id } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    if ($null -eq $previousDataOverride) { Remove-Item Env:AI_USAGE_DATA_DIR -ErrorAction SilentlyContinue } else { $env:AI_USAGE_DATA_DIR = $previousDataOverride }
    if (Test-Path -LiteralPath $measurementData) { Remove-Item -LiteralPath $measurementData -Recurse -Force }
}
