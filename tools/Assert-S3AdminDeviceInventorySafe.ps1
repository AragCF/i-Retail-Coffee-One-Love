param([Parameter(Mandatory=$true)][string]$ZipPath)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$resolved = (Resolve-Path -LiteralPath $ZipPath).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($resolved)

try {
    $entries = @($archive.Entries)

    foreach($required in @("SUMMARY.json","80_inventory.json","90_results.json")) {
        if (-not ($entries | Where-Object { $_.FullName.Replace("\","/").Split("/")[-1] -eq $required })) {
            Write-Host ("[FAIL] Missing required entry: " + $required)
            exit 10
        }
    }

    foreach($entry in $entries) {
        if ($entry.FullName -match '(?i)(\.form$|\.raw$|auth\.json$|iretail-api\.json$)') {
            Write-Host ("[FAIL] Forbidden entry: " + $entry.FullName)
            exit 11
        }

        if ($entry.FullName -notmatch '(?i)\.(json|txt)$') { continue }
        $reader = New-Object IO.StreamReader($entry.Open())
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }

        foreach($pattern in @(
            '(?i)"[^"]*(token|password|secret)"\s*:\s*"(?!\[REDACTED\])[^"]+"',
            '(?i)"(device_code|external_code|code|code_device|username|phone|email|address)"\s*:\s*"(?!\[REDACTED\])[^"]+"',
            '(?i)"mutating_calls"\s*:\s*[1-9]',
            '(?i)"device_create_allowed"\s*:\s*true',
            '(?i)"device_update_allowed"\s*:\s*true',
            '(?i)"repeat_activation_allowed"\s*:\s*true',
            '(?i)"device_remove_allowed"\s*:\s*true',
            '(?i)"order_send_allowed"\s*:\s*true'
        )) {
            if ($text -match $pattern) {
                Write-Host ("[FAIL] Unsafe content in " + $entry.FullName)
                exit 12
            }
        }
    }

    Write-Host "[OK] S3 admin-device inventory ZIP safety validation passed."
    exit 0
}
finally {
    $archive.Dispose()
}
