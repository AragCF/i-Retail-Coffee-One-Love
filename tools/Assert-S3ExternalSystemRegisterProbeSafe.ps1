param([Parameter(Mandatory=$true)][string]$ZipPath)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$resolved = (Resolve-Path -LiteralPath $ZipPath).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($resolved)

try {
    $entries = @($archive.Entries)
    $summaryEntry = $entries | Where-Object { $_.FullName -match '(^|[\\/])SUMMARY\.json$' } | Select-Object -First 1

    if ($null -eq $summaryEntry) {
        Write-Host "[FAIL] SUMMARY.json missing."
        exit 10
    }

    foreach ($entry in $entries) {
        if ($entry.FullName -match '(?i)(\.form$|\.raw$|iretail-api\.json$|auth\.json$)') {
            Write-Host ("[FAIL] Forbidden ZIP entry: " + $entry.FullName)
            exit 11
        }
    }

    $reader = New-Object IO.StreamReader($summaryEntry.Open())
    try { $summaryText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $summary = $summaryText | ConvertFrom-Json

    if ($summary.order_send_allowed -ne $false) { Write-Host "[FAIL] order_send_allowed must be false."; exit 12 }
    if ($summary.config_update_allowed -ne $false) { Write-Host "[FAIL] config_update_allowed must be false."; exit 13 }
    if ($summary.external_register_retry_allowed -ne $false) { Write-Host "[FAIL] retry must be false."; exit 14 }

    if ($summary.mode -eq "CONTROLLED_EXTERNAL_REGISTER_PROBE") {
        if ([int]$summary.external_register_calls -ne 1) {
            Write-Host "[FAIL] controlled probe must record exactly one external register call."
            exit 15
        }
        if ($summary.automatic_device_binding -ne $false) {
            Write-Host "[FAIL] automatic_device_binding must be false."
            exit 16
        }
        if ($summary.source_external_code_saved -ne $false) {
            Write-Host "[FAIL] external_code must not be saved."
            exit 17
        }
    } elseif ($summary.mode -eq "READ_ONLY_RECOVERY") {
        if ([int]$summary.external_register_calls -ne 0) {
            Write-Host "[FAIL] recovery must record zero external register calls."
            exit 18
        }
    } else {
        Write-Host ("[FAIL] Unsupported report mode: " + [string]$summary.mode)
        exit 19
    }

    foreach ($entry in $entries) {
        if ($entry.FullName -notmatch '(?i)\.(txt|json)$') { continue }

        $r = New-Object IO.StreamReader($entry.Open())
        try { $text = $r.ReadToEnd() } finally { $r.Dispose() }

        $patterns = @(
            '(?i)"[^"]*(token|password|secret)"\s*:\s*"(?!\[REDACTED\])[^"]+"',
            '(?i)"pin"\s*:\s*"(?!\[REDACTED\])[^"]+"',
            '(?i)"(device_code|external_code)"\s*:\s*"(?!\[REDACTED\])[^"]+"',
            '(?i)"(username|phone|email|first_name|last_name|patronymic|full_name|address|inn|serial|serial_number|fn_serial|kkt_serial|mac|ip|url_ofd|account_id|user_id|offline_shop_id)"\s*:\s*"(?!\[REDACTED\])[^"]+"'
        )

        foreach ($pattern in $patterns) {
            if ($text -match $pattern) {
                Write-Host ("[FAIL] Unredacted sensitive field in " + $entry.FullName)
                exit 20
            }
        }
    }

    Write-Host "[OK] S3 external-system register ZIP safety validation passed."
    exit 0
}
finally {
    $archive.Dispose()
}
