$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$probe = Join-Path $root "tools\iRetailControlledDeviceRegisterProbe.ps1"
$assert = Join-Path $root "tools\Assert-S3DeviceRegisterProbeSafe.ps1"

foreach($file in @($probe,$assert)){
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
    if($errors.Count -gt 0){
        Write-Host ("[FAIL] PowerShell syntax: " + $file)
        foreach($e in $errors){ Write-Host ("  " + $e.Message) }
        exit 1
    }
}

$text = Get-Content -Raw -LiteralPath $probe -Encoding UTF8
$registerNeedle = 'Invoke-CurlRequest ($baseUrl + "iretail/device/register")'
$registerPos = $text.IndexOf($registerNeedle)
$markerPos = $text.IndexOf('Save-Marker "REGISTER_CALL_STARTED"')

if($registerPos -lt 0){ Write-Host "[FAIL] Controlled register call not found."; exit 2 }
if($markerPos -lt 0 -or $markerPos -ge $registerPos){ Write-Host "[FAIL] Marker must precede register."; exit 3 }
if(([regex]::Matches($text,[regex]::Escape($registerNeedle))).Count -ne 1){ Write-Host "[FAIL] Register invocation count must be one."; exit 4 }
if($text -notmatch '"--retry","0"'){ Write-Host "[FAIL] curl retry=0 missing."; exit 5 }
if($text -notmatch [regex]::Escape('$requestSecrets $false')){ Write-Host "[FAIL] Register must disable redirects."; exit 6 }
if($text -notmatch 'ReadOnlyRecovery'){ Write-Host "[FAIL] Recovery mode missing."; exit 7 }
if($text -notmatch 'automatic_device_binding=\$false'){ Write-Host "[FAIL] Auto binding guard missing."; exit 8 }
if($text -notmatch 'config_update_allowed=\$false'){ Write-Host "[FAIL] Config update guard missing."; exit 9 }

foreach($forbidden in @(
    "iretail/device/register-external-system",
    "iretail/device/update-info",
    "iretail/shift/open-shift",
    "iretail/shift/close-shift",
    "iretail/employee/authorize",
    "iretail/payment-in/create",
    "iretail/order/synchronize"
)){
    if($text.Contains($forbidden)){ Write-Host ("[FAIL] Forbidden route: " + $forbidden); exit 10 }
}
if($text.Contains('"iretail/shift/get-current"')){ Write-Host "[FAIL] shift/get-current forbidden."; exit 11 }

Write-Host "[OK] S3 device/register PowerShell syntax and one-shot guards passed."
exit 0
