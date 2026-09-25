from pathlib import Path
import json, zipfile, re

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / "test_reports" / "sbp_server_config_docs"
files = sorted(folder.glob("SBP_SERVER_CONFIG_DOCS_*.zip"), key=lambda p: p.stat().st_mtime, reverse=True)

if not files:
    print("[ANALYZE] no committed SBP_SERVER_CONFIG_DOCS ZIP")
    raise SystemExit(0)

zpath = files[0]
print(f"[ANALYZE] artifact={zpath.relative_to(ROOT)}")

with zipfile.ZipFile(zpath) as z:
    names=set(z.namelist())

    def load_json(name):
        if name not in names:
            return None
        return json.loads(z.read(name).decode("utf-8-sig"))

    summary=load_json("SUMMARY.json") or {}
    pages=load_json("01_pages.json") or []
    routes=load_json("03_routes.json") or []
    mutations=load_json("04_mutating_candidates.json") or []
    contexts=z.read("02_contexts.txt").decode("utf-8-sig") if "02_contexts.txt" in names else ""

    print("[SUMMARY] "+json.dumps(summary,ensure_ascii=False,sort_keys=True))
    print("[PAGES_OK] "+json.dumps([p for p in pages if str(p.get("http_code"))=="200"],ensure_ascii=False,sort_keys=True))
    print("[MUTATING_CANDIDATES] "+json.dumps(mutations,ensure_ascii=False,sort_keys=True))

    interesting_routes=[]
    for row in routes:
        route=str(row.get("route",""))
        if re.search(r"(shop|channel|service|profile|trade-point).*(create|update|save|edit|enable|verify|activate|bind|attach)|(?:create|update|save|edit|enable|verify|activate|bind|attach).*(shop|channel|service|profile|trade-point)",route,re.I):
            interesting_routes.append(row)
    print("[INTERESTING_ROUTES] "+json.dumps(interesting_routes,ensure_ascii=False,sort_keys=True))

    # Small context excerpts for operator/configuration decisions.
    for needle in ["verified","enable","online shop","offline_shop","lock_service","sbp","service_in"]:
        idx=contexts.lower().find(needle.lower())
        if idx >= 0:
            excerpt=contexts[max(0,idx-500):idx+1600].replace("\r"," ").replace("\n"," ")
            print(f"[CONTEXT:{needle}] {excerpt}")
