# Star Abyss performance benchmark runner.
#
# Runs the real game in a real Forward+ window and samples wall-clock frame times,
# render-thread timings and engine monitors. Nothing is headless and nothing is
# faked: the numbers come from continuous rendering with continuous input from the
# in-game bot.
#
# Works on Windows PowerShell 5.1 (the previous version required PowerShell 7 for
# ProcessStartInfo.ArgumentList, which this machine does not have).
#
# This machine's execution policy rejects unsigned scripts, so always launch it with
# -ExecutionPolicy Bypass (that is what the command lines below do):
#
# Quick start (from the project root):
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1      # 1920x1080, capped at 60
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Resolution 1280x720 -FrameCap 60 -Label 720p60
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -FrameCap 0 -Label 1080p-uncapped
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Suite benchmark -Resolution 1920x1080 -FrameCap 0
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Info -Resolution 1280x720
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Matrix   # 2 resolutions x capped/uncapped
#
# Requirements and cautions:
#   * the desktop window is opened and owns the foreground; do not move the mouse or
#     click while it runs (native pointer motion pollutes the injected input);
#   * never run this while another Godot process uses the same project (shared .godot
#     cache makes the engine crash with 0xC0000005);
#   * a run is ~55-60 s at the 60 FPS cap and ~45-50 s uncapped.

#Requires -Version 5.1
[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [string]$GodotPath,
    [ValidatePattern('^\d{3,4}x\d{3,4}$')][string]$Resolution = '1920x1080',
    [ValidateRange(0, 480)][int]$FrameCap = 60,
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Label = '',
    [ValidateRange(1, 3)][int]$Rounds = 1,
    [ValidateSet('probe', 'benchmark')][string]$Suite = 'probe',
    [switch]$Info,
    [switch]$Matrix
)

$ErrorActionPreference = 'Stop'

$benchmarkRoot = Split-Path -Parent $PSScriptRoot
$benchmarkGodot = if ($GodotPath) { $GodotPath } else { 'D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe' }
$benchmarkLogs = Join-Path $benchmarkRoot '.local\validation'
$benchmarkAppData = Join-Path $benchmarkRoot '.local\appdata'
$benchmarkLocalAppData = Join-Path $benchmarkRoot '.local\localappdata'

# Engine lines this sandbox produces (redirected APPDATA, unreadable certificate
# store, no writable editor-settings directory). They are not game defects.
$benchmarkIgnored = @(
    'Failed to read the root certificate store',
    "Can't save resource to empty path",
    'Error saving editor settings to'
)

if (-not (Test-Path -LiteralPath $benchmarkGodot -PathType Leaf)) { throw "Missing engine: $benchmarkGodot" }
New-Item -ItemType Directory -Path $benchmarkLogs, $benchmarkAppData, $benchmarkLocalAppData -Force | Out-Null

function Invoke-BenchmarkRun {
    param(
        [Parameter(Mandatory)][string]$RunLabel,
        [Parameter(Mandatory)][string]$RunResolution,
        [Parameter(Mandatory)][int]$RunFrameCap,
        [Parameter(Mandatory)][string]$RunSuite,
        [switch]$RunInfo
    )

    $benchmarkLog = Join-Path $benchmarkLogs "performance_$RunLabel.log"
    $benchmarkOut = Join-Path $benchmarkLogs "performance_$RunLabel.stdout.txt"
    $benchmarkErr = Join-Path $benchmarkLogs "performance_$RunLabel.stderr.txt"

    $benchmarkArgs = @('--path', (Join-Path $benchmarkRoot 'godot'), '--disable-vsync', '--log-file', $benchmarkLog)
    if ($RunInfo) {
        $benchmarkArgs += @('--script', '../tools/performance_probe.gd', '--', '--mode=info', "--resolution=$RunResolution")
    }
    elseif ($RunSuite -eq 'benchmark') {
        # The shipped suite pins its own 1920x1080 framebuffer and always uncaps.
        $benchmarkArgs += @('--resolution', $RunResolution, '--script', 'res://tests/performance_benchmark.gd', '--', "--label=$RunLabel", "--rounds=$Rounds")
    }
    else {
        $benchmarkArgs += @('--script', '../tools/performance_probe.gd', '--', "--label=$RunLabel", "--resolution=$RunResolution", "--fps=$RunFrameCap", "--rounds=$Rounds")
    }
    # ProcessStartInfo + a single Arguments string: Start-Process -PassThru does not
    # expose ExitCode on Windows PowerShell 5.1, and ArgumentList is PowerShell 7 only.
    $benchmarkQuoted = ($benchmarkArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $benchmarkStart = New-Object System.Diagnostics.ProcessStartInfo
    $benchmarkStart.FileName = $benchmarkGodot
    $benchmarkStart.WorkingDirectory = $benchmarkRoot
    $benchmarkStart.UseShellExecute = $false
    $benchmarkStart.CreateNoWindow = $true
    $benchmarkStart.RedirectStandardOutput = $true
    $benchmarkStart.RedirectStandardError = $true
    $benchmarkStart.Arguments = $benchmarkQuoted
    $benchmarkStart.EnvironmentVariables['APPDATA'] = $benchmarkAppData
    $benchmarkStart.EnvironmentVariables['LOCALAPPDATA'] = $benchmarkLocalAppData

    Write-Output "RUN $RunLabel ($RunSuite, $RunResolution, frame cap $(if ($RunFrameCap -eq 0) { 'off' } else { $RunFrameCap })) ..."
    $benchmarkProcess = [System.Diagnostics.Process]::Start($benchmarkStart)
    $benchmarkStdout = $benchmarkProcess.StandardOutput.ReadToEndAsync()
    $benchmarkStderr = $benchmarkProcess.StandardError.ReadToEndAsync()
    # Sample memory while it runs; PeakWorkingSet64 is unreadable after exit on 5.1.
    $benchmarkPeakWorkingSet = 0.0
    $benchmarkDeadline = [DateTime]::UtcNow.AddSeconds(600)
    while (-not $benchmarkProcess.WaitForExit(1000)) {
        if ([DateTime]::UtcNow -gt $benchmarkDeadline) {
            $benchmarkProcess.Kill()
            throw "Benchmark '$RunLabel' exceeded the ten-minute safety bound"
        }
        try {
            $benchmarkWorkingSet = [math]::Round($benchmarkProcess.WorkingSet64 / 1MB, 1)
            if ($benchmarkWorkingSet -gt $benchmarkPeakWorkingSet) { $benchmarkPeakWorkingSet = $benchmarkWorkingSet }
        }
        catch { }
    }
    $benchmarkExit = $benchmarkProcess.ExitCode
    $benchmarkProcess.Dispose()

    $benchmarkText = $benchmarkStdout.GetAwaiter().GetResult() + $benchmarkStderr.GetAwaiter().GetResult()
    Set-Content -LiteralPath $benchmarkOut -Value $benchmarkText -Encoding utf8
    if (Test-Path -LiteralPath $benchmarkErr) { Remove-Item -LiteralPath $benchmarkErr -Force }
    $benchmarkEngineLog = if (Test-Path -LiteralPath $benchmarkLog) { Get-Content -LiteralPath $benchmarkLog -Raw } else { '' }
    if ($RunInfo) {
        # Info mode prints the banner plus a pretty-printed JSON block; show it all.
        Write-Output $benchmarkText.TrimEnd()
        Write-Output "log: $benchmarkLog"
        return
    }

    $benchmarkFailureLines = @()
    foreach ($benchmarkLine in (($benchmarkText, $benchmarkEngineLog) | Out-String) -split "`r?`n") {
        if ($benchmarkLine -match '^(SCRIPT ERROR:|ERROR:|FAIL:)') {
            if (-not ($benchmarkIgnored | Where-Object { $benchmarkLine.Contains($_) })) { $benchmarkFailureLines += $benchmarkLine }
        }
    }

    # The shipped suite writes performance_<label>.json; the probe writes
    # performance_probe_<label>.json (see the two scripts' report destinations).
    $benchmarkReportName = if ($RunSuite -eq 'benchmark') { "performance_$RunLabel.json" } else { "performance_probe_$RunLabel.json" }
    $benchmarkReportPath = Join-Path $benchmarkLogs $benchmarkReportName
    if (-not (Test-Path -LiteralPath $benchmarkReportPath)) { throw "Benchmark '$RunLabel' produced no JSON report (exit $benchmarkExit)" }
    $benchmarkReport = Get-Content -LiteralPath $benchmarkReportPath -Raw | ConvertFrom-Json
    $benchmarkReport | Add-Member -NotePropertyName 'process_peak_working_set_mb' -NotePropertyValue $benchmarkPeakWorkingSet -Force
    $benchmarkReport | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $benchmarkReportPath -Encoding utf8

    if ($benchmarkExit -ne 0 -or $benchmarkFailureLines.Count -gt 0 -or $benchmarkReport.failures -ne 0) {
        Write-Output $benchmarkText
        throw "Benchmark '$RunLabel' failed (exit $benchmarkExit, $($benchmarkReport.failures) assertion failures, $($benchmarkFailureLines.Count) error lines); see $benchmarkOut"
    }
    Write-Output "PASS: $RunLabel -> $benchmarkReportPath (exit 0, $($benchmarkReport.checks) checks, peak working set $benchmarkPeakWorkingSet MB)"
    foreach ($benchmarkPhase in $benchmarkReport.phases.PSObject.Properties) {
        $benchmarkValue = $benchmarkPhase.Value
        if ($benchmarkValue.samples -le 0) { continue }
        Write-Output ("  {0,-18} {1,8:N1} FPS  p50 {2,6:N2}  p95 {3,6:N2}  p99 {4,7:N2}  max {5,8:N2} ms  GPU p95 {6,5:N2} ms  {7} frames" -f `
                $benchmarkPhase.Name, $benchmarkValue.mean_fps, $benchmarkValue.wall_ms_p50, $benchmarkValue.wall_ms_p95, `
                $benchmarkValue.wall_ms_p99, $benchmarkValue.wall_ms_max, $benchmarkValue.gpu_ms_p95, $benchmarkValue.samples)
    }
}

if ($Info) {
    Invoke-BenchmarkRun -RunLabel 'info' -RunResolution $Resolution -RunFrameCap 0 -RunSuite 'probe' -RunInfo
    return
}

if ($Matrix) {
    foreach ($benchmarkMatrixCap in @(60, 0)) {
        foreach ($benchmarkMatrixResolution in @('1920x1080', '1280x720')) {
            $benchmarkCapLabel = if ($benchmarkMatrixCap -eq 0) { 'uncapped' } else { "capped$benchmarkMatrixCap" }
            $benchmarkResolutionLabel = if ($benchmarkMatrixResolution -eq '1920x1080') { '1080p' } else { '720p' }
            Invoke-BenchmarkRun -RunLabel "$benchmarkResolutionLabel-$benchmarkCapLabel" -RunResolution $benchmarkMatrixResolution `
                -RunFrameCap $benchmarkMatrixCap -RunSuite 'probe'
        }
    }
    return
}

$benchmarkFinalLabel = if ($Label) { $Label } elseif ($Suite -eq 'benchmark') { 'latest' } else {
    $benchmarkCapSuffix = if ($FrameCap -eq 0) { 'uncapped' } else { "capped$FrameCap" }
    "$Resolution-$benchmarkCapSuffix"
}
Invoke-BenchmarkRun -RunLabel $benchmarkFinalLabel -RunResolution $Resolution -RunFrameCap $FrameCap -RunSuite $Suite
