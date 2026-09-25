from pathlib import Path
import json, zipfile, re

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / "test_reports" / "sbp_channel_service_docs"
files = sorted(folder.glob("SBP_CHANNEL_SERVICE_DOCS_*.zip"), key=lambda p: p.stat().st_mtime, reverse=True)

if not files:
    print("[ANALYZE] no committed SBP_CHANNEL_SERVICE_DOCS ZIP")
    raise SystemExit(0)

zpath = files[0]
print(f"[ANALYZE] artifact={zpath.relative_to(ROOT)}")

with zipfile.ZipFile(zpath) as z:
    names=set(z.namelist())
    summary=json.loads(z.read("SUMMARY.json").decode("utf-8-sig"))
    routes=json.loads(z.read("04_route_candidates.json").decode("utf-8-sig"))
    contexts=json.loads(z.read("03_contexts.json").decode("utf-8-sig"))

    print("[SUMMARY] "+json.dumps(summary,ensure_ascii=False,sort_keys=True))
    for r in routes:
        print("[ROUTE] "+json.dumps(r,ensure_ascii=False,sort_keys=True))

    interesting_terms={"shop_verified","offline_shop_id","service_in_id","service_in_slug","sbp","sbp_low_risk","verify","verification","enable","enabled","update","create"}
    emitted=0
    for item in contexts:
        if str(item.get("term","")).lower() in interesting_terms and emitted < 80:
            print("[CONTEXT] "+json.dumps(item,ensure_ascii=False,sort_keys=True))
            emitted += 1
