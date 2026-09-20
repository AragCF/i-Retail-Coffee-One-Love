from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    if new in text:
        print(f"[SKIP] {label}: already applied")
        return
    if old not in text:
        raise SystemExit(f"[FAIL] {label}: baseline not found")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"[OK] {label}")

p = "app/src/main/java/com/coffeeonelove/iretail/ui/IntegrationGateways.kt"
replace_once(p,
"""            val result = try {
                val zipBytes = downloadCatalogZip()
                cacheFile.writeBytes(zipBytes)
                val parsed = parseCatalogZip(zipBytes)
                CatalogRefreshResult(
                    success = parsed.products.isNotEmpty(),""",
"""            val result = try {
                val zipBytes = downloadCatalogZip()
                val parsed = parseCatalogZip(zipBytes)
                if (parsed.offersCount <= 0 || parsed.products.isEmpty()) {
                    throw IllegalStateException("Каталог I-Retail не содержит пригодных товаров")
                }
                persistValidatedCatalog(zipBytes)
                CatalogRefreshResult(
                    success = true,""",
"validate before cache replace")

replace_once(p,
"""        val price = parsePrice(offer.optString("price", "0"))""",
"""        val priceMinor = parsePriceMinor(offer.optString("price", "0"))
        val price = (priceMinor / 100L).coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()""",
"API price to minor units")

replace_once(p,
"""            categoryTitle = categoryTitle
        )
    }

    private fun parsePrice(value: String): Int = try {
        BigDecimal(value.replace(',', '.')).setScale(0, RoundingMode.HALF_UP).toInt()
    } catch (_: Exception) {
        0
    }""",
"""            categoryTitle = categoryTitle,
            priceMinor = priceMinor
        )
    }

    private fun parsePriceMinor(value: String): Long = try {
        BigDecimal(value.replace(',', '.'))
            .setScale(2, RoundingMode.HALF_UP)
            .movePointRight(2)
            .longValueExact()
            .coerceAtLeast(0L)
    } catch (_: Exception) {
        0L
    }""",
"two-decimal price parser")

replace_once(p,
"""                val caption = attrs["caption"]?.trim().orEmpty()
                val price = attrs["price"]?.substringBefore('.')?.toIntOrNull() ?: return@mapNotNull null
                val offerId = attrs["offerId"]?.trim().orEmpty()""",
"""                val caption = attrs["caption"]?.trim().orEmpty()
                val priceMinor = parsePriceMinor(attrs["price"].orEmpty())
                val price = (priceMinor / 100L).coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
                val offerId = attrs["offerId"]?.trim().orEmpty()""",
"XML price to minor units")

replace_once(p,
"""                    heat = category == "micromarket",
                    gcode = if (category == "coffee") "Coffee-$offerId" else null
                )""",
"""                    heat = category == "micromarket",
                    gcode = if (category == "coffee") "Coffee-$offerId" else null,
                    priceMinor = priceMinor
                )""",
"XML product minor price")

replace_once(p,
""".distinctBy { it.name.lowercase(Locale.ROOT) + "|" + it.price + "|" + it.volume }""",
""".distinctBy { it.name.lowercase(Locale.ROOT) + "|" + it.priceMinor + "|" + it.volume }""",
"catalog distinct key uses exact price")

replace_once(p,
"""    private fun readAsset(path: String): String = try {""",
"""    private fun persistValidatedCatalog(zipBytes: ByteArray) {
        val candidate = File(context.filesDir, "iretail_catalog_cache.zip.new")
        val backup = File(context.filesDir, "iretail_catalog_cache.zip.bak")
        candidate.delete()
        backup.delete()

        candidate.writeBytes(zipBytes)
        val reparsed = parseCatalogZip(candidate.readBytes())
        if (reparsed.offersCount <= 0 || reparsed.products.isEmpty()) {
            candidate.delete()
            throw IllegalStateException("Проверка нового каталога после записи не пройдена")
        }

        if (cacheFile.exists() && !cacheFile.renameTo(backup)) {
            candidate.delete()
            throw IllegalStateException("Не удалось сохранить резервную копию каталога")
        }

        if (!candidate.renameTo(cacheFile)) {
            if (backup.exists()) backup.renameTo(cacheFile)
            candidate.delete()
            throw IllegalStateException("Не удалось заменить кэш каталога")
        }

        backup.delete()
    }

    private fun readAsset(path: String): String = try {""",
"validated cache replacement")

replace_once(p,
"""    fun createOrder(lines: List<CartLine>, grossAmount: Int, ibonusDiscountSum: Int = 0, loyalty: LocalLoyaltyGateway? = null): RuntimeOrder {
        val number = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT).format(Date()) + "-" + (++sequence)
        val payableAmount = (grossAmount - ibonusDiscountSum).coerceAtLeast(0)
        val order = RuntimeOrder(
            localId = sequence.toString(),
            externalNumber = number,
            amount = payableAmount,
            items = lines.map { CartLine(it.product, it.quantity, it.ownCup, it.syrupAdded, it.syrupName) },
            grossAmount = grossAmount,
            ibonusDiscountSum = ibonusDiscountSum.coerceAtLeast(0),""",
"""    fun createOrder(lines: List<CartLine>, grossAmountMinor: Long, ibonusDiscountMinor: Long = 0L, loyalty: LocalLoyaltyGateway? = null): RuntimeOrder {
        val number = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT).format(Date()) + "-" + (++sequence)
        val safeGrossMinor = grossAmountMinor.coerceAtLeast(0L)
        val safeDiscountMinor = ibonusDiscountMinor.coerceIn(0L, safeGrossMinor)
        val payableMinor = (safeGrossMinor - safeDiscountMinor).coerceAtLeast(0L)
        val order = RuntimeOrder(
            localId = sequence.toString(),
            externalNumber = number,
            amount = (payableMinor / 100L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            items = lines.map { CartLine(it.product, it.quantity, it.ownCup, it.syrupAdded, it.syrupName) },
            grossAmount = (safeGrossMinor / 100L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            ibonusDiscountSum = (safeDiscountMinor / 100L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),""",
"order accepts exact minor units")

replace_once(p,
"""            loyaltyExternalId = loyalty?.externalId,
            loyaltyBalanceLabel = loyalty?.balanceLabel
        )""",
"""            loyaltyExternalId = loyalty?.externalId,
            loyaltyBalanceLabel = loyalty?.balanceLabel,
            amountMinor = payableMinor,
            grossAmountMinor = safeGrossMinor,
            ibonusDiscountMinor = safeDiscountMinor
        )""",
"order stores exact minor units")

p = "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt"
simple = [
("formatMoney(product.price)", "formatMoney(product.priceMinor)", "product price display"),
("formatMoney(line.product.price * line.quantity)", "formatMoney(line.product.priceMinor * line.quantity.toLong())", "cart line exact totals"),
("cartGrossTotal()", "cartGrossTotalMinor()", "gross total helper rename"),
("orderDiscount()", "orderDiscountMinor()", "discount helper rename"),
("cartTotal()", "cartTotalMinor()", "cart total helper rename"),
("formatMoney(order.amount)", "formatMoney(order.amountMinor)", "order amount display"),
("order?.amount ?: cartTotalMinor()", "order?.amountMinor ?: cartTotalMinor()", "nullable order amount display"),
("order == null || order.amount <= 0", "order == null || order.amountMinor <= 0L", "payment amount validation"),
('val amount = String.format(Locale.US, "%d.00", order.amount)', "val amount = paymentAmount(order.amountMinor)", "Kozen exact amount"),
('"UI v0.5.35 |', '"UI v0.5.36 |', "diagnostic version"),
]
for old, new, label in simple:
    while True:
        target = ROOT / p
        text = target.read_text(encoding="utf-8")
        if old not in text:
            break
        target.write_text(text.replace(old, new, 1), encoding="utf-8")
        print(f"[OK] {label}")

replace_once(p,
"""        val available = loyaltyGateway.availableBonusAmount.coerceAtMost(cartGrossTotalMinor())
        addLabel(formatMoney(available),""",
"""        val available = loyaltyGateway.availableBonusAmount
            .coerceAtMost((cartGrossTotalMinor() / 100L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
        addLabel(formatMoney(available.toLong() * 100L),""",
"landscape loyalty available amount")

replace_once(p,
"""        addLabel(formatMoney(available.coerceAtMost(cartGrossTotalMinor())), RectSpec(600, 598, 300, 65), 27f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)""",
"""        val availableForOrder = available.coerceAtMost(
            (cartGrossTotalMinor() / 100L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        )
        addLabel(formatMoney(availableForOrder.toLong() * 100L), RectSpec(600, 598, 300, 65), 27f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)""",
"portrait loyalty available amount")

replace_once(p,
"""    private fun cartGrossTotalMinor(): Int = cart.sumOf { it.product.price * it.quantity }

    private fun orderDiscountMinor(): Int = loyaltyGateway.bonusApplied.coerceAtMost(cartGrossTotalMinor()).coerceAtLeast(0)

    private fun cartTotalMinor(): Int = (cartGrossTotalMinor() - orderDiscountMinor()).coerceAtLeast(0)

    private fun formatMoney(value: Int): String = "$value,00 ₽" """.rstrip(),
"""    private fun cartGrossTotalMinor(): Long =
        cart.sumOf { it.product.priceMinor * it.quantity.toLong() }

    private fun orderDiscountMinor(): Long {
        val bonusMinor = loyaltyGateway.bonusApplied.coerceAtLeast(0).toLong() * 100L
        return bonusMinor.coerceAtMost(cartGrossTotalMinor())
    }

    private fun cartTotalMinor(): Long =
        (cartGrossTotalMinor() - orderDiscountMinor()).coerceAtLeast(0L)

    private fun formatMoney(valueMinor: Long): String {
        val safe = valueMinor.coerceAtLeast(0L)
        val rubles = safe / 100L
        val kopecks = safe % 100L
        return String.format(Locale("ru", "RU"), "%d,%02d ₽", rubles, kopecks)
    }

    private fun paymentAmount(valueMinor: Long): String {
        val safe = valueMinor.coerceAtLeast(0L)
        return String.format(Locale.US, "%d.%02d", safe / 100L, safe % 100L)
    }""",
"minor-unit total helpers")

replace_once(p,
"""        val bonus = loyaltyGateway.applyBonus(cartGrossTotalMinor())
        if (bonus > 0) {
            toast("Бонусы применены: \${formatMoney(bonus)}")""",
"""        val maxBonusRub = (cartGrossTotalMinor() / 100L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        val bonus = loyaltyGateway.applyBonus(maxBonusRub)
        if (bonus > 0) {
            toast("Бонусы применены: \${formatMoney(bonus.toLong() * 100L)}")""",
"loyalty compatibility conversion")

p = "app/build.gradle"
replace_once(p, "versionCode 35", "versionCode 36", "versionCode")
replace_once(p, "versionName '0.5.35-root-layout'", "versionName '0.5.36-s2-catalog-money'", "versionName")

p = "BUILD_WINDOWS_CLI.bat"
replace_once(p, "rem i-Retail Android UI v0.5.35 root layout", "rem i-Retail Android UI v0.5.36 S2 catalog and money", "Windows build banner")
replace_once(p, 'set "SCRIPT_VERSION=0.5.35-root-layout"', 'set "SCRIPT_VERSION=0.5.36-s2-catalog-money"', "Windows build version")

print("[OK] v0.5.36 S2 materialization completed")
