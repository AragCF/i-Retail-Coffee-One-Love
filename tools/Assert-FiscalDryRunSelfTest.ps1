param(
    [Parameter(Mandatory=$true)][string]$ReportDir,
    [Parameter(Mandatory=$true)][string]$ExpectedVersion
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version 2.0

$pkg=Join-Path $ReportDir "02_package.txt"
$mode=Join-Path $ReportDir "03_machine_mode.txt"
$log=Join-Path $ReportDir "04_logcat.txt"
$draftPath=Join-Path $ReportDir "05_fiscalization_dry_run.json"

foreach($p in @($pkg,$mode,$log,$draftPath)) {
    if(-not (Test-Path -LiteralPath $p)) { throw "Missing report file: $p" }
}

$pkgText=Get-Content -Raw -LiteralPath $pkg
$modeText=Get-Content -Raw -LiteralPath $mode
$logText=Get-Content -Raw -LiteralPath $log

if($pkgText -notmatch [regex]::Escape("versionName=$ExpectedVersion")) { throw "Wrong installed version" }
if($modeText -notmatch ">standalone<") { throw "Standalone mode not persisted" }
if($modeText -notmatch 'name="real_pos_enabled" value="false"') { throw "real_pos_enabled is not false" }

if($logText -match "PAYMENT_TX_ONCE|PAYMENT_CALL_BEGIN|PAYMENT_CALL_RESULT") { throw "Financial marker found" }
if($logText -notmatch "SELF_TEST_RESULT state=DRAFT_READY sendAllowed=false") { throw "DRAFT_READY self-test marker missing" }

$draft=Get-Content -Raw -LiteralPath $draftPath -Encoding UTF8 | ConvertFrom-Json

function Assert-Equal($Actual,$Expected,[string]$Name) {
    if([string]$Actual -ne [string]$Expected) {
        throw "$Name mismatch: actual=$Actual expected=$Expected"
    }
}

Assert-Equal $draft.mode "DRY_RUN_ONLY" "mode"
Assert-Equal $draft.send_allowed $false "send_allowed"
Assert-Equal $draft.network_actions "NONE" "network_actions"
Assert-Equal $draft.credentials_present $false "credentials_present"
Assert-Equal $draft.order_state "PAID" "order_state"
Assert-Equal $draft.payment_method "CARD" "payment_method"
Assert-Equal $draft.gross_amount_minor 1000 "gross_amount_minor"
Assert-Equal $draft.discount_minor 0 "discount_minor"
Assert-Equal $draft.payable_amount_minor 1000 "payable_amount_minor"
Assert-Equal $draft.gross_lines_minor 1000 "gross_lines_minor"
Assert-Equal $draft.gross_matches_runtime $true "gross_matches_runtime"
Assert-Equal $draft.payable_equation_matches $true "payable_equation_matches"
Assert-Equal $draft.products_count 1 "products_count"
Assert-Equal $draft.products_with_modifiers 0 "products_with_modifiers"

$cardAmount=$draft.form_fields_candidate.PSObject.Properties["card_amount"].Value
Assert-Equal $cardAmount "10.00" "card_amount"

$productName=$draft.form_fields_candidate.PSObject.Properties["purchase[products][0][name]"].Value
$productPrice=$draft.form_fields_candidate.PSObject.Properties["purchase[products][0][price]"].Value
$productQuantity=$draft.form_fields_candidate.PSObject.Properties["purchase[products][0][quantity]"].Value
Assert-Equal $productName "Fiscal DRY_RUN Self Test" "product name"
Assert-Equal $productPrice "10.00" "product price"
Assert-Equal $productQuantity 1 "product quantity"

if([string]$draft.external_order_id -notlike "FISCAL-SELFTEST-*") { throw "Synthetic external_order_id missing" }

Write-Host "[OK] Installed version: $ExpectedVersion"
Write-Host "[OK] STANDALONE persisted, real POS disabled"
Write-Host "[OK] No financial markers"
Write-Host "[OK] FiscalGateway state=DRAFT_READY"
Write-Host "[OK] DRY_RUN money/product invariants passed"
exit 0
