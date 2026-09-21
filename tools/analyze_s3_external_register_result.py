from __future__ import annotations

from pathlib import Path
import html
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXT_DIR = ROOT / "test_reports" / "s3_external_register"
ORD_DIR = ROOT / "test_reports" / "s3_device_register"
DOC_DIR = ROOT / "test_reports" / "s3_counter_sources"

def latest(folder: Path, pattern: str) -> Path | None:
    items = sorted(folder.glob(pattern))
    return items[-1] if items else None

def member_by_basename(zf: zipfile.ZipFile, basename: str) -> str | None:
    for name in zf.namelist():
        if name.replace("\\", "/").split("/")[-1] == basename:
            return name
    return None

def read_json(path: Path, basename: str):
    with zipfile.ZipFile(path, "r") as zf:
        member = member_by_basename(zf, basename)
        if member is None:
            return None
        return json.loads(zf.read(member).decode("utf-8", errors="replace"))

def html_to_text(raw: str) -> str:
    value = re.sub(r"(?is)<script.*?</script>", " ", raw)
    value = re.sub(r"(?is)<style.*?</style>", " ", value)
    value = re.sub(r"(?is)<[^>]+>", " ", value)
    value = html.unescape(value)
    return re.sub(r"\s+", " ", value).strip()

ext_zip = latest(EXT_DIR, "S3_EXTERNAL_REGISTER_PROBE_*.zip")
ord_zip = latest(ORD_DIR, "S3_DEVICE_REGISTER_PROBE_*.zip")
docs_zip = latest(DOC_DIR, "S3_COUNTER_SOURCES_*.zip")

if ext_zip is None:
    print("[SKIP] external register ZIP missing")
    raise SystemExit(0)

ext_summary = read_json(ext_zip, "SUMMARY.json") or {}
ext_http = read_json(ext_zip, "30_external_register_http.json") or {}
ext_resp = read_json(ext_zip, "31_external_register_response_sanitized.json") or {}
ext_before = read_json(ext_zip, "10_before_snapshot.json") or {}
ext_after = read_json(ext_zip, "40_after_snapshot.json") or {}

print(f"[EXTERNAL_REPORT] {ext_zip.relative_to(ROOT)}")
print("[EXTERNAL_SUMMARY]")
for key in (
    "mode","contract_version","source_device_id","source_external_code_present",
    "source_external_code_length","source_external_code_saved",
    "external_register_calls","external_register_retry_allowed",
    "config_update_allowed","order_send_allowed",
    "external_register_outcome","register_http_code","register_curl_exit",
    "register_api_status","returned_device_id","returned_type_slug",
    "returned_channel_id","returned_device_inner_id","returned_counters",
    "device_ids_before","device_ids_after","new_device_ids",
    "returned_device_is_new","returned_type_is_cashbox","automatic_device_binding",
):
    if key in ext_summary:
        print(f"{key}={json.dumps(ext_summary[key], ensure_ascii=False, sort_keys=True)}")

print()
print("[EXTERNAL_HTTP]")
print(json.dumps(ext_http, ensure_ascii=False, sort_keys=True, indent=2))
print()
print("[EXTERNAL_RESPONSE_SANITIZED]")
print(json.dumps(ext_resp, ensure_ascii=False, sort_keys=True, indent=2))
print()
print("[EXTERNAL_BEFORE_AFTER]")
print("before=" + json.dumps({
    "device_ids": ext_before.get("device_ids"),
    "device_checks": ext_before.get("device_checks"),
}, ensure_ascii=False, sort_keys=True))
print("after=" + json.dumps({
    "device_ids": ext_after.get("device_ids"),
    "device_checks": ext_after.get("device_checks"),
}, ensure_ascii=False, sort_keys=True))

if ord_zip is not None:
    ord_summary = read_json(ord_zip, "SUMMARY.json") or {}
    ord_resp = read_json(ord_zip, "31_register_response_sanitized.json") or {}
    print()
    print(f"[ORDINARY_REPORT] {ord_zip.relative_to(ROOT)}")
    print("ordinary_outcome=" + json.dumps(ord_summary.get("register_outcome"), ensure_ascii=False))
    print("ordinary_api_status=" + json.dumps(ord_summary.get("register_api_status"), ensure_ascii=False))
    print("ordinary_response=" + json.dumps(ord_resp, ensure_ascii=False, sort_keys=True))
    print("same_response_shape=" + str(sorted(ord_resp.keys()) == sorted(ext_resp.keys())))
    on = ((ord_resp.get("result") or {}).get("number") if isinstance(ord_resp, dict) else None)
    en = ((ext_resp.get("result") or {}).get("number") if isinstance(ext_resp, dict) else None)
    print("ordinary_error_number=" + json.dumps(on, ensure_ascii=False))
    print("external_error_number=" + json.dumps(en, ensure_ascii=False))
    print("same_error_number=" + str(on is not None and en is not None and on == en))

if docs_zip is not None:
    print()
    print(f"[DEVICE_CONTROLLER_DOCS] {docs_zip.relative_to(ROOT)}")
    with zipfile.ZipFile(docs_zip, "r") as zf:
        member = member_by_basename(zf, "app-controllers-iretail-devicecontroller.html")
        if member:
            text = html_to_text(zf.read(member).decode("utf-8", errors="replace"))
            endpoints = []
            for m in re.finditer(r"/api/iretail/device/[A-Za-z0-9_./-]+", text):
                ep = m.group(0).rstrip(".,;:)]}")
                if ep not in endpoints:
                    endpoints.append(ep)
            print("[DEVICE_ENDPOINTS]")
            for ep in endpoints:
                print(ep)

            terms = [
                "create", "register", "register-external-system",
                "get-by-channel-id", "get-device-info",
                "workplace_cashier", "self_service_terminal",
                "coffee_machine", "external_code", "device_code"
            ]
            print()
            print("[RELEVANT_CONTEXTS]")
            for term in terms:
                matches = list(re.finditer(re.escape(term), text, flags=re.I))
                print("=" * 80)
                print("[TERM] " + term)
                if not matches:
                    print("NOT_FOUND")
                    continue
                for m in matches[:3]:
                    start = max(0, m.start() - 850)
                    end = min(len(text), m.start() + 1800)
                    print(text[start:end])
                    print()

print("[SAFETY]")
print("No I-Retail API request was made. Only committed ZIP evidence and docs were read.")
