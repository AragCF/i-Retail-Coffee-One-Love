from __future__ import annotations

from pathlib import Path
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "test_reports" / "s3_counter_sources"

zips = sorted(REPORT_DIR.glob("S3_COUNTER_SOURCES_*.zip"))
if not zips:
    print("[SKIP] No S3_COUNTER_SOURCES_*.zip is present in this checkout.")
    raise SystemExit(0)

zip_path = zips[-1]
print(f"[INFO] Analyzing: {zip_path.relative_to(ROOT)}")

with zipfile.ZipFile(zip_path, "r") as zf:
    names = set(zf.namelist())

    def find_member(basename: str) -> str | None:
        matches = [name for name in names if Path(name).name == basename]
        if not matches:
            return None
        return sorted(matches)[0]

    def read_text(basename: str) -> str:
        member = find_member(basename)
        if member is None:
            return ""
        return zf.read(member).decode("utf-8", errors="replace")

    def read_json(basename: str):
        text = read_text(basename)
        if not text.strip():
            return None
        return json.loads(text)

    summary = read_json("SUMMARY.json") or {}
    read_only = read_json("08_read_only_name_candidates.json") or []
    state_change = read_json("09_state_change_name_candidates.json") or []
    hits = read_json("06_counter_hits.json") or []
    contexts_text = read_text("07_counter_contexts.txt")

if isinstance(read_only, dict):
    read_only = [read_only]
if isinstance(state_change, dict):
    state_change = [state_change]
if isinstance(hits, dict):
    hits = [hits]

print("[SUMMARY]")
for key in (
    "discovered_iretail_pages",
    "downloaded_pages",
    "failed_pages",
    "unique_counter_hits",
    "read_only_name_candidates",
    "state_change_name_candidates",
    "network_actions",
    "working_api_calls",
    "device_register_called",
    "order_synchronize_called",
):
    if key in summary:
        print(f"{key}={summary[key]}")

print()
print("[READ_ONLY_NAME_CANDIDATES]")
if not read_only:
    print("NONE")
else:
    for idx, item in enumerate(read_only, 1):
        print(
            f"{idx}. endpoint={item.get('nearest_endpoint','')} "
            f"term={item.get('term','')} page={item.get('page','')}"
        )

print()
print("[STATE_CHANGE_NAME_CANDIDATES]")
unique_state = []
seen_state = set()
for item in state_change:
    key = (item.get("nearest_endpoint",""), item.get("term",""))
    if key in seen_state:
        continue
    seen_state.add(key)
    unique_state.append(item)
for idx, item in enumerate(unique_state, 1):
    print(
        f"{idx}. endpoint={item.get('nearest_endpoint','')} "
        f"term={item.get('term','')} page={item.get('page','')}"
    )

blocks = [block.strip() for block in contexts_text.split("----") if block.strip()]

print()
print("[READ_ONLY_CONTEXTS]")
for idx, candidate in enumerate(read_only, 1):
    endpoint = str(candidate.get("nearest_endpoint",""))
    term = str(candidate.get("term",""))
    matching = [
        block for block in blocks
        if f"TERM={term}" in block and f"ENDPOINT={endpoint}" in block
    ]
    print(f"--- candidate {idx}: {endpoint} / {term} ---")
    if not matching:
        print("NO_MATCHING_CONTEXT")
        continue
    for block in matching[:3]:
        print(block[:5000])
        print()

print("[COUNTER_HITS_BY_ENDPOINT]")
grouped = {}
for item in hits:
    endpoint = item.get("nearest_endpoint","") or "<none>"
    grouped.setdefault(endpoint, set()).add(item.get("term",""))
for endpoint in sorted(grouped):
    terms = ",".join(sorted(x for x in grouped[endpoint] if x))
    print(f"{endpoint}: {terms}")
