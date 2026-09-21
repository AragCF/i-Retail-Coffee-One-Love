$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$file = Join-Path $root "tools\iRetailOrderDocsAudit.ps1"
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
if($errors.Count -gt 0){
    Write-Host "[FAIL] $file"
    foreach($e in $errors){ Write-Host ("  " + $e.Message) }
    exit 1
}
$text = Get-Content -Raw -LiteralPath $file -Encoding UTF8
if($text -match '\(\s*if\s*\('){
    Write-Host "[FAIL] Parenthesized if-expression detected."
    exit 2
}
Write-Host "[OK] S3 order docs PowerShell syntax/runtime-pattern checks passed."
exit 0
