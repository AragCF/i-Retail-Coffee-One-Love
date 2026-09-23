from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
bat = (ROOT / "MAIN_26_FISCAL_POSITIVE_PAYMENT_1RUB_TEST.bat").read_text(encoding="utf-8")
pub = (ROOT / "GIT_126_PUBLISH_FISCAL_POSITIVE_PAYMENT_1RUB.bat").read_text(encoding="utf-8")
contract = (ROOT / "docs/S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1.md").read_text(encoding="utf-8")
sanitize = (ROOT / "tools/Sanitize-FiscalPositivePaymentReport.ps1").read_text(encoding="utf-8")
assert_ps = (ROOT / "tools/Assert-FiscalPositivePayment1Rub.ps1").read_text(encoding="utf-8")

checks = {
    "versionCode 98+": bool(re.search(r"versionCode\s+(9[8-9]|[1-9]\d{2,})", gradle)),
    "versionName v0.5.98": "versionName '0.5.98-fiscal-positive-payment-test'" in gradle,
    "approved contract": "APPROVED_FOR_ONE_ATTEMPT" in contract,
    "exact one ruble": "100 копеек" in contract and "1,00 ₽" in contract,
    "test product isolated": 'id = "s3-fiscal-positive-test-1rub"' in main and "catalog = listOf(fiscalPositivePaymentTestProduct)" in main,
    "test price 100 minor": "priceMinor = 100L" in main,
    "debug standalone gate": "positiveTestRequested && debuggable && machineModeConfig.standalone && realPosEnabled" in main,
    "runtime pos not persisted": "--ez real_pos_enabled true --ez fiscal_positive_payment_test true" in bat and "--ez persist_machine_mode true --ez real_pos_enabled true" not in bat,
    "persisted false baseline": "--ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true" in bat,
    "one attempt marker Android": "fiscal_positive_payment_test_v1_0_1.attempt" in main,
    "one attempt marker Windows": "FISCAL_POSITIVE_PAYMENT_v1_0_1_CONSUMED.marker" in bat,
    "previous unresolved blocks": "PREVIOUS_UNRESOLVED" in main and "unresolved_request_id" in bat,
    "exact cart guards": "cartGrossTotalMinor() != 100L" in main and "line.quantity != 1" in main and "line.ownCup || line.syrupAdded" in main,
    "runtime order guards": "order.grossAmountMinor != 100L" in main and "order.ibonusDiscountMinor != 0L" in main,
    "no Windows PAYMENT command": not bool(re.search(r"adb[^\n\r]*\bPAYMENT\b", bat, re.I)),
    "app disables runtime pos": "TEST_RUNTIME_POS_DISABLED" in main,
    "Windows disables persisted pos": bat.count("--ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true") >= 2,
    "fiscal proof": "FISCAL_RESULT state=" in main and "PAYMENT_APPROVED_FISCAL_READY" in bat,
    "DRY_RUN assertion": 'Assert-Equal $draft.network_actions "NONE"' in assert_ps and 'Assert-Equal $draft.send_allowed $false' in assert_ps,
    "product assertion": 's3-fiscal-positive-test-1rub' in assert_ps and '"1.00"' in assert_ps,
    "safety sanitizer": "rrn|authCode|receipt|terminalId|transactionId|paymentTid" in sanitize,
    "safety publication gate": "SAFETY_SCAN_OK" in pub and ".safe.txt" in pub,
    "generic report push current head": "git push origin HEAD" in pub,
    "no cloud fiscal in test script": "cloud_fiscal_sent=false" in bat,
    "no order sync in test script": "order_sync_sent=false" in bat,
    "no brewing in test script": "brewing_started=false" in bat,
}

failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("v0.5.98 controlled payment guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.98 controlled payment guard: {len(checks)} checks passed")
