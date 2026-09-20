$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$audit = Join-Path $root "tools\iRetailApiCurlAudit.ps1"
$text = Get-Content -Raw -LiteralPath $audit -Encoding UTF8

if ($text -match '\(\s*if\s*\(') {
    Write-Host "[FAIL] Parenthesized if-expression detected in iRetailApiCurlAudit.ps1"
    exit 1
}

if (-not $text.Contains('$docSize = 0')) {
    Write-Host "[FAIL] Explicit docSize initialization not found."
    exit 2
}

if (-not $text.Contains('size = $docSize')) {
    Write-Host "[FAIL] docInfo size does not use explicit docSize variable."
    exit 3
}

Write-Host "[OK] Retail API audit runtime-pattern checks passed."
exit 0
