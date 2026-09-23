from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
contract=(ROOT/"docs/S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.0.md").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
m=re.search(r"versionCode\s+(\d+)",gradle)

checks={
    "versionCode at least 90": bool(m) and int(m.group(1))>=90,
    "contract proposed": "PROPOSED_NOT_APPROVED" in contract,
    "exactly one payment": "Ровно одна попытка" in contract,
    "human initiates": "только человеком" in contract,
    "retry forbidden": "автоматический retry запрещён" in contract,
    "uncertain blocks retry": "UNCERTAIN" in contract and "повтор запрещён" in contract,
    "fiscal send disabled": "sendAllowed=false" in contract and "network_actions = NONE" in contract,
    "order sync forbidden": "iretail/order/synchronize" in contract and "Жёстко запрещено" in contract,
    "standalone retained": "machine_mode" in contract and "standalone" in contract,
    "real POS restored false": "real_pos_enabled" in contract and "false" in contract,
    "no executable positive script yet": not (ROOT/"MAIN_25_FISCAL_POSITIVE_PAYMENT_TEST.bat").exists(),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.90 contract guard failed: "+", ".join(failed))
print(f"[OK] v0.5.90 contract guard: {len(checks)} checks passed")
