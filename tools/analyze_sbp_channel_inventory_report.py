from pathlib import Path
import json, zipfile

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / "test_reports" / "sbp_channel_inventory"
files = sorted(folder.glob("SBP_CHANNEL_INVENTORY_*.zip"), key=lambda p: p.stat().st_mtime, reverse=True)

if not files:
    print("[ANALYZE] no committed SBP_CHANNEL_INVENTORY ZIP")
    raise SystemExit(0)

zpath = files[0]
print(f"[ANALYZE] artifact={zpath.relative_to(ROOT)}")

with zipfile.ZipFile(zpath) as z:
    def load(name):
        raw=z.read(name).decode("utf-8-sig")
        return json.loads(raw) if raw.strip() else None

    summary=load("SUMMARY.json") or {}
    rows=load("20_channel_inventory.json") or []
    print("[SUMMARY] "+json.dumps(summary,ensure_ascii=False,sort_keys=True))
    for row in rows:
        print("[CHANNEL] "+json.dumps(row,ensure_ascii=False,sort_keys=True))
