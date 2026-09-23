from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
bat=(ROOT/"MAIN_25_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
pub=(ROOT/"GIT_125_PUBLISH_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
vm=re.search(r"versionName\s+'([^']+)'",gradle)
expected=vm.group(1) if vm else ""
checks={
 "versionCode at least 95": bool(re.search(r"versionCode\s+(9[5-9]|[1-9]\d{2,})",gradle)),
 "versionName present": bool(expected),
 "main branch tracks versionName": f'EXPECTED_BRANCH=v{expected}' in bat,
 "main expected version tracks versionName": f'EXPECTED_VERSION={expected}' in bat,
 "publisher branch tracks versionName": f'EXPECTED_BRANCH=v{expected}' in pub,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("self-test version invariant failed: "+", ".join(failed))
print("[OK] self-test version invariant")
