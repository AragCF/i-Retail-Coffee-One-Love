from __future__ import annotations

from pathlib import Path
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "test_reports" / "s3_device_register"

zips = sorted(REPORT_DIR.glob("S3_DEVICE_REGISTER_PROBE_*.zip"))
if not zips:
    print("[SKIP] No S3_DEVICE_REGISTER_PROBE_*.zip in checkout.")
    raise SystemExit(0)

zip_path = zips[-1]
print(f"[INFO] Analyzing: {zip_path.relative_to(ROOT)}")

with zipfile.ZipFile(zip_path, "r") as zf:
    names = list(zf.namelist())

    def by_basename(name: str) -> str | None:
        wanted = name
        for item in names:
            normalized = item.replace("\\", "/")
            if normalized.split("/")[-1] == wanted:
                return item
        return None

    def read_text(name: str) -> str:
        member = by_basename(name)
        if member is None:
            return ""
        return zf.read(member).decode("utf-8", errors="replace")

    def read_json(name: str):
        text = read_text(name)
        if not text.strip():
            return None
        return json.loads(text)

    summary = read_json("SUMMARY.json") or {}
    register_http = read_json("30_register_http.json") or {}
    register_response = read_json("31_register_response_sanitized.json") or {}
    before = read_json("10_before_snapshot.json") or {}
    after = read_json("40_after_snapshot.json") or {}

print("[SUMMARY]")
for key in (
    "mode",
    "contract_version",
    "register_calls",
    "register_retry_allowed",
    "config_update_allowed",
    "order_send_allowed",
    "register_outcome",
    "register_http_code",
    "register_curl_exit",
    "register_api_status",
    "returned_device_id",
    "returned_type_slug",
    "returned_channel_id",
    "returned_counters",
    "returned_shift",
    "configured_device_id",
    "device_ids_before",
    "device_ids_after",
    "new_device_ids",
    "returned_device_is_new",
    "returned_type_is_cashbox",
    "automatic_device_binding",
):
    if key in summary:
        print(f"{key}={json.dumps(summary[key], ensure_ascii=False, sort_keys=True)}")

print()
print("[REGISTER_HTTP]")
for key in ("curl_exit","http_code","content_type","time_total","remote_ip","url_effective","stderr"):
    if key in register_http:
        print(f"{key}={json.dumps(register_http[key], ensure_ascii=False)}")

print()
print("[REGISTER_RESPONSE_SANITIZED]")
print(json.dumps(register_response, ensure_ascii=False, sort_keys=True, indent=2))

print()
print("[BEFORE]")
print(json.dumps({
    "device_ids": before.get("device_ids"),
    "queried_device_ids": before.get("queried_device_ids"),
    "device_checks": before.get("device_checks"),
}, ensure_ascii=False, sort_keys=True, indent=2))

print()
print("[AFTER]")
print(json.dumps({
    "device_ids": after.get("device_ids"),
    "queried_device_ids": after.get("queried_device_ids"),
    "device_checks": after.get("device_checks"),
}, ensure_ascii=False, sort_keys=True, indent=2))

before_ids = before.get("device_ids") or []
after_ids = after.get("device_ids") or []

print()
print("[DIFF]")
print("device_ids_changed=" + str(before_ids != after_ids))
print("added_device_ids=" + json.dumps([x for x in after_ids if x not in before_ids], ensure_ascii=False))
print("removed_device_ids=" + json.dumps([x for x in before_ids if x not in after_ids], ensure_ascii=False))

print()
print("[SAFETY]")
print("No I-Retail API call was made by this analyzer.")
print("This job reads only the committed ZIP report.")
