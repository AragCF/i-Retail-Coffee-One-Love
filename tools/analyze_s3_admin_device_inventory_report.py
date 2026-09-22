from __future__ import annotations

from pathlib import Path
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "test_reports" / "s3_admin_device_inventory"
zips = sorted(REPORT_DIR.glob("S3_ADMIN_DEVICE_INVENTORY_*.zip"))
if not zips:
    print("[SKIP] No admin-device inventory ZIP.")
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

    summary = read_json("SUMMARY.json") or {}
    inventory = read_json("80_inventory.json") or []
    results = read_json("90_results.json") or []

    print("[SUMMARY]")
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True, indent=2))

    print()
    print("[INVENTORY]")
    print(json.dumps(inventory, ensure_ascii=False, sort_keys=True, indent=2))

    print()
    print("[RESULTS]")
    print(json.dumps(results, ensure_ascii=False, sort_keys=True, indent=2))

    interesting = []
    for name in names:
        base = name.replace("\\", "/").split("/")[-1]
        if base.endswith("_sanitized.json") and (
            "admin_count" in base or
            "admin_find" in base or
            "admin_devices_in_orders" in base or
            "admin_device_6287" in base or
            "admin_device_3476" in base
        ):
            interesting.append(base)

    print()
    print("[INTERESTING_SAFE_RESPONSES]")
    for base in sorted(interesting):
        data = read_json(base)
        print("=" * 80)
        print(base)
        print(json.dumps(data, ensure_ascii=False, sort_keys=True, indent=2))

print()
print("[INTERPRETATION_HINTS]")
print("1) If admin find/count are permission denied, absence from those lists is not evidence of nonexistence.")
print("2) Direct get-device-info success for 6287/3476 is stronger evidence that those IDs exist.")
print("3) Type extraction must follow actual response nesting; blank type in the first audit may be a parser issue.")
print("4) No I-Retail API call is made by this analyzer.")
