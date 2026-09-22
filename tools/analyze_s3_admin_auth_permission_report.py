from __future__ import annotations

from pathlib import Path
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "test_reports" / "s3_admin_auth_permission"
zips = sorted(REPORT_DIR.glob("S3_ADMIN_AUTH_PERMISSION_*.zip"))
if not zips:
    print("[SKIP] No S3_ADMIN_AUTH_PERMISSION_*.zip")
    raise SystemExit(0)

path = zips[-1]
print(f"[REPORT] {path.relative_to(ROOT)}")

with zipfile.ZipFile(path, "r") as zf:
    names = list(zf.namelist())

    def member(basename: str):
        for name in names:
            if name.replace("\\", "/").split("/")[-1] == basename:
                return name
        return None

    def read_json(basename: str):
        m = member(basename)
        if not m:
            return None
        return json.loads(zf.read(m).decode("utf-8", errors="replace"))

    for basename in (
        "SUMMARY.json",
        "10_ordinary_auth_sanitized.json",
        "11_admin_auth_sanitized.json",
        "20_ordinary_permissions_sanitized.json",
        "21_admin_permissions_sanitized.json",
        "21_admin_permissions_skipped.json",
        "22_admin_profiles_sanitized.json",
        "22_admin_profiles_skipped.json",
        "30_admin_device_find_sanitized.json",
        "30_admin_device_find_skipped.json",
    ):
        data = read_json(basename)
        if data is None:
            continue
        print("=" * 90)
        print(basename)
        print(json.dumps(data, ensure_ascii=False, sort_keys=True, indent=2))

print("[SAFETY]")
print("No I-Retail API request was made by this analyzer.")
