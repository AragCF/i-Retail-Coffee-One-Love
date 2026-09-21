param(
    [Parameter(Mandatory=$true)]
    [string]$ZipPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ZipPath)) {
    Write-Host "[FAIL] ZIP not found: $ZipPath"
    exit 2
}

$tmp = Join-Path $env:TEMP ("iretail_s3_v2_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tmp -Force

    $jsonFile = Get-ChildItem -LiteralPath $tmp -Recurse -File |
        Where-Object { $_.Name -eq "01_order_sync_draft.json" } |
        Select-Object -First 1

    if ($null -eq $jsonFile) {
        Write-Host "[FAIL] 01_order_sync_draft.json not found in ZIP."
        exit 3
    }

    $raw = Get-Content -Raw -LiteralPath $jsonFile.FullName -Encoding UTF8
    $doc = $raw | ConvertFrom-Json

    if ($doc.mode -ne "DRY_RUN_ONLY") {
        Write-Host "[FAIL] mode is not DRY_RUN_ONLY."
        exit 4
    }
    if ($doc.schema_version -ne "S3_DRY_RUN_V2") {
        Write-Host "[FAIL] schema_version is not S3_DRY_RUN_V2."
        exit 5
    }
    if ($doc.send_allowed -ne $false) {
        Write-Host "[FAIL] send_allowed must be false."
        exit 6
    }
    if ($doc.contract_state -ne "BLOCKED_PENDING_DEVICE_REGISTER_DECISION") {
        Write-Host "[FAIL] contract_state is not blocked at device/register decision."
        exit 7
    }
    if ($doc.validation.lines_equal_gross -ne $true) {
        Write-Host "[FAIL] lines_equal_gross must be true."
        exit 8
    }

    $request = $doc.candidate_request
    if ($null -ne $request.device_id) {
        Write-Host "[FAIL] candidate_request.device_id must remain null."
        exit 9
    }
    if ($null -ne $request.counters.order_counter -or
        $null -ne $request.counters.operation_counter -or
        $null -ne $request.counters.refund_counter) {
        Write-Host "[FAIL] counters must remain unresolved."
        exit 10
    }
    if ($null -ne $request.shift.id -or $null -ne $request.shift.check_counter) {
        Write-Host "[FAIL] shift must remain unresolved."
        exit 11
    }

    $orderItem = @($request.orders)[0]
    foreach ($field in @("employee_id","shift_id","device_id","order_status_id","payment_status_id","order_number","short_number","number_to_day","service_in_slug")) {
        if ($null -ne $orderItem.$field) {
            Write-Host ("[FAIL] wire field must remain unresolved: " + $field)
            exit 12
        }
    }

    if (@($orderItem.products).Count -lt 1) {
        Write-Host "[FAIL] No products in DRY_RUN v2."
        exit 13
    }

    if ($raw -match '(?i)"(?:access[_-]?token|client[_-]?secret|password|device_code|pin)"\s*:') {
        Write-Host "[FAIL] Sensitive key detected in DRY_RUN v2 JSON."
        exit 14
    }

    Write-Host "[OK] S3 DRY_RUN v2 ZIP safety validation passed."
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
