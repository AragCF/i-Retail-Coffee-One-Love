from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
contract = (ROOT / "docs/S3_EXTERNAL_SYSTEM_REGISTER_CONTROLLED_PROBE_CONTRACT_v1.0.0.md").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
m = re.search(r"versionCode\s+(\d+)", gradle)

checks = {
    "versionCode at least 69": bool(m) and int(m.group(1)) >= 69,
    "contract proposed": "PROPOSED_NOT_APPROVED" in contract,
    "explicit new approval text": "Одобряю один пробный register-external-system" in contract,
    "one call maximum": "ровно один" in contract.lower(),
    "external code never published": "`external_code` не попадает в консоль, Git или ZIP" in contract,
    "retry disabled": "curl retry=0" in contract,
    "ordinary register forbidden": "обычный `device/register` повторно запрещён" in contract,
    "order synchronize forbidden": "`order/synchronize` запрещён" in contract,
    "payments forbidden": "платежи запрещены" in contract,
    "uncertain result stops retry": "EXTERNAL_REGISTER_RESULT_UNCERTAIN" in contract and "повтор `register-external-system` запрещён" in contract,
}

failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("external register contract gate failed: " + ", ".join(failed))
print(f"[OK] external register contract gate: {len(checks)} checks passed")
