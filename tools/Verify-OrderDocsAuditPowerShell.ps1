$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$files = @(
    (Join-Path $root "tools\iRetailOrderDocsAudit.ps1"),
    (Join-Path $root "tools\iRetailOrderDependencyDocsAudit.ps1")
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
    Write-Host "[FAIL] Function name Curl conflicts with the Windows PowerShell curl alias."
    exit 3
}
if($text -notmatch '(?im)^\s*function\s+Invoke-CurlToFile\s*\('){
    Write-Host "[FAIL] Invoke-CurlToFile function was not found."
    exit 4
}
if($text -notmatch '&\s*curl\.exe'){
    Write-Host "[FAIL] curl.exe is not invoked explicitly."
    exit 5
}
Write-Host "[OK] S3 order docs PowerShell syntax/runtime-pattern checks passed."
exit 0
