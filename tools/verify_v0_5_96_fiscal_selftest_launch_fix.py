from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
bat=(ROOT/"MAIN_25_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
force=bat.find('am force-stop com.coffeeonelove.iretail')
launch=bat.find('--ez fiscal_dry_run_self_test true')
checks={
 "versionCode 96+": bool(re.search(r"versionCode\s+(9[6-9]|[1-9]\d{2,})",gradle)),
 "current version": "versionName '0.5.96-fiscal-selftest-launch-fix'" in gradle,
 "force-stop before self-test": force >= 0 and launch > force,
 "real pos stays false": "--ez real_pos_enabled false" in bat and "--ez real_pos_enabled true" not in bat,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.96 launch guard failed: "+", ".join(failed))
print("[OK] v0.5.96 launch guard")
