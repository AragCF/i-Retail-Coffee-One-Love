package com.coffeeonelove.iretail.ui

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.math.BigDecimal
import java.math.RoundingMode
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipInputStream

/**
 * Слой данных и интеграций.
 *
 * v0.5: каталог больше не привязан только к XML из макета.
 * Приложение умеет авторизоваться в I-Retail как терминал, скачивать актуальный ZIP-каталог
 * через iretail/catalog/download-actual-zip, разбирать categories.json/offers_0000.json,
 * сохранять локальный кэш и показывать кэш при отсутствии сети.
 */
class IretailContentRepository(private val context: Context) {
    private val apiConfig: IretailApiConfig by lazy { loadApiConfig() }
    private val cacheFile: File by lazy { File(context.filesDir, "iretail_catalog_cache.zip") }

    fun loadProducts(): List<Product> {
        val cached = try { parseCatalogZip(cacheFile.readBytes()).products } catch (_: Exception) { emptyList() }
        return cached.ifEmpty { loadProductsFromXmlAsset() }
    }

    fun refreshProductsAsync(onResult: (CatalogRefreshResult) -> Unit) {
        if (!apiConfig.enabled) {
            onResult(CatalogRefreshResult(false, emptyList(), "Удалённый каталог отключён в content/iretail-api.json", "content XML", channelId = apiConfig.channelId))
            return
        }
        Thread {
            val result = try {
                val zipBytes = downloadCatalogZip()
                cacheFile.writeBytes(zipBytes)
                val parsed = parseCatalogZip(zipBytes)
                CatalogRefreshResult(
                    success = parsed.products.isNotEmpty(),
                    products = parsed.products,
                    message = "I-Retail: загружено ${parsed.products.size} товаров из ${parsed.offersCount} предложений",
                    source = "I-Retail ZIP",
                    categoriesCount = parsed.categoriesCount,
                    offersCount = parsed.offersCount,
                    channelId = apiConfig.channelId
                )
            } catch (e: Exception) {
                val cached = try { parseCatalogZip(cacheFile.readBytes()) } catch (_: Exception) { null }
                if (cached != null && cached.products.isNotEmpty()) {
                    CatalogRefreshResult(true, cached.products, "I-Retail недоступен, показан сохранённый каталог: ${e.cleanMessage()}", "I-Retail ZIP cache", cached.categoriesCount, cached.offersCount, apiConfig.channelId)
                } else {
                    CatalogRefreshResult(false, emptyList(), "I-Retail недоступен, показан XML-макет: ${e.cleanMessage()}", "content XML", channelId = apiConfig.channelId)
                }
            }
            onResult(result)
        }.start()
    }

    fun lookupLoyaltyAsync(input: String, onResult: (LoyaltyLookupResult) -> Unit) {
        val query = input.trim()
        if (query.isBlank()) {
            onResult(LoyaltyLookupResult(false, "Введите код карты, телефон или email"))
            return
        }
        Thread {
            val result = try {
                lookupLoyalty(query)
            } catch (e: Exception) {
                LoyaltyLookupResult(false, "Лояльность I-Retail недоступна: ${e.cleanMessage()}")
            }
            onResult(result)
        }.start()
    }

    fun loadPaymentMethods(): List<PayMethod> {
        val xml = readAsset("content/pay-methods.xml")
        return Regex("<method\\s+([^>]*)>(.*?)</method>", RegexOption.DOT_MATCHES_ALL).findAll(xml)
            .mapNotNull { match ->
                val attrs = parseAttributes(match.groupValues[1]) ?: return@mapNotNull null
                val body = match.groupValues[2]
                val title = Regex("<title>(.*?)</title>", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE)).find(body)?.groupValues?.getOrNull(1)?.trim().orEmpty()
                val id = attrs["id"].orEmpty()
                if (id.isBlank() || title.isBlank()) return@mapNotNull null
                PayMethod(
                    id = id,
                    slug = attrs["slug"].orEmpty(),
                    title = title,
                    enabled = attrs["enabled"] == "true",
                    phoneRequired = attrs["phone"] == "true"
                )
            }
            .distinctBy { it.slug + "|" + it.title }
            .toList()
            .ifEmpty {
                listOf(
                    PayMethod("4", "external_plastic_cards", "Внешний эквайринг", true, false),
                    PayMethod("cash", "cash", "Наличные", true, false),
                    PayMethod("7777", "payin_payout", "Online", true, false)
                )
            }
    }

    private fun downloadCatalogZip(): ByteArray {
        val token = authenticate()
        return postFormBytes(
            path = "iretail/catalog/download-actual-zip",
            fields = apiFields(token) + mapOf("channel_id" to apiConfig.channelId)
        )
    }

    private fun lookupLoyalty(input: String): LoyaltyLookupResult {
        val token = authenticate()
        val common = apiFields(token) + mapOf("channel_id" to apiConfig.channelId)
        val normalized = input.trim()
        val isEmail = normalized.contains("@")
        val phone = if (!isEmail) normalizePhone(normalized) else ""

        val attempts = mutableListOf<Pair<String, Map<String, String>>>()

        // По отчёту iretail_exhibition_probe_20260618_063113_readonly.zip подтверждён
        // рабочий вариант для личного кода клиента: поле code = 0736816.
        if (!isEmail) attempts.add("code" to (common + mapOf("code" to normalized)))
        if (isEmail) attempts.add("email" to (common + mapOf("email" to normalized)))
        if (phone.length >= 10) attempts.add("phone" to (common + mapOf("phone" to phone)))

        val fallbackCodeFields = listOf("ident", "client_code", "personal_code", "card_code", "external_id")
        fallbackCodeFields.forEach { field ->
            if (!isEmail) attempts.add(field to (common + mapOf(field to normalized)))
        }

        val messages = mutableListOf<String>()
        attempts.forEach { (label, fields) ->
            val json = runCatching { postFormJson("iretail/client/get-coupons-and-balance", fields) }.getOrNull()
            val result = interpretLoyaltyJson(json)
            if (result.success) return result
            val title = json?.optJSONObject("result")?.optString("title").orEmpty()
            if (title.isNotBlank()) messages.add("$label: $title")
        }

        return LoyaltyLookupResult(false, messages.firstOrNull()?.let { "Клиент не найден ($it)" } ?: "Клиент не найден")
    }

    private fun interpretLoyaltyJson(json: JSONObject?): LoyaltyLookupResult {
        if (json == null || !json.optBoolean("status", false)) return LoyaltyLookupResult(false, "Нет данных")
        val result = json.optJSONObject("result") ?: return LoyaltyLookupResult(false, "Нет данных клиента")
        val settings = result.optJSONObject("settings")
        val loyaltyActive = settings?.optBoolean("active", false) == true
        if (!loyaltyActive) return LoyaltyLookupResult(false, "Система лояльности выключена в I-Retail", loyaltyActive = false)

        val balanceInfo = parseIretailBalance(result.optJSONArray("amount"))
        val couponsCount = result.optJSONArray("coupons")?.length() ?: 0
        val externalId = result.optString("externalId", "").takeIf { it.isNotBlank() && it != "null" }
        val balanceLabel = balanceInfo.label ?: "0 бонусов"
        val couponText = if (couponsCount > 0) ", купонов: $couponsCount" else ""
        return LoyaltyLookupResult(
            success = true,
            message = "Клиент найден: $balanceLabel$couponText",
            balanceLabel = balanceLabel,
            availableBonusAmount = balanceInfo.availableAmount,
            externalId = externalId,
            couponsCount = couponsCount,
            loyaltyActive = true
        )
    }

    private fun parseIretailBalance(amounts: JSONArray?): BalanceInfo {
        if (amounts == null || amounts.length() == 0) return BalanceInfo("0 бонусов", 0)
        val labels = mutableListOf<String>()
        var available = 0
        for (i in 0 until amounts.length()) {
            val item = amounts.optJSONObject(i) ?: continue
            val rawAmount = item.optDouble("amount", 0.0)
            val rounded = BigDecimal.valueOf(rawAmount).setScale(0, RoundingMode.DOWN).toInt().coerceAtLeast(0)
            val currency = item.optString("currency", "").ifBlank { "бонусов" }
            labels.add("$rounded $currency")
            if (rounded > available) available = rounded
        }
        return BalanceInfo(labels.joinToString(", ").ifBlank { "0 бонусов" }, available)
    }

    private data class BalanceInfo(val label: String?, val availableAmount: Int)

    private fun authenticate(): String {
        val json = postFormJson(
            path = "user/authentication",
            fields = mapOf(
                "username" to apiConfig.login,
                "password" to apiConfig.password,
                "client_id" to apiConfig.clientId,
                "client_secret" to apiConfig.clientSecret
            )
        )
        if (!json.optBoolean("status", false)) throw IllegalStateException(json.optJSONObject("result")?.optString("title") ?: "authentication failed")
        return json.getJSONObject("result").getString("access_token")
    }

    private fun apiFields(accessToken: String): Map<String, String> = mapOf(
        "client_id" to apiConfig.clientId,
        "client_secret" to apiConfig.clientSecret,
        "access_token" to accessToken
    )

    private fun postFormJson(path: String, fields: Map<String, String>): JSONObject {
        val bytes = postFormBytes(path, fields)
        return JSONObject(bytes.toString(Charsets.UTF_8))
    }

    private fun postFormBytes(path: String, fields: Map<String, String>): ByteArray {
        val url = URL(apiConfig.baseUrl.trimEnd('/') + "/" + path.trimStart('/'))
        val payload = fields.entries.joinToString("&") { entry ->
            URLEncoder.encode(entry.key, "UTF-8") + "=" + URLEncoder.encode(entry.value, "UTF-8")
        }.toByteArray(Charsets.UTF_8)
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15000
            readTimeout = 30000
            doOutput = true
            setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
            setRequestProperty("Accept", "application/json, application/zip, */*")
        }
        conn.outputStream.use { it.write(payload) }
        val code = conn.responseCode
        val stream = if (code in 200..299) conn.inputStream else conn.errorStream
        val body = stream?.use { it.readBytes() } ?: ByteArray(0)
        if (code !in 200..299) throw IllegalStateException("HTTP $code: ${body.toString(Charsets.UTF_8).take(160)}")
        return body
    }

    private fun parseCatalogZip(zipBytes: ByteArray): ParsedCatalog {
        var categoriesJson: JSONObject? = null
        val offers = mutableListOf<JSONObject>()
        ZipInputStream(ByteArrayInputStream(zipBytes)).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                val name = entry.name.trimStart('/')
                val text = zip.readBytes().toString(Charsets.UTF_8)
                when {
                    name == "categories.json" -> categoriesJson = JSONObject(text)
                    name.startsWith("offers_") && name.endsWith(".json") -> {
                        val root = JSONObject(text)
                        val arr = root.optJSONArray("offers") ?: JSONArray()
                        for (i in 0 until arr.length()) {
                            arr.optJSONObject(i)?.let { offers.add(it) }
                        }
                    }
                }
                zip.closeEntry()
                entry = zip.nextEntry
            }
        }
        val categoryTitles = mutableMapOf<Int, String>()
        categoriesJson?.let { collectCategoryTitles(it, categoryTitles) }
        val products = offers
            .filter { it.optBoolean("available", true) && it.optInt("status_id", 1) == 1 }
            .mapNotNull { offerToProduct(it, categoryTitles) }
            .distinctBy { it.id }
            .sortedWith(compareBy<Product> { it.categoryTitle ?: "" }.thenBy { it.name.lowercase(Locale.ROOT) })
        return ParsedCatalog(products, categoryTitles.size, offers.size)
    }

    private fun collectCategoryTitles(category: JSONObject, result: MutableMap<Int, String>) {
        val id = category.optInt("id", 0)
        val title = category.optString("title", "").trim()
        if (id > 0 && title.isNotBlank()) result[id] = title
        val children = category.optJSONArray("categories") ?: return
        for (i in 0 until children.length()) children.optJSONObject(i)?.let { collectCategoryTitles(it, result) }
    }

    private fun offerToProduct(offer: JSONObject, categories: Map<Int, String>): Product? {
        val id = offer.optLong("id", 0L).takeIf { it > 0 }?.toString() ?: return null
        val name = offer.optString("name", "").trim()
        if (name.isBlank()) return null
        val price = parsePrice(offer.optString("price", "0"))
        val categoryId = offer.optInt("category_id", 0)
        val categoryTitle = categories[categoryId]
        val imageUrl = offer.optJSONArray("pictures")?.optJSONObject(0)?.optString("url")?.takeIf { it.isNotBlank() }
        val volume = detectVolume(name, offer)
        val gcode = offer.optString("gcode", "").takeIf { it.isNotBlank() && it != "null" }
        val category = detectUiCategory(name, categoryTitle, gcode)
        return Product(
            id = id,
            offerId = offer.optString("external_offer_id", id).takeIf { it.isNotBlank() && it != "null" } ?: id,
            name = name,
            volume = volume,
            price = price,
            category = category,
            available = true,
            heat = category == "micromarket" && offer.optInt("microwave_time", 0) > 0,
            gcode = gcode,
            imageUrl = imageUrl,
            categoryTitle = categoryTitle
        )
    }

    private fun parsePrice(value: String): Int = try {
        BigDecimal(value.replace(',', '.')).setScale(0, RoundingMode.HALF_UP).toInt()
    } catch (_: Exception) {
        0
    }

    private fun detectVolume(name: String, offer: JSONObject): String {
        Regex("(\\d+)\\s*(мл|ml|г|гр|g|л|l)", RegexOption.IGNORE_CASE).find(name)?.let { match ->
            return match.value.replace(" ", "")
        }
        val unitId = offer.optInt("unit_id", 1)
        return if (unitId == 1) "1 шт." else ""
    }

    private fun detectUiCategory(name: String, categoryTitle: String?, gcode: String?): String {
        val source = (name + " " + (categoryTitle ?: "")).lowercase(Locale.ROOT).replace("ё", "е")
        val coffeeWords = listOf("кофе", "капучино", "латте", "эспрессо", "американо", "какао", "флэт", "flat", "espresso", "cappuccino", "latte", "coffee")
        val coffeeGcode = gcode?.lowercase(Locale.ROOT)?.startsWith("coffee-") == true
        if (coffeeGcode || coffeeWords.any { source.contains(it) }) return "coffee"
        val marketWords = listOf("еда", "продукт", "фрукт", "сумк", "часы", "парфюм", "аромат", "ремни")
        if (marketWords.any { source.contains(it) }) return "micromarket"
        return "other"
    }

    private fun loadProductsFromXmlAsset(): List<Product> {
        val xml = readAsset("content/main-screen.xml")
        val offers = Regex("<offer\\s+([^>/]+)/?>").findAll(xml)
            .mapNotNull { parseAttributes(it.groupValues[1]) }
            .mapNotNull { attrs ->
                val caption = attrs["caption"]?.trim().orEmpty()
                val price = attrs["price"]?.substringBefore('.')?.toIntOrNull() ?: return@mapNotNull null
                val offerId = attrs["offerId"]?.trim().orEmpty()
                if (caption.isBlank() || offerId.isBlank()) return@mapNotNull null
                val volume = Regex("(\\d+)\\s*мл", RegexOption.IGNORE_CASE).find(caption)?.value?.replace(" ", "") ?: ""
                val isCoffee = volume.isNotBlank() || listOf("американо", "капучино", "латте", "эспрессо", "какао", "флэт").any { caption.lowercase(Locale.ROOT).contains(it) }
                val isFood = listOf("еда", "товар", "тестовый").any { caption.lowercase(Locale.ROOT).contains(it) }
                val category = when {
                    isCoffee -> "coffee"
                    isFood -> "micromarket"
                    else -> "other"
                }
                Product(
                    id = offerId,
                    offerId = offerId,
                    name = caption.removeSuffix(" $volume").trim(),
                    volume = volume.ifBlank { if (category == "coffee") "200мл" else "1 шт." },
                    price = price,
                    category = category,
                    available = true,
                    heat = category == "micromarket",
                    gcode = if (category == "coffee") "Coffee-$offerId" else null
                )
            }
            .filter { it.category == "coffee" || it.category == "micromarket" }
            .distinctBy { it.name.lowercase(Locale.ROOT) + "|" + it.price + "|" + it.volume }
            .toMutableList()

        if (offers.none { it.category == "micromarket" }) {
            offers.add(Product("local-food-1", "local-food-1", "Сэндвич", "1 шт.", 180, "micromarket", true, heat = true))
        }
        return offers.ifEmpty { fallbackProducts() }
    }

    private fun readAsset(path: String): String = try {
        context.assets.open(path).bufferedReader(Charsets.UTF_8).use { it.readText() }
    } catch (_: Exception) {
        ""
    }

    private fun parseAttributes(raw: String): Map<String, String>? {
        val attrs = Regex("([A-Za-z0-9_:-]+)=\"([^\"]*)\"").findAll(raw).associate { it.groupValues[1] to decodeXml(it.groupValues[2]) }
        return attrs.ifEmpty { null }
    }

    private fun decodeXml(value: String): String = value
        .replace("&quot;", "\"")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")

    private fun loadApiConfig(): IretailApiConfig {
        val text = readAsset("content/iretail-api.json")
        if (text.isBlank()) return IretailApiConfig()
        val json = JSONObject(text)
        return IretailApiConfig(
            enabled = json.optBoolean("enabled", true),
            baseUrl = json.optString("base_url", "https://my.i-retail.com/api/"),
            login = json.optString("login", ""),
            password = json.optString("password", ""),
            clientId = json.optString("client_id", "IRETAIL_TERMINAL"),
            clientSecret = json.optString("client_secret", "2758bb5da44242c8cc36f070ec09655d"),
            profileId = json.optString("profile_id", "2512"),
            channelId = json.optString("channel_id", "5676"),
            currencyId = json.optString("currency_id", "643"),
            deviceCode = json.optString("device_code", "6287"),
            deviceId = json.optString("device_id", "6287")
        )
    }

    private fun normalizePhone(value: String): String {
        val digits = value.filter { it.isDigit() }
        return when {
            digits.length == 11 && digits.startsWith("8") -> "7" + digits.drop(1)
            digits.length == 10 -> "7$digits"
            else -> digits
        }
    }

    private fun Exception.cleanMessage(): String = message?.take(180) ?: javaClass.simpleName

    private fun fallbackProducts(): List<Product> = listOf(
        Product("coffee-americano", "coffee-americano", "Американо", "200мл", 149, "coffee", true, gcode = "Coffee-01"),
        Product("coffee-cappuccino", "coffee-cappuccino", "Капучино", "200мл", 149, "coffee", true, gcode = "Coffee-02"),
        Product("coffee-latte", "coffee-latte", "Латте", "300мл", 179, "coffee", true, gcode = "Coffee-03"),
        Product("coffee-espresso", "coffee-espresso", "Эспрессо", "100мл", 149, "coffee", true, gcode = "Coffee-04"),
        Product("food-sandwich", "food-sandwich", "Сэндвич", "1 шт.", 180, "micromarket", true, heat = true)
    )

    private data class IretailApiConfig(
        val enabled: Boolean = false,
        val baseUrl: String = "https://my.i-retail.com/api/",
        val login: String = "",
        val password: String = "",
        val clientId: String = "IRETAIL_TERMINAL",
        val clientSecret: String = "2758bb5da44242c8cc36f070ec09655d",
        val profileId: String = "2512",
        val channelId: String = "5676",
        val currencyId: String = "643",
        val deviceCode: String = "6287",
        val deviceId: String = "6287"
    )

    private data class ParsedCatalog(
        val products: List<Product>,
        val categoriesCount: Int,
        val offersCount: Int
    )
}

class LocalRetailOrderGateway {
    private var sequence = 1000
    private var activeOrder: RuntimeOrder? = null

    fun createOrder(lines: List<CartLine>, grossAmount: Int, ibonusDiscountSum: Int = 0, loyalty: LocalLoyaltyGateway? = null): RuntimeOrder {
        val number = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT).format(Date()) + "-" + (++sequence)
        val payableAmount = (grossAmount - ibonusDiscountSum).coerceAtLeast(0)
        val order = RuntimeOrder(
            localId = sequence.toString(),
            externalNumber = number,
            amount = payableAmount,
            items = lines.map { CartLine(it.product, it.quantity, it.ownCup, it.syrupAdded, it.syrupName) },
            grossAmount = grossAmount,
            ibonusDiscountSum = ibonusDiscountSum.coerceAtLeast(0),
            loyaltyExternalId = loyalty?.externalId,
            loyaltyBalanceLabel = loyalty?.balanceLabel
        )
        activeOrder = order
        return order
    }

    fun startPayment(method: PaymentMethod): OperationResult {
        val order = activeOrder ?: return OperationResult.ERROR
        order.status = OrderStatus.PAYMENT_STARTED
        order.paymentMethod = method
        return OperationResult.SUCCESS
    }

    fun completePayment(): OperationResult {
        val order = activeOrder ?: return OperationResult.ERROR
        order.status = OrderStatus.PAID
        order.fiscalReceiptUrl = "local://receipt/" + order.externalNumber
        order.status = OrderStatus.FISCALIZED
        return OperationResult.SUCCESS
    }

    fun markCooking(): RuntimeOrder? {
        val order = activeOrder
        order?.status = OrderStatus.COOKING
        return order
    }

    fun markReady(): RuntimeOrder? {
        val order = activeOrder
        order?.status = OrderStatus.READY
        return order
    }

    fun currentOrder(): RuntimeOrder? = activeOrder
}

class LocalMachineGateway {
    fun confirmCupPlaced(): DeviceCommandResult = DeviceCommandResult(true, "Стакан подтверждён")
    fun dispenseCoffee(order: RuntimeOrder?): DeviceCommandResult {
        val count = order?.items?.sumOf { it.quantity } ?: 0
        return DeviceCommandResult(true, "Выдано позиций: $count", 100)
    }
    fun heatFood(): DeviceCommandResult = DeviceCommandResult(true, "Разогрев завершён", 100)
}

class LocalLoyaltyGateway {
    var loggedIn: Boolean = false
        private set
    var bonusApplied: Int = 0
        private set
    var balanceLabel: String? = null
        private set
    var availableBonusAmount: Int = 0
        private set
    var externalId: String? = null
        private set
    var couponsCount: Int = 0
        private set
    var attachedToOrder: Boolean = false
        private set

    fun loginSuccess(result: LoyaltyLookupResult) {
        loggedIn = true
        balanceLabel = result.balanceLabel
        availableBonusAmount = result.availableBonusAmount.coerceAtLeast(0)
        externalId = result.externalId
        couponsCount = result.couponsCount
        attachedToOrder = true
        bonusApplied = 0
    }

    fun loginSuccess(balance: String?) {
        loggedIn = true
        balanceLabel = balance
        availableBonusAmount = parseBalanceRub(balance).coerceAtLeast(0)
        attachedToOrder = true
        bonusApplied = 0
    }

    fun login(cardOrPhone: String): OperationResult {
        loggedIn = cardOrPhone.isNotBlank()
        availableBonusAmount = 0
        attachedToOrder = loggedIn
        bonusApplied = 0
        return if (loggedIn) OperationResult.SUCCESS else OperationResult.ERROR
    }

    fun applyBonus(maxAmount: Int): Int {
        attachedToOrder = loggedIn || attachedToOrder
        bonusApplied = maxAmount.coerceAtMost(availableBonusAmount).coerceAtLeast(0)
        return bonusApplied
    }

    fun clear() {
        loggedIn = false
        bonusApplied = 0
        balanceLabel = null
        availableBonusAmount = 0
        externalId = null
        couponsCount = 0
        attachedToOrder = false
    }

    private fun parseBalanceRub(value: String?): Int {
        val raw = value ?: return 0
        val match = Regex("\\d+(?:[.,]\\d+)?").find(raw)?.value ?: return 0
        return try {
            BigDecimal(match.replace(',', '.')).setScale(0, RoundingMode.DOWN).toInt()
        } catch (_: Exception) {
            0
        }
    }
}
