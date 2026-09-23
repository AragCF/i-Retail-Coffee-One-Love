from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
bat = (ROOT / "MAIN_25_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

m = re.search(r"versionCode\s+(\d+)", gradle)
checks = {
    "versionCode at least 96": bool(m) and int(m.group(1)) >= 96,
    "trigger helper": "maybeRunFiscalDryRunSelfTest" in main,
    "onCreate trigger": 'maybeRunFiscalDryRunSelfTest(intent, "onCreate")' in main,
    "onNewIntent trigger": 'maybeRunFiscalDryRunSelfTest(intent, "onNewIntent")' in main,
    "trigger log": "SELF_TEST_TRIGGER source=" in main,
    "extra removed": 'intent.removeExtra("fiscal_dry_run_self_test")' in main,
    "force stop before selftest": bat.find("am force-stop com.coffeeonelove.iretail") < bat.find("--ez fiscal_dry_run_self_test true"),
    "wait for result": "for /l %%S in (1,1,10)" in bat,
    "real POS never enabled": "--ez real_pos_enabled true" not in bat,
}
failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("intent guard failed: " + ", ".join(failed))
print(f"[OK] intent guard: {len(checks)} checks passed")
