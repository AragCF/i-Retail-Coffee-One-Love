param(
    [Parameter(Mandatory=$true)][string]$RawJl22,
    [Parameter(Mandatory=$true)][string]$RawKozen,
    [Parameter(Mandatory=$true)][string]$ReportDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Redact-Text([string]$Text) {
    $value = $Text
    $value = [regex]::Replace(
        $value,
        '(?i)\b(rrn|authCode|receipt|terminalId|transactionId|paymentTid)=([^\s]+)',
        '$1=[REDACTED]'
    )
    $value = [regex]::Replace(
        $value,
        '(?i)\b(pan|track1|track2|pin)=([^\s]+)',
        '$1=[REDACTED]'
    )
    $value = [regex]::Replace($value, '(?<!\d)\d{13,19}(?!\d)', '[LONG_NUMBER_REDACTED]')
    return $value
}

$jl22Out = Join-Path $ReportDir "05_jl22_logcat.txt"
$kozenOut = Join-Path $ReportDir "06_kozen_logcat.txt"

$jl22Text = if (Test-Path -LiteralPath $RawJl22) { Get-Content -Raw -LiteralPath $RawJl22 } else { "" }
$kozenText = if (Test-Path -LiteralPath $RawKozen) { Get-Content -Raw -LiteralPath $RawKozen } else { "" }

Set-Content -LiteralPath $jl22Out -Value (Redact-Text $jl22Text) -Encoding UTF8
Set-Content -LiteralPath $kozenOut -Value (Redact-Text $kozenText) -Encoding UTF8

Remove-Item -LiteralPath $RawJl22 -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $RawKozen -Force -ErrorAction SilentlyContinue

$forbidden = @(
    '(?i)\b(?:pan|track1|track2|pin|api_key|client_secret|access_token|device_code|external_code)\s*[:=]\s*(?!false\b|none\b|null\b|-)([^\s,}"'']+)',
    '(?i)\b(?:rrn|authCode|receipt|terminalId|transactionId|paymentTid)=(?!\[REDACTED\])[^\s]+',
    '(?<!\d)\d{13,19}(?!\d)'
)

$hits = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $ReportDir -File | ForEach-Object {
    if ($_.Name -eq "SAFETY_SCAN_OK.txt") { return }
    $text = Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
    foreach ($pattern in $forbidden) {
        if ($text -match $pattern) {
            $hits.Add($_.Name + " :: " + $pattern)
        }
    }
}

if ($hits.Count -gt 0) {
    $hits | ForEach-Object { Write-Host "[SAFETY FAIL] $_" }
    throw "Safety scan failed"
}

Set-Content -LiteralPath (Join-Path $ReportDir "SAFETY_SCAN_OK.txt") -Value "SAFETY_SCAN_OK" -Encoding ASCII
Write-Host "[OK] Safety scan passed"
exit 0
