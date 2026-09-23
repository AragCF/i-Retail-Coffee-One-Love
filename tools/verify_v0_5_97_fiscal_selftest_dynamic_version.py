from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
bat = (ROOT / "MAIN_25_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
pub = (ROOT / "GIT_125_PUBLISH_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

checks = {
    "versionCode at least 97": bool(re.search(r"versionCode\s+(9[7-9]|[1-9]\d{2,})", gradle)),
    "current versionName": "versionName '0.5.97-fiscal-selftest-dynamic-version'" in gradle,
    "dynamic version extraction": 'findstr /C:"versionName "' in bat and 'set "EXPECTED_VERSION="' in bat,
    "single quotes stripped": "EXPECTED_VERSION:'=" in bat,
    "no hardcoded main branch": "EXPECTED_BRANCH=" not in bat,
    "no hardcoded publisher branch": "EXPECTED_BRANCH=" not in pub,
    "validation failure archived": "FISCAL_DRYRUN_SELFTEST_VALIDATION_FAILED" in bat,
    "validation failure published": "Diagnostic ZIP was published for analysis" in bat,
    "generic publisher commit": "test: fiscal positive dryrun selftest" in pub,
}
failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("v0.5.97 dynamic version guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.97 dynamic version guard: {len(checks)} checks passed")
