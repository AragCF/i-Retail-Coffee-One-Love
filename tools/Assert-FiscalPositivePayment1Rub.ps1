param(
    [Parameter(Mandatory=$true)][string]$ReportDir,
    [Parameter(Mandatory=$true)][string]$ExpectedVersion,
    [Parameter(Mandatory=$true)][string]$Outcome
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Require-File([string]$Name) {
    $p = Join-Path $ReportDir $Name
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing report file: $Name" }
    return $p
}

function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ([string]$Actual -ne [string]$Expected) {
        throw "$Name mismatch: actual=$Actual expected=$Expected"
    }
}

$pkg = Require-File "02_package.txt"
$mode = Require-File "03_machine_mode.txt"
$marker = Require-File "04_attempt_marker.txt"
$jl22 = Require-File "05_jl22_logcat.txt"
$kozen = Require-File "06_kozen_logcat.txt"

$pkgText = Get-Content -Raw -LiteralPath $pkg
$modeText = Get-Content -Raw -LiteralPath $mode
$markerText = Get-Content -Raw -LiteralPath $marker
$jl22Text = Get-Content -Raw -LiteralPath $jl22
$kozenText = Get-Content -Raw -LiteralPath $kozen

if ($pkgText -notmatch [regex]::Escape("versionName=$ExpectedVersion")) { throw "Wrong installed version" }
if ($modeText -notmatch ">standalone<") { throw "Standalone mode not persisted" }
if ($modeText -notmatch 'name="real_pos_enabled" value="false"') { throw "Persisted real_pos_enabled is not false" }

if ($Outcome -eq "NO_ATTEMPT_TIMEOUT") {
    if ($markerText.Trim().Length -ne 0) { throw "Attempt marker exists although no attempt was expected" }
    if ($jl22Text -match "PAYMENT_TX_ONCE") { throw "PAYMENT was observed during NO_ATTEMPT outcome" }
    throw "No financial attempt was started; positive acceptance is not complete"
}

if ($markerText -notmatch "contract=S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1") { throw "Wrong attempt contract marker" }
if ($markerText -notmatch "amount_minor=100") { throw "Attempt marker amount is not 100 minor units" }
if ($markerText -notmatch "product_id=s3-fiscal-positive-test-1rub") { throw "Attempt marker product mismatch" }
if ($markerText -notmatch "claimed=true") { throw "Attempt marker was not claimed" }

$paymentTxCount = ([regex]::Matches($jl22Text, "PAYMENT_TX_ONCE")).Count
Assert-Equal $paymentTxCount 1 "PAYMENT_TX_ONCE count"

if ($jl22Text -notmatch "ATTEMPT_CLAIMED amountMinor=100 productId=s3-fiscal-positive-test-1rub") {
    throw "Controlled attempt marker log missing"
}
if ($jl22Text -notmatch "TEST_RUNTIME_POS_DISABLED") { throw "Runtime POS disable marker missing" }

if ($Outcome -ne "PAYMENT_APPROVED_FISCAL_READY") {
    throw "Financial attempt finished as $Outcome; a second payment is forbidden without new approval"
}

if ($jl22Text -notmatch "TEST_RESULT status=APPROVED") { throw "APPROVED test result missing" }
if ($jl22Text -notmatch "FISCAL_RESULT state=DRAFT_READY sendAllowed=false amountMinor=100 productId=s3-fiscal-positive-test-1rub") {
    throw "Positive FiscalGateway result missing"
}

$draftPath = Require-File "07_fiscalization_dry_run.json"
$draft = Get-Content -Raw -LiteralPath $draftPath -Encoding UTF8 | ConvertFrom-Json

Assert-Equal $draft.mode "DRY_RUN_ONLY" "mode"
Assert-Equal $draft.send_allowed $false "send_allowed"
Assert-Equal $draft.network_actions "NONE" "network_actions"
Assert-Equal $draft.credentials_present $false "credentials_present"
Assert-Equal $draft.order_state "PAID" "order_state"
Assert-Equal $draft.payment_method "CARD" "payment_method"
Assert-Equal $draft.gross_amount_minor 100 "gross_amount_minor"
Assert-Equal $draft.discount_minor 0 "discount_minor"
Assert-Equal $draft.payable_amount_minor 100 "payable_amount_minor"
Assert-Equal $draft.gross_lines_minor 100 "gross_lines_minor"
Assert-Equal $draft.gross_matches_runtime $true "gross_matches_runtime"
Assert-Equal $draft.payable_equation_matches $true "payable_equation_matches"
Assert-Equal $draft.products_count 1 "products_count"
Assert-Equal $draft.products_with_modifiers 0 "products_with_modifiers"

$product = $draft.product_evidence.product_0
Assert-Equal $product.catalog_id "s3-fiscal-positive-test-1rub" "catalog_id"
Assert-Equal $product.price_minor 100 "product price_minor"
Assert-Equal $product.quantity 1 "product quantity"
Assert-Equal $product.own_cup $false "own_cup"
Assert-Equal $product.syrup_added $false "syrup_added"

$form = $draft.form_fields_candidate
Assert-Equal $form.PSObject.Properties["card_amount"].Value "1.00" "card_amount"
Assert-Equal $form.PSObject.Properties["purchase[products][0][name]"].Value "S3 TEST PRODUCT 1 RUB" "product name"
Assert-Equal $form.PSObject.Properties["purchase[products][0][price]"].Value "1.00" "product price"
Assert-Equal $form.PSObject.Properties["purchase[products][0][quantity]"].Value 1 "product quantity form"

if ($jl22Text -match "order/synchronize") { throw "order/synchronize marker found" }
if ($jl22Text -match "sendAllowed=true") { throw "Fiscal network send marker found" }

Write-Host "[OK] One PAYMENT_TX_ONCE"
Write-Host "[OK] Payment amount: 1.00 RUB"
Write-Host "[OK] APPROVED -> PAID -> FiscalGateway DRAFT_READY"
Write-Host "[OK] DRY_RUN product and money invariants passed"
Write-Host "[OK] Persisted real POS is false"
exit 0
