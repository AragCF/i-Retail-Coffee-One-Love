from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
contract = (ROOT / "docs/S3_DEVICE_REGISTER_CONTROLLED_PROBE_CONTRACT_v1.0.1.md").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

version_match = re.search(r"versionCode\s+(\d+)", gradle)

checks = {
    "contract version 1.0.1": "**Версия контракта:** 1.0.1" in contract,
    "contract is proposed, not approved": "PROPOSED_NOT_APPROVED" in contract,
    "explicit approval required": "явное одобрение именно этого контракта" in contract,
    "single register call": "Ровно **один** вызов" in contract,
    "uncertain result forbids retry": "REGISTER_RESULT_UNCERTAIN" in contract and "повторный `device/register` запрещён" in contract,
    "get-current forbidden": "`shift/get-current`" in contract and "допускает создание смены" in contract,
    "order synchronize forbidden": "`order/synchronize`" in contract and "остаётся запрещён" in contract,
    "no rollback fiction": "автоматический откат не предусматривается" in contract,
    "cashier type documented": "`workplace_cashier`" in contract,
    "self-service type documented": "`self_service_terminal`" in contract,
    "coffee machine distinction explicit": "`coffee_machine`" in contract and "нельзя автоматически отождествлять" in contract,
    "no automatic config rewrite": "не записываются в рабочую конфигурацию" in contract,
    "versionCode at least 63": bool(version_match) and int(version_match.group(1)) >= 63,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
if failed:
    raise SystemExit("device/register contract 1.0.1 gate failed: " + ", ".join(failed))
print(f"[OK] device/register contract 1.0.1 gate: {len(checks)} checks passed")
