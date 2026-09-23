from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
bat=(ROOT/"MAIN_25_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
pub=(ROOT/"GIT_125_PUBLISH_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

checks={
    "versionCode 95+": bool(re.search(r"versionCode\s+(9[5-9]|[1-9]\d{2,})",gradle)),
    "current versionName": "versionName '0.5.95-fiscal-selftest-versionname-fix'" in gradle,
    "main current branch": 'EXPECTED_BRANCH=v0.5.95-fiscal-selftest-versionname-fix' in bat,
    "main current version": 'EXPECTED_VERSION=0.5.95-fiscal-selftest-versionname-fix' in bat,
    "publisher current branch": 'EXPECTED_BRANCH=v0.5.95-fiscal-selftest-versionname-fix' in pub,
    "banner current": "i-Retail v0.5.95 - FISCAL POSITIVE DRY_RUN SELF-TEST" in bat,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.95 versionName fix guard failed: "+", ".join(failed))
print(f"[OK] v0.5.95 versionName fix guard: {len(checks)} checks passed")
