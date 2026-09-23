from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
bat = (ROOT / "MAIN_25_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
pub = (ROOT / "GIT_125_PUBLISH_FISCAL_DRYRUN_SELFTEST.bat").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

m = re.search(r"versionCode\s+(\d+)", gradle)
checks = {
    "versionCode at least 95": bool(m) and int(m.group(1)) >= 95,
    "main has no hardcoded branch": "EXPECTED_BRANCH=" not in bat,
    "publisher has no hardcoded branch": "EXPECTED_BRANCH=" not in pub,
    "publisher reads current branch": "git branch --show-current" in pub,
    "publisher rejects detached HEAD": "Detached HEAD is not supported" in pub,
}
failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("publication guard failed: " + ", ".join(failed))
print(f"[OK] publication guard: {len(checks)} checks passed")
