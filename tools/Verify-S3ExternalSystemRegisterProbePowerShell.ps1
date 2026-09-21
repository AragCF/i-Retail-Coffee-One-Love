$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$probe = Join-Path $root "tools\iRetailControlledExternalSystemRegisterProbe.ps1"
$assert = Join-Path $root "tools\Assert-S3ExternalSystemRegisterProbeSafe.ps1"

foreach($file in @($probe,$assert)){
    $tokens=$null
    $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
    if($errors.Count -gt 0){
        Write-Host ("[FAIL] PowerShell syntax: " + $file)
        foreach($e in $errors){ Write-Host ("  " + $e.Message) }
        exit 1
    }
}

$text = Get-Content -Raw -LiteralPath $probe -Encoding UTF8
$needle = 'Invoke-CurlRequest ($baseUrl + "iretail/device/register-external-system")'
$callPos = $text.IndexOf($needle)
$markerPos = $text.IndexOf('Save-Marker "EXTERNAL_REGISTER_CALL_STARTED"')

if($callPos -lt 0){ Write-Host "[FAIL] external register call not found."; exit 2 }
if($markerPos -lt 0 -or $markerPos -ge $callPos){ Write-Host "[FAIL] marker must be written before external register."; exit 3 }
if(([regex]::Matches($text,[regex]::Escape($needle))).Count -ne 1){ Write-Host "[FAIL] external register invocation must occur exactly once."; exit 4 }
if($text -notmatch '"--retry","0"'){ Write-Host "[FAIL] curl retry=0 guard missing."; exit 5 }
if($text -notmatch [regex]::Escape('$externalSecrets $false')){ Write-Host "[FAIL] external register must disable redirects."; exit 6 }
if($text -notmatch 'ReadOnlyRecovery'){ Write-Host "[FAIL] recovery mode missing."; exit 7 }
if($text -notmatch 'automatic_device_binding=\$false'){ Write-Host "[FAIL] auto binding guard missing."; exit 8 }
if($text -notmatch 'config_update_allowed=\$false'){ Write-Host "[FAIL] config update guard missing."; exit 9 }
if($text -notmatch 'source_external_code_saved=\$false'){ Write-Host "[FAIL] external_code persistence guard missing."; exit 10 }

foreach($forbidden in @(
    '"iretail/device/register")',
    '"iretail/device/update-info"',
    '"iretail/shift/get-current"',
    '"iretail/shift/open-shift"',
    '"iretail/shift/close-shift"',
    '"iretail/employee/authorize"',
    '"iretail/payment-in/create"',
    '"iretail/order/synchronize"'
)){
    if($text.Contains($forbidden)){ Write-Host ("[FAIL] Forbidden route pattern: " + $forbidden); exit 11 }
}

Write-Host "[OK] S3 external-system register PowerShell one-shot guards passed."
exit 0
