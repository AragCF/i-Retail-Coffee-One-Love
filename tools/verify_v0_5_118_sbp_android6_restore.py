from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
sbp = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpDryRun.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
runner = (ROOT / "MAIN_30_SBP_DRYRUN_UI_TEST.bat").read_text(encoding="utf-8")
helper = (ROOT / "tools/WAIT_FOR_JL22.bat").read_text(encoding="utf-8")

version_code_match = re.search(r"versionCode\s+(\d+)", gradle)
version_name_match = re.search(r"versionName\s+'([^']+)'", gradle)
version_code = int(version_code_match.group(1)) if version_code_match else 0
version_name = version_name_match.group(1) if version_name_match else ""

force_stop_pos = runner.find("am force-stop com.coffeeonelove.iretail")
self_test_pos = runner.find("--ez sbp_dry_run_self_test true")

checks = {
    "app version 0.5.118": version_code == 118 and version_name == "0.5.118-sbp-android6-restore-fix",
    "restore still exists": "fun restore(record: SbpSessionRecord)" in sbp,
    "restore no longer uses updateAndGet lambda": "generationCounter.updateAndGet" not in sbp,
    "restore uses API-safe CAS": "generationCounter.compareAndSet" in sbp and "generationCounter.get()" in sbp,
    "restore avoids java.util.function imports": "import java.util.function" not in sbp and "java.util.function." not in sbp,
    "restore keeps generation monotonic": "while (observed < record.generation)" in sbp,
    "saved session recovery is preserved": "sbpSessionStore.loadActive()" in main and "sbpDryRunSession.restore(recovered)" in main,
    "runner targets current version": bool(version_name) and version_name in runner,
    "runner starts from fresh process": force_stop_pos >= 0 and self_test_pos > force_stop_pos,
    "runner keeps durable session": "clear data" not in runner.lower() and "pm clear" not in runner.lower(),
    "runner collects AndroidRuntime": "AndroidRuntime:E" in runner,
    "runner fails fast on fatal exception": 'findstr /C:"FATAL EXCEPTION:"' in runner and "DRY_RUN_CRASH" in runner,
    "runner fails fast on missing class": 'findstr /C:"NoClassDefFoundError"' in runner,
    "runner waits for JL22 before restore": runner.count('tools\\WAIT_FOR_JL22.bat" JL22') >= 3,
    "JL22 helper still supports Ctrl+C": "Ctrl+C" in helper and ":WAIT_LOOP" in helper,
    "real POS stays false": "--ez real_pos_enabled true" not in runner,
    "no financial adb command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QR_PAYMENT|QRPAYMENT|REFUND|RECONCILIATION)\b", runner, re.I)),
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.118 Android 6 SBP restore guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.118 Android 6 SBP restore guard: {len(checks)} checks passed")
