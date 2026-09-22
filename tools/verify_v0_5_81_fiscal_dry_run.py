from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
fiscal = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/FiscalizationDraft.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
gateway_path = ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/FiscalGateway.kt"
gateway = gateway_path.read_text(encoding="utf-8") if gateway_path.exists() else ""
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

m = re.search(r"versionCode\s+(\d+)", gradle)

checks = {
    "versionCode at least 81": bool(m) and int(m.group(1)) >= 81,
    "dry run mode": '"DRY_RUN_ONLY"' in fiscal,
    "network actions none": '"NONE"' in fiscal,
    "send disabled": "private const val SEND_ALLOWED = false" in fiscal,
    "credentials absent": '.put("credentials_present", false)' in fiscal,
    "documented create endpoint only candidate": "cloud-fiscal/order/create" in fiscal and "CREATE_ENDPOINT_CANDIDATE" in fiscal,
    "documented status endpoint only candidate": "cloud-fiscal/order/getStatus" in fiscal and "STATUS_ENDPOINT_CANDIDATE" in fiscal,
    "card amount exact minor conversion": 'form.put("card_amount", money(order.amountMinor))' in fiscal,
    "external order id": 'form.put("external_order_id", order.externalNumber)' in fiscal,
    "discount blocker": "discount_allocation" in fiscal and "hasOrderLevelDiscount" in fiscal,
    "provider blocker": "2019 cloud-fiscal endpoint must be confirmed" in fiscal,
    "no URL class": "URL(" not in fiscal and "java.net.URL" not in fiscal,
    "no HTTP connection": "HttpURLConnection" not in fiscal and "HttpsURLConnection" not in fiscal,
    "no socket": "Socket(" not in fiscal and "java.net.Socket" not in fiscal,
    "builder wired after payment confirmation": (
        main.find("markPaymentConfirmed()") >= 0 and (
            main.find("FiscalizationDraftBuilder") > main.find("markPaymentConfirmed()") or (
                main.find("fiscalGateway.afterPaymentConfirmed(order)") > main.find("markPaymentConfirmed()") and
                "class DryRunFiscalGateway" in gateway and
                "FiscalizationDraftBuilder" in gateway
            )
        )
    ),
    "no success claim": "Фискальный чек пока не сформирован" in main,
}

failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("fiscal DRY_RUN guard failed: " + ", ".join(failed))
print(f"[OK] fiscal DRY_RUN guard: {len(checks)} checks passed")
