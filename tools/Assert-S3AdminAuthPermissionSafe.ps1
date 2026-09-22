param([Parameter(Mandatory=$true)][string]$ZipPath)

$ErrorActionPreference="Stop"
Set-StrictMode -Version 2.0

$resolved=(Resolve-Path -LiteralPath $ZipPath).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($resolved)

try {
    $entries=@($archive.Entries)

    foreach($required in @("SUMMARY.json","10_ordinary_auth_sanitized.json","11_admin_auth_sanitized.json")) {
        if(-not ($entries | Where-Object { $_.FullName.Replace("\","/").Split("/")[-1] -eq $required })) {
            Write-Host ("[FAIL] Missing required entry: " + $required)
            exit 10
        }
    }

    foreach($entry in $entries) {
        if($entry.FullName -match '(?i)(\.form$|\.raw$|iretail-api\.json$|auth\.json$)') {
            Write-Host ("[FAIL] Forbidden ZIP entry: " + $entry.FullName)
            exit 11
        }

        if($entry.FullName -notmatch '(?i)\.(txt|json)$') { continue }

        $reader=New-Object IO.StreamReader($entry.Open())
        try { $text=$reader.ReadToEnd() } finally { $reader.Dispose() }

        foreach($pattern in @(
            '(?i)"[^"]*(token|password|secret)"\s*:\s*"(?!\[REDACTED\])[^"]+"',
            '(?i)"(username|email|phone|first_name|last_name|full_name|address|inn|device_code|external_code|code_device)"\s*:\s*"(?!\[REDACTED\])[^"]+"',
            '(?i)"mutating_calls"\s*:\s*[1-9]',
            '(?i)"admin_device_create_allowed"\s*:\s*true',
            '(?i)"admin_device_update_allowed"\s*:\s*true',
            '(?i)"repeat_activation_allowed"\s*:\s*true',
            '(?i)"device_register_allowed"\s*:\s*true',
            '(?i)"order_send_allowed"\s*:\s*true'
        )) {
            if($text -match $pattern) {
                Write-Host ("[FAIL] Unsafe content in " + $entry.FullName)
                exit 12
            }
        }
    }

    Write-Host "[OK] S3 admin-auth permission ZIP safety validation passed."
    exit 0
}
finally {
    $archive.Dispose()
}
