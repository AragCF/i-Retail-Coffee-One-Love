from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)
checks={
    "versionCode at least 93": bool(m) and int(m.group(1))>=93,
    "BuildConfig import removed": "com.coffeeonelove.iretail.BuildConfig" not in main,
    "Android debuggable flag used": "ApplicationInfo.FLAG_DEBUGGABLE" in main,
    "non-debug rejected": "SELF_TEST_REJECTED reason=NOT_DEBUG_BUILD" in main,
    "real POS still rejected": "SELF_TEST_REJECTED reason=REAL_POS_ENABLED" in main,
    "self-test still uses FiscalGateway": "fiscalGateway.afterPaymentConfirmed(order)" in main,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.93 build fix verification failed: "+", ".join(failed))
print(f"[OK] v0.5.93 build fix: {len(checks)} checks passed")
