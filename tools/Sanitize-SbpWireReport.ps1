param(
    [Parameter(Mandatory=$true)][string]$RawJl22,
    [Parameter(Mandatory=$true)][string]$RawKozen,
    [Parameter(Mandatory=$true)][string]$ReportDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Redact-Wire([string]$Text) {
    if ($null -eq $Text) { return "" }
    $v = $Text
    $v = [regex]::Replace(
        $v,
        '(?i)\b(payloadB64|qrPayload|payload|qrIdB64|qrId)=([^\s]+)',
        '$1=[REDACTED]'
    )
    $v = [regex]::Replace(
        $v,
        '(?i)\b(rrn|authCode|terminalId|paymentTid|transactionId)=([^\s]+)',
        '$1=[REDACTED]'
    )
    $v = [regex]::Replace($v, '(?<!\d)\d{13,19}(?!\d)', '[LONG_NUMBER_REDACTED]')
    return $v
}

$jl22 = if (Test-Path -LiteralPath $RawJl22) { Get-Content -Raw -LiteralPath $RawJl22 } else { "" }
$kozen = if (Test-Path -LiteralPath $RawKozen) { Get-Content -Raw -LiteralPath $RawKozen } else { "" }

$jl22Safe = Redact-Wire $jl22
$kozenSafe = Redact-Wire $kozen

Set-Content -LiteralPath (Join-Path $ReportDir "05_jl22_logcat.txt") -Value $jl22Safe -Encoding UTF8
Set-Content -LiteralPath (Join-Path $ReportDir "06_kozen_logcat.txt") -Value $kozenSafe -Encoding UTF8

Remove-Item -LiteralPath $RawJl22 -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $RawKozen -Force -ErrorAction SilentlyContinue

$all = (Get-ChildItem -LiteralPath $ReportDir -File | ForEach-Object {
    Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
}) -join [Environment]::NewLine

$forbidden = @(
    '(?i)\bpayloadB64=(?!\[REDACTED\])\S+',
    '(?i)\bqrIdB64=(?!\[REDACTED\])\S+',
    '(?i)\bqrPayload=(?!\[REDACTED\])\S+',
    '(?i)\bpayload=(?!\[REDACTED\])\S+',
    'SBP-SYNTHETIC-WIRE\|',
    '(?<!\d)\d{13,19}(?!\d)'
)

$hits = New-Object System.Collections.Generic.List[string]
foreach ($pattern in $forbidden) {
    if ($all -match $pattern) { $hits.Add($pattern) }
}
if ($hits.Count -gt 0) {
    foreach ($hit in $hits) { Write-Host "[SAFETY FAIL] $hit" }
    throw "SBP wire report safety scan failed"
}

Set-Content -LiteralPath (Join-Path $ReportDir "SAFETY_SCAN_OK.txt") -Value "SAFETY_SCAN_OK" -Encoding ASCII
Write-Host "[OK] SBP wire safety scan passed"
