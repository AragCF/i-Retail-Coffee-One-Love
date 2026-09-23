from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
bat=(ROOT/"MAIN_25_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
ps=(ROOT/"tools/Assert-FiscalDryRunSelfTest.ps1").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)
checks={
    "versionCode at least 91": bool(m) and int(m.group(1))>=91,
    "debug guard": "BuildConfig.DEBUG" in main,
    "explicit self-test extra": "fiscal_dry_run_self_test" in main and "fiscal_dry_run_self_test" in bat,
    "synthetic paid order": "OrderStatus.PAID" in main and "PaymentMethod.CARD" in main,
    "synthetic exact amount": "amountMinor = 1000L" in main and "grossAmountMinor = 1000L" in main,
    "one product no modifiers": 'id = "fiscal-selftest-product"' in main and "quantity = 1" in main,
    "uses FiscalGateway": "fiscalGateway.afterPaymentConfirmed(order)" in main,
    "real POS must be false in self-test": "SELF_TEST_REJECTED reason=REAL_POS_ENABLED" in main,
    "bat persists real pos false": "--ez real_pos_enabled false" in bat,
    "bat never enables real pos": "--ez real_pos_enabled true" not in bat,
    "bat no payment script": "MAIN_22_REAL_UI_PAYMENT_TEST" not in bat and "AOA_14_PAYMENT" not in bat,
    "bat no Kozen": "KOZEN" not in bat,
    "bat no cloud fiscal network": "curl " not in bat.lower() and "kassa.i-bonus.me" not in bat,
    "validator requires DRAFT_READY": "SELF_TEST_RESULT state=DRAFT_READY sendAllowed=false" in ps,
    "validator exact card amount": '"10.00"' in ps and "card_amount" in ps,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.91 fiscal self-test guard failed: "+", ".join(failed))
print(f"[OK] v0.5.91 fiscal self-test guard: {len(checks)} checks passed")
