$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$files = @(
    (Join-Path $root "tools\iRetailDeviceCodeSourceAudit.ps1"),
    (Join-Path $root "tools\Assert-S3DeviceCodeSourceSafe.ps1")
)

foreach($file in $files){
    $tokens=$null
    $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
    if($errors.Count -gt 0){
        foreach($e in $errors){ Write-Host ("[FAIL] " + $e.Message) }
        exit 1
    }
}

$text = Get-Content -Raw -LiteralPath $files[0] -Encoding UTF8
foreach($forbidden in @(
    'iretail/device/register',
    'iretail/device/update-info',
    'iretail/device/register-external-system',
    'iretail/shift/get-current',
    'iretail/shift/open-shift',
    'iretail/shift/close-shift',
    'iretail/order/synchronize',
    'iretail/payment-in/create'
)){
    if($text.Contains($forbidden)){
        Write-Host ("[FAIL] Forbidden route: " + $forbidden)
        exit 2
    }
}
if($text -notmatch 'get-by-channel-id' -or $text -notmatch 'get-device-info'){
    Write-Host "[FAIL] Required read-only device routes missing."
    exit 3
}

Write-Host "[OK] S3 device-code source PowerShell guard passed."
exit 0
