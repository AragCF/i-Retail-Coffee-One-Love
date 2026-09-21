from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
draft = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/OrderSyncDraft.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
models = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/Models.kt").read_text(encoding="utf-8")
gateway = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/IntegrationGateways.kt").read_text(encoding="utf-8")
evidence = (ROOT / "app/src/main/assets/content/s3-order-evidence.json").read_text(encoding="utf-8")

checks = {
    "dry-run mode remains explicit": '"DRY_RUN_ONLY"' in draft,
    "v2 schema is explicit": '"S3_DRY_RUN_V2"' in draft,
    "network send is explicitly disabled": '.put("send_allowed", false)' in draft,
    "network actions are none": '.put("network_actions", "NONE")' in draft,
    "documented synchronize endpoint is named": '"iretail/order/synchronize"' in draft,
    "wire top device remains unresolved": '.put("device_id", JSONObject.NULL)' in draft,
    "wire counters remain unresolved": '.put("order_counter", JSONObject.NULL)' in draft and '.put("operation_counter", JSONObject.NULL)' in draft and '.put("refund_counter", JSONObject.NULL)' in draft,
    "wire shift remains unresolved": '.put("check_counter", JSONObject.NULL)' in draft,
    "employee is not guessed into wire order": '.put("employee_id", JSONObject.NULL)' in draft,
    "service slug is not guessed into wire order": '.put("service_in_slug", JSONObject.NULL)' in draft,
    "order status is not guessed": '.put("order_status_id", JSONObject.NULL)' in draft,
    "payment status is not guessed": '.put("payment_status_id", JSONObject.NULL)' in draft,
    "order number is not guessed": '.put("order_number", JSONObject.NULL)' in draft,
    "offer id mapping is not guessed": '.put("offer_id", JSONObject.NULL)' in draft,
    "draft builder has no HTTP client": "HttpURLConnection" not in draft and "java.net.URL" not in draft,
    "device register is mentioned only as blocked contract gate": "device/register(device_code)" in draft and "NOT called" in draft,
    "checkout still only writes local draft": "OrderSyncDraftBuilder(this).write(order)" in main,
    "checkout still opens payment selection": 'openScreen("PAYMENT_METHOD_ALL")' in main,
    "product model stores audited catalog metadata": all(token in models for token in ["idYml", "typeId", "unitId", "catalogCurrency", "basePriceMinor", "taxId"]),
    "catalog parser fills contract metadata": all(token in gateway for token in ['offer.optString("id_yml"', 'offer.optInt("type_id"', 'offer.optInt("unit_id"', 'offer.optInt("tax_id"']),
    "non-secret evidence snapshot exists": '"device_id": 3476' in evidence and '"id": 164570' in evidence and '"card_service_in_slug_candidate": "external_plastic_cards"' in evidence,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
if failed:
    raise SystemExit("S3 DRY_RUN v2 guard failed: " + ", ".join(failed))
print(f"[OK] S3 DRY_RUN v2 guard: {len(checks)} checks passed")
