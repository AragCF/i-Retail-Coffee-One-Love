from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
models = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/Models.kt").read_text(encoding="utf-8")
gateways = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/IntegrationGateways.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")

checks = {
    "Product stores minor units": "val priceMinor: Long = price.toLong() * 100L" in models,
    "RuntimeOrder stores exact minor totals": "val amountMinor: Long" in models and "val grossAmountMinor: Long" in models,
    "API price parser keeps 2 decimals": ".setScale(2, RoundingMode.HALF_UP)" in gateways and ".movePointRight(2)" in gateways,
    "old whole-ruble parser removed": "setScale(0, RoundingMode.HALF_UP).toInt()" not in gateways,
    "XML decimal truncation removed": "substringBefore('.')" not in gateways,
    "new catalog parsed before cache replacement": gateways.find("val parsed = parseCatalogZip(zipBytes)") < gateways.find("persistValidatedCatalog(zipBytes)"),
    "cache candidate revalidated": "val reparsed = parseCatalogZip(candidate.readBytes())" in gateways,
    "cart totals use minor units": "it.product.priceMinor * it.quantity.toLong()" in main,
    "Kozen receives exact two-decimal amount": "paymentAmount(order.amountMinor)" in main,
    "money formatter prints kopecks": '"%d,%02d ₽"' in main,
    "S1 no local fiscalized state": "order.status = OrderStatus.FISCALIZED" not in gateways,
    "S1 no fake local receipt": "local://receipt/" not in gateways,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
if failed:
    raise SystemExit("S2 guard failed: " + ", ".join(failed))
print(f"[OK] S2 catalog-money guard: {len(checks)} checks passed")
