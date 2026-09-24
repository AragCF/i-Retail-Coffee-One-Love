$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$analyzer = Join-Path $PSScriptRoot "Analyze-FiscalPaymentMarkerAudit.ps1"
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("iretail_marker_audit_" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Path $temp | Out-Null
try {
    @"
contract=S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1
amount_minor=100
product_id=s3-fiscal-positive-test-1rub
claimed=true
"@ | Set-Content -LiteralPath (Join-Path $temp "03_marker_raw.txt") -Encoding UTF8

    @"
<map>
<string name="unresolved_request_id">ui-20260924012345-abcd</string>
<string name="unresolved_amount">1.00</string>
<string name="unresolved_tid">1234567890123456</string>
</map>
"@ | Set-Content -LiteralPath (Join-Path $temp "05_jl22_payment_prefs_raw.txt") -Encoding UTF8

    "PAYMENT_TX_ONCE requestId=ui-20260924012345-abcd amount=1.00 terminalId=1234567890123456" |
        Set-Content -LiteralPath (Join-Path $temp "06_jl22_logcat_raw.txt") -Encoding UTF8

    @"
{
  "external_order_id": "FISCAL-SELFTEST-1760000000000",
  "form_fields_candidate": {
    "card_amount": "1.00"
  }
}
"@ | Set-Content -LiteralPath (Join-Path $temp "07_fiscalization_dry_run.txt") -Encoding UTF8

    @"
<map>
<string name="active_request">ui-20260924012345-abcd</string>
<string name="payment.ui-20260924012345-abcd.status">STARTED</string>
<string name="payment.ui-20260924012345-abcd.tid">1234567890123456</string>
</map>
"@ | Set-Content -LiteralPath (Join-Path $temp "08_kozen_bridge_prefs_raw.txt") -Encoding UTF8

    "PAYMENT_CALL_BEGIN requestId=ui-20260924012345-abcd terminalId=1234567890123456" |
        Set-Content -LiteralPath (Join-Path $temp "09_kozen_logcat_raw.txt") -Encoding UTF8

    "WINDOWS_CONSUMED_MARKER_NOT_FOUND" |
        Set-Content -LiteralPath (Join-Path $temp "10_windows_consumed_marker.txt") -Encoding UTF8

    & $analyzer -ReportDir $temp

    $required = @(
        "SUMMARY.txt",
        "03_marker_safe.txt",
        "05_jl22_payment_prefs_safe.txt",
        "06_jl22_logcat_safe.txt",
        "07_fiscalization_dry_run_safe.txt",
        "08_kozen_bridge_prefs_safe.txt",
        "09_kozen_logcat_safe.txt",
        "SAFETY_SCAN_OK.txt"
    )
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $temp $name))) {
            throw "Missing safe audit file: $name"
        }
    }

    foreach ($name in @(
        "03_marker_raw.txt",
        "05_jl22_payment_prefs_raw.txt",
        "06_jl22_logcat_raw.txt",
        "07_fiscalization_dry_run.txt",
        "08_kozen_bridge_prefs_raw.txt",
        "09_kozen_logcat_raw.txt"
    )) {
        if (Test-Path -LiteralPath (Join-Path $temp $name)) {
            throw "Raw audit file survived sanitization: $name"
        }
    }

    $all = (Get-ChildItem -LiteralPath $temp -File | ForEach-Object {
        Get-Content -Raw -LiteralPath $_.FullName
    }) -join [Environment]::NewLine

    if ($all -match '(?<!\d)\d{13,19}(?!\d)') {
        throw "Long numeric token survived sanitizer"
    }
    if ($all -match 'terminalId=(?!\[REDACTED\])') {
        throw "terminalId survived sanitizer"
    }

    $summary = Get-Content -Raw -LiteralPath (Join-Path $temp "SUMMARY.txt")
    if ($summary -notmatch "outcome=UNRESOLVED_PAYMENT_PRESENT") {
        throw "Unexpected audit outcome in runtime fixture"
    }

    Write-Host "[OK] Marker audit runtime sanitization fixture passed"
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
