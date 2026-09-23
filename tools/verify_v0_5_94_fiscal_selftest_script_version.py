from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
bat = (ROOT / "MAIN_25_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

m = re.search(r"versionCode\s+(\d+)", gradle)
checks = {
    "versionCode at least 94": bool(m) and int(m.group(1)) >= 94,
    "versionName read dynamically": 'findstr /C:"versionName "' in bat,
    "build.gradle source used": '"app\\build.gradle"' in bat,
    "no hardcoded EXPECTED_BRANCH": "EXPECTED_BRANCH=" not in bat,
    "expected version starts empty": 'set "EXPECTED_VERSION="' in bat,
}
failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("dynamic version guard failed: " + ", ".join(failed))
print(f"[OK] dynamic version guard: {len(checks)} checks passed")
