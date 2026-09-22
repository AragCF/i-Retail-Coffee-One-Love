from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
gateway = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/FiscalGateway.kt").read_text(encoding="utf-8")
draft = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/FiscalizationDraft.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

m = re.search(r"versionCode\s+(\d+)", gradle)

checks = {
    "versionCode at least 82": bool(m) and int(m.group(1)) >= 82,
    "FiscalGateway interface": "interface FiscalGateway" in gateway,
    "provider-neutral states": all(x in gateway for x in ["DRAFT_READY","SUBMITTED","FISCALIZED","FAILED","UNCERTAIN"]),
    "only dry-run implementation": "class DryRunFiscalGateway" in gateway,
    "dry run delegates builder": "FiscalizationDraftBuilder" in gateway,
    "no URL in gateway": "URL(" not in gateway and "java.net.URL" not in gateway,
    "no HTTP in gateway": "HttpURLConnection" not in gateway and "HttpsURLConnection" not in gateway,
    "no socket in gateway": "Socket(" not in gateway,
    "main uses interface": "private lateinit var fiscalGateway: FiscalGateway" in main,
    "main initializes dry-run provider": "fiscalGateway = DryRunFiscalGateway(this)" in main,
    "main invokes after confirmed payment": "fiscalGateway.afterPaymentConfirmed(order)" in main,
    "draft remains send disabled": "private const val SEND_ALLOWED = false" in draft,
    "receipt remains unclaimed": 'Фискальный чек пока не сформирован' in main,
}

failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("fiscal adapter boundary guard failed: " + ", ".join(failed))
print(f"[OK] fiscal adapter boundary guard: {len(checks)} checks passed")
