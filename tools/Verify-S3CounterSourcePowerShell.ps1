$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$file = Join-Path $root "tools\iRetailCounterSourceDocsAudit.ps1"

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
if($errors.Count -gt 0){
    Write-Host "[FAIL] PowerShell syntax errors:"
    foreach($e in $errors){ Write-Host ("  " + $e.Message) }
    exit 1
}

$text = Get-Content -Raw -LiteralPath $file -Encoding UTF8

if($text -notmatch 'https://my\.i-retail\.com/api/apidoc/actual'){
    Write-Host "[FAIL] Documentation base URL missing."
    exit 2
}
if($text -notmatch 'app-controllers-iretail-\.\*controller'){
    Write-Host "[FAIL] Dynamic iretail controller discovery missing."
    exit 3
}
foreach($term in @("order_counter","operation_counter","refund_counter","check_counter","counters")){
    if($text -notmatch [Regex]::Escape($term)){
        Write-Host ("[FAIL] Counter term missing: " + $term)
        exit 4
    }
}
if($text -match '(?i)--request|--data|--form|--upload-file'){
    Write-Host "[FAIL] Non-GET curl option detected."
    exit 5
}
if($text -match '(?i)user/authentication|access_token|client_secret'){
    Write-Host "[FAIL] Working API authentication material detected."
    exit 6
}

Write-Host "[OK] S3 counter-source PowerShell syntax and safety checks passed."
exit 0
