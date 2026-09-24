param(
    [Parameter(Mandatory=$true)][string]$ReportDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Read-Text([string]$Name) {
    $p = Join-Path $ReportDir $Name
    if (-not (Test-Path -LiteralPath $p)) { return "" }
    return Get-Content -Raw -LiteralPath $p -ErrorAction SilentlyContinue
}

function Xml-StringValue([string]$Text, [string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $pattern = '<string name="' + [regex]::Escape($Name) + '">([^<]*)</string>'
    $m = [regex]::Match($Text, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Redact([string]$Text) {
    if ($null -eq $Text) { return "" }
    $v = $Text
    $v = [regex]::Replace(
        $v,
        '(?i)\b(rrn|authCode|receipt|terminalId|transactionId|paymentTid)=([^\s<"]+)',
        '$1=[REDACTED]'
    )
    $v = [regex]::Replace(
        $v,
        '(?i)\b(pan|track1|track2|pin)=([^\s<"]+)',
        '$1=[REDACTED]'
    )
    $v = [regex]::Replace(
        $v,
        '(?i)(<string name="(?:unresolved_tid|payment\.[^"]+\.tid)">)[^<]*(</string>)',
        '$1[REDACTED]$2'
    )
    $v = [regex]::Replace($v, '(?<!\d)\d{13,19}(?!\d)', '[LONG_NUMBER_REDACTED]')
    return $v
}

$marker = Read-Text "03_marker_raw.txt"
$jl22Prefs = Read-Text "05_jl22_payment_prefs_raw.txt"
$jl22Log = Read-Text "06_jl22_logcat_raw.txt"
$kozenPrefs = Read-Text "08_kozen_bridge_prefs_raw.txt"
$kozenLog = Read-Text "09_kozen_logcat_raw.txt"
$windowsMarker = Read-Text "10_windows_consumed_marker.txt"

$markerPresent = $marker -match "S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1"
$unresolvedId = Xml-StringValue $jl22Prefs "unresolved_request_id"
$unresolvedAmount = Xml-StringValue $jl22Prefs "unresolved_amount"
$kozenActive = Xml-StringValue $kozenPrefs "active_request"

$paymentTxCount = ([regex]::Matches($jl22Log, "PAYMENT_TX_ONCE")).Count
$attemptClaimCount = ([regex]::Matches($jl22Log, "ATTEMPT_CLAIMED")).Count
$testResultCount = ([regex]::Matches($jl22Log, "TEST_RESULT status=")).Count
$kozenCallBeginCount = ([regex]::Matches($kozenLog, "PAYMENT_CALL_BEGIN")).Count
$kozenCallResultCount = ([regex]::Matches($kozenLog, "PAYMENT_CALL_RESULT")).Count
$windowsConsumed = $windowsMarker -match "consumed=true"

$statusMatches = [regex]::Matches(
    $kozenPrefs,
    '<string name="payment\.([^"]+)\.status">([^<]*)</string>'
)
$records = New-Object System.Collections.Generic.List[object]
foreach ($m in $statusMatches) {
    $records.Add([pscustomobject]@{
        request_id = $m.Groups[1].Value
        status = $m.Groups[2].Value
    })
}

$outcome = "NO_MARKER"
if ($markerPresent) {
    if (-not [string]::IsNullOrWhiteSpace($unresolvedId) -or -not [string]::IsNullOrWhiteSpace($kozenActive)) {
        $outcome = "UNRESOLVED_PAYMENT_PRESENT"
    } elseif ($paymentTxCount -gt 0 -or $kozenCallBeginCount -gt 0 -or $windowsConsumed) {
        $outcome = "DIRECT_PAYMENT_EVIDENCE_FOUND"
    } elseif ($records.Count -gt 0) {
        $outcome = "MARKER_PRESENT_WITH_KOZEN_PAYMENT_HISTORY"
    } else {
        $outcome = "MARKER_PRESENT_NO_DIRECT_PAYMENT_EVIDENCE"
    }
}

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("===== PAYMENT MARKER AUDIT =====")
$summary.Add("outcome=$outcome")
$summary.Add("read_only=true")
$summary.Add("payment_sent_by_audit=false")
$summary.Add("marker_present=" + $markerPresent.ToString().ToLowerInvariant())
$summary.Add("windows_consumed_marker=" + $windowsConsumed.ToString().ToLowerInvariant())
$summary.Add("jl22_unresolved_present=" + (-not [string]::IsNullOrWhiteSpace($unresolvedId)).ToString().ToLowerInvariant())
$summary.Add("jl22_unresolved_request_id=" + $(if ($unresolvedId) { $unresolvedId } else { "-" }))
$summary.Add("jl22_unresolved_amount=" + $(if ($unresolvedAmount) { $unresolvedAmount } else { "-" }))
$summary.Add("kozen_active_request_present=" + (-not [string]::IsNullOrWhiteSpace($kozenActive)).ToString().ToLowerInvariant())
$summary.Add("kozen_active_request=" + $(if ($kozenActive) { $kozenActive } else { "-" }))
$summary.Add("jl22_payment_tx_once_log_count=$paymentTxCount")
$summary.Add("jl22_attempt_claim_log_count=$attemptClaimCount")
$summary.Add("jl22_test_result_log_count=$testResultCount")
$summary.Add("kozen_payment_call_begin_log_count=$kozenCallBeginCount")
$summary.Add("kozen_payment_call_result_log_count=$kozenCallResultCount")
$summary.Add("kozen_persisted_payment_status_count=" + $records.Count)
$summary.Add("")
$summary.Add("===== RECENT KOZEN PAYMENT STATUS RECORDS =====")
$recent = @($records | Sort-Object request_id -Descending | Select-Object -First 10)
if ($recent.Count -eq 0) {
    $summary.Add("(none)")
} else {
    foreach ($r in $recent) {
        $summary.Add(("request_id={0} status={1}" -f $r.request_id, $r.status))
    }
}
$summary.Add("")
$summary.Add("IMPORTANT: this audit does not delete the marker, does not clear payment state, and does not authorize another payment.")

$summaryText = ($summary -join [Environment]::NewLine)
Set-Content -LiteralPath (Join-Path $ReportDir "SUMMARY.txt") -Value (Redact $summaryText) -Encoding UTF8

$rawFiles = @(
    "03_marker_raw.txt",
    "05_jl22_payment_prefs_raw.txt",
    "06_jl22_logcat_raw.txt",
    "08_kozen_bridge_prefs_raw.txt",
    "09_kozen_logcat_raw.txt"
)
foreach ($name in $rawFiles) {
    $src = Join-Path $ReportDir $name
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $safeName = $name.Replace("_raw", "_safe")
    $safePath = Join-Path $ReportDir $safeName
    $text = Get-Content -Raw -LiteralPath $src -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $safePath -Value (Redact $text) -Encoding UTF8
    Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
}

$draftRaw = Join-Path $ReportDir "07_fiscalization_dry_run.txt"
if (Test-Path -LiteralPath $draftRaw) {
    $draftSafe = Join-Path $ReportDir "07_fiscalization_dry_run_safe.txt"
    $draftText = Get-Content -Raw -LiteralPath $draftRaw -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $draftSafe -Value (Redact $draftText) -Encoding UTF8
    Remove-Item -LiteralPath $draftRaw -Force -ErrorAction SilentlyContinue
}

$forbidden = @(
    '(?i)\b(?:pan|track1|track2|pin)\s*[:=]\s*(?!\[REDACTED\])[^\s]+',
    '(?i)\b(?:rrn|authCode|receipt|terminalId|transactionId|paymentTid)=(?!\[REDACTED\])[^\s]+',
    '(?<!\d)\d{13,19}(?!\d)'
)
$hits = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $ReportDir -File | ForEach-Object {
    $text = Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
    foreach ($pattern in $forbidden) {
        if ($text -match $pattern) { $hits.Add($_.Name + " :: " + $pattern) }
    }
}
if ($hits.Count -gt 0) {
    $hits | ForEach-Object { Write-Host "[SAFETY FAIL] $_" }
    throw "Marker audit safety scan failed"
}

Set-Content -LiteralPath (Join-Path $ReportDir "SAFETY_SCAN_OK.txt") -Value "SAFETY_SCAN_OK" -Encoding ASCII
Get-Content -LiteralPath (Join-Path $ReportDir "SUMMARY.txt")
