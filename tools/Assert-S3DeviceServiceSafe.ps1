param([Parameter(Mandatory=$true)][string]$ZipPath)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$resolved = (Resolve-Path -LiteralPath $ZipPath).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = [IO.Compression.ZipFile]::OpenRead($resolved)
try {
    $names = @($archive.Entries | ForEach-Object { $_.FullName })

    foreach($required in @("SUMMARY.txt","SUMMARY.json","80_device_checks.json","90_results.json")) {
        if ($names -notcontains $required) {
            Write-Host "[FAIL] Missing required entry: $required"
            exit 10
        }
    }

    $forbiddenNamePatterns = @(
        '(?i)\.form$',
        '(?i)\.raw$',
        '(?i)auth\.json$',
        '(?i)iretail-api\.json$',
        '(?i)config.*secret'
    )

    foreach($entry in $archive.Entries) {
        foreach($pattern in $forbiddenNamePatterns) {
            if ($entry.FullName -match $pattern) {
                Write-Host ("[FAIL] Forbidden ZIP entry: " + $entry.FullName)
                exit 11
            }
        }
    }

    foreach($entry in $archive.Entries) {
        if ($entry.FullName -notmatch '(?i)\.(txt|json)$') { continue }

        $reader = New-Object IO.StreamReader($entry.Open())
        try {
            $text = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }

        $patterns = @(
            '(?i)"(access_token|refresh_token|client_secret|password)"\s*:\s*"(?!\[REDACTED\])[^"]+"',
            '(?i)"pin"\s*:\s*"(?!\[REDACTED\])[^"]+"',
            '(?i)"(device_code|external_code)"\s*:\s*"(?!\[REDACTED\])[^"]+"',
            '(?i)"(username|phone|email|first_name|last_name|patronymic|full_name|address|inn|serial|serial_number|fn_serial|kkt_serial|mac|ip|url_ofd)"\s*:\s*"(?!\[REDACTED\])[^"]+"'
        )

        foreach($pattern in $patterns) {
            if ($text -match $pattern) {
                Write-Host ("[FAIL] Unredacted sensitive field in " + $entry.FullName)
                exit 12
            }
        }

        if ($text -match '(?i)"order_send_allowed"\s*:\s*true') {
            Write-Host ("[FAIL] order_send_allowed=true in " + $entry.FullName)
            exit 13
        }

        if ($text -match '(?i)"automatic_device_selection"\s*:\s*true') {
            Write-Host ("[FAIL] automatic_device_selection=true in " + $entry.FullName)
            exit 14
        }
    }

    Write-Host "[OK] S3 device/service ZIP safety validation passed."
    exit 0
}
finally {
    $archive.Dispose()
}
