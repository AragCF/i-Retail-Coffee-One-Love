from __future__ import annotations

from pathlib import Path
import html
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CODE_DIR = ROOT / "test_reports" / "s3_device_code_source"
DOC_DIR = ROOT / "test_reports" / "s3_counter_sources"

def latest(pattern_dir: Path, pattern: str) -> Path | None:
    items = sorted(pattern_dir.glob(pattern))
    return items[-1] if items else None

def member_by_basename(zf: zipfile.ZipFile, basename: str) -> str | None:
    for name in zf.namelist():
        if name.replace("\\", "/").split("/")[-1] == basename:
            return name
    return None

def read_json_from_zip(path: Path, basename: str):
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

code_zip = latest(CODE_DIR, "S3_DEVICE_CODE_SOURCE_*.zip")
docs_zip = latest(DOC_DIR, "S3_COUNTER_SOURCES_*.zip")

if code_zip is None:
    print("[SKIP] No device-code source ZIP.")
    raise SystemExit(0)
if docs_zip is None:
    print("[SKIP] No counter-source documentation ZIP.")
    raise SystemExit(0)

print(f"[DEVICE_CODE_REPORT] {code_zip.relative_to(ROOT)}")
summary = read_json_from_zip(code_zip, "SUMMARY.json") or {}
observations = read_json_from_zip(code_zip, "DEVICE_CODE_OBSERVATIONS.json") or []
if isinstance(observations, dict):
    observations = [observations]

for key in (
    "configured_device_code_equals_device_id",
    "configured_device_code_length",
    "configured_device_id_length",
    "devices_found",
    "device_ids",
    "register_calls",
    "order_send_allowed",
    "config_update_allowed",
):
    if key in summary:
        print(f"{key}={json.dumps(summary[key], ensure_ascii=False)}")

print()
print("[DEVICE_CODE_OBSERVATIONS]")
for item in observations:
    safe = {
        "device_id": item.get("device_id"),
        "device_type": item.get("device_type"),
        "server_code_present": item.get("server_code_present"),
        "server_code_length": item.get("server_code_length"),
        "server_code_matches_config_device_code": item.get("server_code_matches_config_device_code"),
        "server_code_equals_device_id": item.get("server_code_equals_device_id"),
        "external_code_present": item.get("external_code_present"),
        "external_code_length": item.get("external_code_length"),
        "external_code_matches_config_device_code": item.get("external_code_matches_config_device_code"),
    }
    print(json.dumps(safe, ensure_ascii=False, sort_keys=True))

print()
print(f"[DOCUMENTATION_REPORT] {docs_zip.relative_to(ROOT)}")

endpoint_hits = {}
contexts = []
with zipfile.ZipFile(docs_zip, "r") as zf:
    for name in zf.namelist():
        normalized = name.replace("\\", "/").split("/")[-1]
        if not (normalized.startswith("app-controllers-iretail-") and normalized.endswith("controller.html")):
            continue

        raw = zf.read(name).decode("utf-8", errors="replace")
        text = html_to_text(raw)
        if "external_code" not in text.lower():
            continue

        endpoint_matches = list(re.finditer(r"/api/iretail/[A-Za-z0-9_./-]+", text, flags=re.I))
        term_matches = list(re.finditer(r"\bexternal_code\b", text, flags=re.I))

        for tm in term_matches:
            nearest = None
            nearest_dist = None
            for em in endpoint_matches:
                dist = abs(tm.start() - em.start())
                if em.start() <= tm.start():
                    dist //= 2
                if nearest_dist is None or dist < nearest_dist:
                    nearest = em
                    nearest_dist = dist

            endpoint = nearest.group(0) if nearest else "<none>"
            endpoint_hits.setdefault(endpoint, set()).add(normalized)

            start = max(0, tm.start() - 900)
            end = min(len(text), tm.start() + 1800)
            contexts.append((endpoint, normalized, text[start:end]))

print("[EXTERNAL_CODE_ENDPOINTS]")
for endpoint in sorted(endpoint_hits):
    pages = ",".join(sorted(endpoint_hits[endpoint]))
    print(f"{endpoint} | pages={pages}")

print()
for target in (
    "/api/iretail/device/get-device-info",
    "/api/iretail/device/register-external-system",
    "/api/iretail/device/register",
):
    print("=" * 80)
    print(f"[TARGET] {target}")
    matches = [(page, ctx) for endpoint, page, ctx in contexts if endpoint == target]
    if not matches:
        print("NO_EXTERNAL_CODE_CONTEXT")
        continue
    for page, ctx in matches[:3]:
        print(f"PAGE={page}")
        print(ctx)
        print()

print("[INTERPRETATION_GUARD]")
print("This analyzer performs no I-Retail API requests.")
print("It reads only committed ZIP evidence and documentation.")
