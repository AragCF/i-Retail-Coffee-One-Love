from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
bat=(ROOT/"MAIN_25_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
pub=(ROOT/"GIT_125_PUBLISH_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)
vm=re.search(r"versionName\s+'([^']+)'",gradle)
expected=vm.group(1) if vm else ""

checks={
    "versionCode at least 94": bool(m) and int(m.group(1))>=94,
    "versionName current": expected=="0.5.94-fiscal-selftest-script-version-fix",
    "main branch matches versionName": f'EXPECTED_BRANCH=v{expected}' in bat,
    "main expected version matches": f'EXPECTED_VERSION={expected}' in bat,
    "publisher branch matches": f'EXPECTED_BRANCH=v{expected}' in pub,
    "main banner current": "i-Retail v0.5.94 - FISCAL POSITIVE DRY_RUN SELF-TEST" in bat,
    "old v0.5.91 branch absent main": "v0.5.91-fiscal-positive-dryrun-selftest" not in bat,
    "old v0.5.91 branch absent publisher": "v0.5.91-fiscal-positive-dryrun-selftest" not in pub,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.94 script/version guard failed: "+", ".join(failed))
print(f"[OK] v0.5.94 script/version guard: {len(checks)} checks passed")
