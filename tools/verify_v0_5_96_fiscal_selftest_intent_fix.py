from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
bat=(ROOT/"MAIN_25_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

checks={
    "versionCode at least 96": bool(re.search(r"versionCode\s+(9[6-9]|[1-9]\d{2,})",gradle)),
    "current version": "versionName '0.5.96-fiscal-selftest-intent-fix'" in gradle,
    "trigger helper": "maybeRunFiscalDryRunSelfTest" in main,
    "onCreate trigger": 'maybeRunFiscalDryRunSelfTest(intent, "onCreate")' in main,
    "onNewIntent trigger": 'maybeRunFiscalDryRunSelfTest(intent, "onNewIntent")' in main,
    "trigger log": "SELF_TEST_TRIGGER source=" in main,
    "extra removed after trigger": 'intent.removeExtra("fiscal_dry_run_self_test")' in main,
    "force-stop before diagnostic start": bat.find("am force-stop com.coffeeonelove.iretail") < bat.find("--ez fiscal_dry_run_self_test true"),
    "waits for DRAFT_READY": "for /l %%S in (1,1,10)" in bat and "SELF_TEST_RESULT state=DRAFT_READY sendAllowed=false" in bat,
    "real POS remains false": "--ez real_pos_enabled false" in bat and "--ez real_pos_enabled true" not in bat,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.96 intent fix guard failed: "+", ".join(failed))
print(f"[OK] v0.5.96 intent fix guard: {len(checks)} checks passed")
