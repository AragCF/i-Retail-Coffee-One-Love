$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$files = @(
    (Join-Path $root "tools\iRetailAdminDeviceInventoryAudit.ps1"),
    (Join-Path $root "tools\Assert-S3AdminDeviceInventorySafe.ps1")
)

foreach($file in $files) {
    $tokens=$null
    $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
    if($errors.Count -gt 0) {
        foreach($e in $errors) { Write-Host ("[FAIL] " + $e.Message) }
        exit 1
    }
}

$text = Get-Content -Raw -LiteralPath $files[0] -Encoding UTF8

foreach($required in @(
    'admin/device/find',
    'admin/device/get-count-device-in-channel',
    'admin/device/get-device-info',
    'admin/device/get-list-device-involved-in-orders'
)) {
    if(-not $text.Contains($required)) {
        Write-Host ("[FAIL] Missing read-only route: " + $required)
        exit 2
    }
}

foreach($forbidden in @(
    'admin/device/create',
    'admin/device/update',
    'admin/device/remove',
    'admin/device/repeat-activation',
    'admin/device/restore',
    'admin/device/block',
    'admin/device/unlock',
    'iretail/device/register',
    'iretail/device/register-external-system',
    'iretail/order/synchronize',
    'iretail/payment-in/create',
    'iretail/shift/open-shift',
    'iretail/shift/close-shift'
)) {
    if($text.Contains($forbidden)) {
        Write-Host ("[FAIL] Forbidden route: " + $forbidden)
        exit 3
    }
}

Write-Host "[OK] S3 admin-device inventory PowerShell guard passed."
exit 0
