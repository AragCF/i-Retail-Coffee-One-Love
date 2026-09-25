from pathlib import Path
import json, zipfile

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / "test_reports" / "sbp_direct_services"
files = sorted(folder.glob("SBP_DIRECT_SERVICES_*.zip"), key=lambda p: p.stat().st_mtime, reverse=True)

if not files:
    print("[ANALYZE] no committed SBP_DIRECT_SERVICES ZIP")
    raise SystemExit(0)

zpath = files[0]
print(f"[ANALYZE] artifact={zpath.relative_to(ROOT)}")

with zipfile.ZipFile(zpath) as z:
    names=set(z.namelist())

    def read_json(name):
        if name not in names:
            return None
        raw=z.read(name).decode("utf-8-sig")
        return json.loads(raw) if raw.strip() else None

    summary=read_json("SUMMARY.json") or {}
    available=read_json("10_channel_available_services_sanitized.json")
    used=read_json("11_profile_used_services_sanitized.json")
    all_services=read_json("12_all_services_sanitized.json")
    recent=read_json("13_recent_payments_in_sanitized.json")
    sbp_available=read_json("20_available_sbp_services.json") or []
    sbp_used=read_json("21_used_sbp_services.json") or []
    sbp_known=read_json("22_known_sbp_services.json") or []

    print("[SUMMARY] "+json.dumps(summary,ensure_ascii=False,sort_keys=True))
    print("[SBP_AVAILABLE] "+json.dumps(sbp_available,ensure_ascii=False,sort_keys=True))
    print("[SBP_USED] "+json.dumps(sbp_used,ensure_ascii=False,sort_keys=True))
    print("[SBP_KNOWN] "+json.dumps(sbp_known,ensure_ascii=False,sort_keys=True))
    print("[AVAILABLE_RESPONSE] "+json.dumps(available,ensure_ascii=False,sort_keys=True))
    print("[USED_RESPONSE] "+json.dumps(used,ensure_ascii=False,sort_keys=True))
    print("[RECENT_PAYMENTS_RESPONSE] "+json.dumps(recent,ensure_ascii=False,sort_keys=True))

    if isinstance(available,dict):
        status=available.get("status")
        result=available.get("result")
        if status is True:
            print("[DIAG] available-services API status=true")
        else:
            print("[DIAG] available-services API status is not true")
        if isinstance(result,dict):
            print("[DIAG] available result keys="+",".join(sorted(result.keys())))
        elif isinstance(result,list):
            print(f"[DIAG] available result list size={len(result)}")

    if isinstance(recent,dict) and recent.get("status") is False:
        r=recent.get("result") or {}
        if isinstance(r,dict):
            print("[DIAG] get-payments-in rejected: title=%s code=%s params=%s" % (
                r.get("title"), r.get("code"), json.dumps(r.get("params"),ensure_ascii=False,sort_keys=True)
            ))
