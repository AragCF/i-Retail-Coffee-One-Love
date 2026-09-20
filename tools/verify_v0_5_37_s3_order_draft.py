from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
draft = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/OrderSyncDraft.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

checks = {
    "versionCode 37": "versionCode 37" in build,
    "versionName 0.5.37": "versionName '0.5.37-s3-order-draft'" in build,
    "draft mode is explicit": '"DRY_RUN_ONLY"' in draft,
    "network send is explicitly disabled": '.put("send_allowed", false)' in draft,
    "candidate endpoint is documented": '"iretail/order/synchronize"' in draft,
    "unresolved order id is explicit": '.put("id", JSONObject.NULL)' in draft,
    "employee id is not guessed": '.put("employee_id", JSONObject.NULL)' in draft,
    "pin is not guessed": '.put("pin", JSONObject.NULL)' in draft,
    "draft contains offer id": '.put("offer_id", line.product.offerId)' in draft,
    "draft contains exact quantity": '.put("quantity", line.quantity)' in draft,
    "draft contains exact price": '.put("price", money(line.product.priceMinor))' in draft,
    "draft validates line sum": '.put("lines_equal_gross", sumsMatch)' in draft,
    "draft builder has no HTTP client": "HttpURLConnection" not in draft and "java.net.URL" not in draft,
    "checkout creates local draft": "OrderSyncDraftBuilder(this).write(order)" in main,
    "checkout still only opens payment selection": 'openScreen("PAYMENT_METHOD_ALL")' in main,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
if failed:
    raise SystemExit("S3 order-draft guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.37 S3 order-draft guard: {len(checks)} checks passed")
