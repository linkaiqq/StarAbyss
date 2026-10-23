# Windows.Media.Ocr helper for tools/ocr_check.py
#
# Why this exists: no agent in this project has image input, but Windows ships a Chinese OCR
# engine (Windows.Media.Ocr, zh-Hans-CN on this machine). That lets QA prove a UI string is
# actually RENDERED on screen instead of only present as a literal in source.
#
# This file is the WinRT plumbing only; all text handling / comparison happens in
# tools/ocr_check.py (UTF-8 safe). Invoke through ocr_check.py rather than directly.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\ocr_winrt.ps1 `
#       -Dir <folder> -Pattern <wildcard> [-Scale 2] -OutJson <path>
#
# Note: a path LIST cannot be passed safely (`powershell -File` mangles comma/semicolon
# separated arguments), hence Dir + Pattern.
param(
    [string]$Dir = '.',
    [string]$Pattern = '*.png',
    [int]$Scale = 2,
    [Parameter(Mandatory = $true)][string]$OutJson
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]

function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    [void]$netTask.Wait(-1)
    $netTask.Result
}

$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]

$engine = $null
foreach ($tag in @('zh-Hans-CN', 'zh-Hans', 'en-US')) {
    try {
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language $tag))
    }
    catch { $engine = $null }
    if ($null -ne $engine) { $usedLanguage = $tag; break }
}
if ($null -eq $engine) {
    throw 'no Windows.Media.Ocr engine available (install a language pack)'
}

$files = @(Get-ChildItem -Path (Join-Path $Dir $Pattern) -File | Sort-Object Name)
if ($files.Count -eq 0) { throw "no files matched $Pattern in $Dir" }

$results = @()
foreach ($f in $files) {
    # Canvas text is small; upscaling before OCR measurably improves CJK recognition.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ocr_' + [guid]::NewGuid().ToString('N') + '.png')
    $bmp = [System.Drawing.Bitmap]::FromFile($f.FullName)
    try {
        if ($Scale -ne 1) {
            $w = [int]($bmp.Width * $Scale); $h = [int]($bmp.Height * $Scale)
            $big = New-Object System.Drawing.Bitmap $w, $h
            $g = [System.Drawing.Graphics]::FromImage($big)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.DrawImage($bmp, 0, 0, $w, $h)
            $g.Dispose()
            $big.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
            $big.Dispose()
        }
        else {
            Copy-Item $f.FullName $tmp -Force
        }
    }
    finally { $bmp.Dispose() }

    $sf = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($tmp)) ([Windows.Storage.StorageFile])
    $stream = Await ($sf.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $software = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $ocr = Await ($engine.RecognizeAsync($software)) ([Windows.Media.Ocr.OcrResult])
    $stream.Dispose()
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue

    $lines = @()
    foreach ($line in $ocr.Lines) { $lines += $line.Text }

    $results += [ordered]@{
        file  = $f.FullName
        width = $bmp.Width
        lines = $lines
        text  = ($lines -join "`n")
    }
}

$payload = [ordered]@{
    engine_language = $usedLanguage
    scale           = $Scale
    results         = $results
}
$json = $payload | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($OutJson, $json, (New-Object System.Text.UTF8Encoding $false))
Write-Output ("OCR done: {0} image(s), engine {1}, json {2}" -f $results.Count, $usedLanguage, $OutJson)
