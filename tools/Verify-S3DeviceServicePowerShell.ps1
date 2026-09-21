$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$files = @(
    (Join-Path $root "tools\iRetailDeviceServiceReconciliation.ps1"),
    (Join-Path $root "tools\Assert-S3DeviceServiceSafe.ps1")
)

foreach($file in $files){
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
    if($errors.Count -gt 0){
        Write-Host "[FAIL] $file"
        foreach($e in $errors){ Write-Host ("  " + $e.Message) }
        exit 1
    }
}

$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_ -Encoding UTF8 }) -join [Environment]::NewLine

if($text -match '\(\s*if\s*\('){
    Write-Host "[FAIL] Parenthesized if-expression detected."
    exit 2
}
if($text -match '(?im)^\s*function\s+Curl\s*\('){
    Write-Host "[FAIL] Function name Curl conflicts with Windows PowerShell alias."
    exit 3
}
if($text -notmatch '&\s*curl\.exe'){
    Write-Host "[FAIL] curl.exe is not invoked explicitly."
    exit 4
}
if($text -match 'profile_services\s*=\s*@\(\$profileServiceItems\)' -or $text -match 'used_services\s*=\s*@\(\$usedServiceItems\)'){
    Write-Host "[FAIL] Windows PowerShell generic-list array binding pattern detected."
    exit 5
}
if($text -notmatch '\$profileServiceItems\.ToArray\(\)' -or $text -notmatch '\$usedServiceItems\.ToArray\(\)'){
    Write-Host "[FAIL] Generic service lists are not converted with ToArray()."
    exit 6
}

Write-Host "[OK] S3 device/service PowerShell syntax/runtime-pattern checks passed."
exit 0
