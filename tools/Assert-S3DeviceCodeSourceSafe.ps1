param([Parameter(Mandatory=$true)][string]$ZipPath)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath).Path)
try {
    $names = @($archive.Entries | ForEach-Object { $_.FullName })
    foreach($required in @("SUMMARY.json","DEVICE_CODE_OBSERVATIONS.json")){
        if(-not ($names | Where-Object { $_.Replace("\","/").Split("/")[-1] -eq $required })){
            Write-Host ("[FAIL] Missing: " + $required)
            exit 10
        }
    }

    foreach($entry in $archive.Entries){
        if($entry.FullName -match '(?i)(\.form$|\.raw$|iretail-api\.json$|auth\.json$)'){
            Write-Host ("[FAIL] Forbidden entry: " + $entry.FullName)
            exit 11
        }
        if($entry.FullName -notmatch '(?i)\.json$'){ continue }
        $reader = New-Object IO.StreamReader($entry.Open())
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }

        foreach($pattern in @(
            '(?i)"(server_code|external_code|device_code|access_token|client_secret|password|username)"\s*:\s*"[^"]+"',
            '(?i)"register_calls"\s*:\s*[1-9]',
            '(?i)"order_send_allowed"\s*:\s*true',
            '(?i)"config_update_allowed"\s*:\s*true'
        )){
            if($text -match $pattern){
                Write-Host ("[FAIL] Unsafe content in " + $entry.FullName)
                exit 12
            }
        }
    }

    Write-Host "[OK] S3 device-code source ZIP safety validation passed."
    exit 0
}
finally {
    $archive.Dispose()
}
