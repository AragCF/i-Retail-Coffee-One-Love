$ErrorActionPreference="Stop"

$root=(Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$files=@(
    (Join-Path $root "tools\iRetailAdminAuthPermissionAudit.ps1"),
    (Join-Path $root "tools\Assert-S3AdminAuthPermissionSafe.ps1")
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

$text=Get-Content -Raw -LiteralPath $files[0] -Encoding UTF8

foreach($required in @(
    'user/authentication',
    'user/admin-authentication',
    'user/get-permissions',
    'user/get-profile-list',
    'admin/device/find'
)) {
    if(-not $text.Contains($required)) {
        Write-Host ("[FAIL] Missing required read-only route: " + $required)
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

Write-Host "[OK] S3 admin-auth permission PowerShell guard passed."
exit 0
