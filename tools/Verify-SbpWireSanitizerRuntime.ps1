$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$sanitizer = Join-Path $PSScriptRoot "Sanitize-SbpWireReport.ps1"
$temp = Join-Path ([IO.Path]::GetTempPath()) ("iretail_sbp_wire_" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $rawPayload = "U0JQLVNZTlRIRVRJQy1TRUNSRVQtUEFZTE9BRA"
    $rawQr = "c3ludGhldGljLTQxMDE"
    $jl22 = Join-Path $temp "RAW_jl22_logcat.txt"
    $kozen = Join-Path $temp "RAW_kozen_logcat.txt"

    "RX_STALE SBP_QR 4101 code=0 qrIdB64=$rawQr payloadB64=$rawPayload synthetic=true" |
        Set-Content -LiteralPath $jl22 -Encoding UTF8
    "TX SBP_QR 4101 code=0 qrIdB64=$rawQr payloadB64=$rawPayload synthetic=true" |
        Set-Content -LiteralPath $kozen -Encoding UTF8

    & $sanitizer -RawJl22 $jl22 -RawKozen $kozen -ReportDir $temp

    if (Test-Path -LiteralPath $jl22) { throw "Raw JL22 log survived" }
    if (Test-Path -LiteralPath $kozen) { throw "Raw Kozen log survived" }

    $safeFiles = @(
        (Join-Path $temp "05_jl22_logcat.txt"),
        (Join-Path $temp "06_kozen_logcat.txt"),
        (Join-Path $temp "SAFETY_SCAN_OK.txt")
    )
    foreach ($p in $safeFiles) {
        if (-not (Test-Path -LiteralPath $p)) { throw "Missing safe output: $p" }
    }

    $all = (Get-ChildItem -LiteralPath $temp -File | ForEach-Object {
        Get-Content -Raw -LiteralPath $_.FullName
    }) -join [Environment]::NewLine

    if ($all.Contains($rawPayload)) { throw "Raw payloadB64 survived" }
    if ($all.Contains($rawQr)) { throw "Raw qrIdB64 survived" }
    if ($all -notmatch 'payloadB64=\[REDACTED\]') { throw "payloadB64 redaction marker missing" }
    if ($all -notmatch 'qrIdB64=\[REDACTED\]') { throw "qrIdB64 redaction marker missing" }
    if ($all -notmatch 'SAFETY_SCAN_OK') { throw "Safety marker missing" }

    Write-Host "[OK] SBP wire sanitizer runtime fixture passed"
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
