from __future__ import annotations

from pathlib import Path
import html
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "test_reports" / "s3_counter_sources"
zips = sorted(REPORT_DIR.glob("S3_COUNTER_SOURCES_*.zip"))

if not zips:
    print("[SKIP] No S3 counter-source ZIP in checkout.")
    raise SystemExit(0)

zip_path = zips[-1]
print(f"[INFO] Analyzing device counter methods from {zip_path.relative_to(ROOT)}")

with zipfile.ZipFile(zip_path, "r") as zf:
    device_members = [
        name for name in zf.namelist()
        if Path(name).name == "app-controllers-iretail-devicecontroller.html"
    ]
    if not device_members:
        raise SystemExit("Device controller page not found in report ZIP")
    raw = zf.read(sorted(device_members)[0]).decode("utf-8", errors="replace")

text = re.sub(r"(?is)<script.*?</script>", " ", raw)
text = re.sub(r"(?is)<style.*?</style>", " ", text)
text = re.sub(r"(?is)<[^>]+>", " ", text)
text = html.unescape(text)
text = re.sub(r"\s+", " ", text).strip()

targets = [
    "/api/iretail/device/register",
    "/api/iretail/device/register-external-system",
    "/api/iretail/device/update-info",
]

for target in targets:
    print()
    print("=" * 80)
    print(f"[METHOD] {target}")
    positions = [m.start() for m in re.finditer(re.escape(target), text)]
    if not positions:
        print("NOT_FOUND")
        continue

    for occurrence, start in enumerate(positions[:3], 1):
        next_candidates = [
            m.start()
            for m in re.finditer(r"/api/iretail/[A-Za-z0-9_./-]+", text[start + len(target):])
        ]
        if next_candidates:
            end = start + len(target) + next_candidates[0]
        else:
            end = min(len(text), start + 7000)
        end = min(end, start + 7000)
        block = text[start:end].strip()
        print(f"[OCCURRENCE {occurrence}]")
        print(block)
        print()

print()
print("[INTERPRETATION_GUARD]")
print("This output is documentation text only. No working API call was made.")
print("A method name or documentation description is not proof of idempotency or absence of side effects.")
