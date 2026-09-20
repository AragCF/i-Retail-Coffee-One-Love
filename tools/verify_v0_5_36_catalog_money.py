from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
models = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/Models.kt").read_text(encoding="utf-8")
money = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/Money.kt").read_text(encoding="utf-8")
gateways = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/IntegrationGateways.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

checks = []

def require(name: str, condition: bool) -> None:
    checks.append((name, condition))
    if not condition:
        raise SystemExit(f"[FAIL] {name}")

require("versionCode 36", "versionCode 36" in build)
require("versionName 0.5.36-catalog-money", "versionName '0.5.36-catalog-money'" in build)

require("Product uses priceMinor Long", "val priceMinor: Long" in models)
require("RuntimeOrder uses amountMinor Long", "val amountMinor: Long" in models)
require("Money parser requires exactly supported minor precision", "setScale(2, RoundingMode.UNNECESSARY)" in money)
require("Money parser converts decimal to minor units exactly", "longValueExact()" in money)
require("Kozen amount comes from minor units", "Money.paymentAmount(order.amountMinor)" in main)
require("old integer Kozen amount formatting removed", 'String.format(Locale.US, "%d.00"' not in main)
require("integer-ruble Product.price field removed", "val price: Int" not in models)
require("old parsePrice integer rounding removed", "private fun parsePrice" not in gateways)
require("XML decimal truncation removed", "substringBefore('.')" not in gateways)

parse_at = gateways.find("val parsed = parseCatalogZip(zipBytes)")
empty_at = gateways.find("if (parsed.products.isEmpty())")
write_at = gateways.find("cacheFile.writeBytes(zipBytes)")
require("downloaded catalog is parsed before cache write", 0 <= parse_at < write_at)
require("downloaded catalog is validated before cache write", 0 <= empty_at < write_at)
require("UI displays current S2 version", "UI v0.5.36" in main)

print(f"[OK] v0.5.36 S2 catalog/money guard: {len(checks)} checks passed")
