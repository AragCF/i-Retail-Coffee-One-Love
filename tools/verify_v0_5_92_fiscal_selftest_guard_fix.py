from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
guard=(ROOT/"tools/verify_v0_5_81_fiscal_dry_run.py").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)
start=main.find("private fun startRealCardPayment()")
end=main.find("private fun finishPayment()", start)
payment_block=main[start:end] if start>=0 and end>start else ""

checks={
    "versionCode at least 92": bool(m) and int(m.group(1))>=92,
    "historical guard scopes payment function": 'main.find("private fun startRealCardPayment()")' in guard and 'main.find("private fun finishPayment()"' in guard,
    "payment block has confirmed transition": "markPaymentConfirmed()" in payment_block,
    "payment block invokes fiscal gateway after confirm": (
        payment_block.find("fiscalGateway.afterPaymentConfirmed(order)") >
        payment_block.find("markPaymentConfirmed()") >= 0
    ),
    "debug self-test remains separate": "private fun runFiscalDryRunSelfTest()" in main and start > main.find("private fun runFiscalDryRunSelfTest()"),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.92 guard fix verification failed: "+", ".join(failed))
print(f"[OK] v0.5.92 guard fix: {len(checks)} checks passed")
