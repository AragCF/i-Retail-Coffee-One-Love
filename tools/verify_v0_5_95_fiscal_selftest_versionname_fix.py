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
    "versionCode at least 95": bool(m) and int(m.group(1))>=95,
    "versionName present": bool(expected),
    "main branch matches current versionName": f"EXPECTED_BRANCH=v{expected}" in bat,
    "main expected version matches current versionName": f"EXPECTED_VERSION={expected}" in bat,
    "publisher branch matches current versionName": f"EXPECTED_BRANCH=v{expected}" in pub,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("fiscal self-test versionName sync failed: "+", ".join(failed))
print(f"[OK] fiscal self-test versionName sync: {len(checks)} checks passed")
