$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$files = @(
    (Join-Path $root "tools\iRetailApiCurlAudit.ps1"),
    (Join-Path $root "tools\Assert-RetailApiAuditSafe.ps1")
)

$failed = $false
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        Write-Host ("[FAIL] " + $file)
        foreach ($errorItem in $errors) { Write-Host ("  " + $errorItem.Message) }
        $failed = $true
    } else {
        Write-Host ("[OK] " + $file)
    }
}
if ($failed) { exit 1 }
Write-Host "[OK] PowerShell syntax checks passed."
exit 0
