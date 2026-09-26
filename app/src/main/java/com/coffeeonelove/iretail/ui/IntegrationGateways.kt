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
    private val bindingRecord: JSONObject? by lazy {
        DeviceBindingStore.get(context).configuredRecord()
    }
    private val apiConfig: IretailApiConfig by lazy { loadApiConfig() }
    private val cacheFile: File by lazy {
        val record = bindingRecord ?: throw BindingFailure("UNBOUND")
        val directory = File(context.noBackupFilesDir, "catalog/" + BindingRecordPolicy.cacheScope(record))
        if (!directory.exists() && !directory.mkdirs()) throw BindingFailure("CATALOG_DIRECTORY")
        File(directory, "iretail_catalog_cache.zip")
    }
    companion object { private val CATALOG_CACHE_LOCK = Any() }
    private fun hasBoundConfiguration(): Boolean = bindingRecord != null


    fun isRemoteCatalogEnabled(): Boolean = apiConfig.enabled

    fun loadProducts(): List<Product> {
        if (!hasBoundConfiguration()) return emptyList()
        val cached = readCatalogCache()
        if (cached?.structureValid == true) return cached.products
        return if (apiConfig.enabled) emptyList() else loadProductsFromXmlAsset()
    }

    fun refreshProductsAsync(onResult: (CatalogRefreshResult) -> Unit) {
        if (!hasBoundConfiguration()) {
            onResult(CatalogRefreshResult(false, emptyList(), "Сначала привяжите устройство", "I-Retail unbound",
                failureStage = "binding", failureReason = "UNBOUND"))
            return
        }
        if (!apiConfig.enabled) {
            onResult(
                CatalogRefreshResult(
                    false,
                    emptyList(),
                    "Удалённый каталог отключён в content/iretail-api.json",
                    "content XML",
                    channelId = apiConfig.channelId,
                    failureStage = "configuration",
                    failureReason = "DISABLED"
                )
            )
            return
        }
        Thread {
            val result = try {
                val token = try {
                    authenticate()
                } catch (e: Exception) {
                    throw CatalogStageException("authentication", safeCatalogFailureReason(e), safeCatalogFailureDetail(e))
                }

                val zipBytes = try {
                    downloadCatalogZip(token)
                } catch (e: Exception) {
                    throw CatalogStageException("download", safeCatalogFailureReason(e), safeCatalogFailureDetail(e))
                }

                val parsed = try {
                    parseCatalogZip(zipBytes)
                } catch (e: Exception) {
                    throw CatalogStageException("parse", safeCatalogFailureReason(e), safeCatalogFailureDetail(e))
                }

                if (!parsed.structureValid) {
                    throw CatalogStageException("validate", "INVALID_CATALOG_STRUCTURE", "catalog-structure-missing")
                }

                try {
                    persistValidatedCatalog(zipBytes)
                } catch (e: Exception) {
                    throw CatalogStageException("cache", safeCatalogFailureReason(e), safeCatalogFailureDetail(e))
                }

                CatalogRefreshResult(
                    success = true,
                    products = parsed.products,
                    message = if (parsed.products.isEmpty()) {
                        "I-Retail: каталог пуст"
                    } else {
                        "I-Retail: загружено ${parsed.products.size} товаров из ${parsed.offersCount} предложений"
                    },
                    source = "I-Retail ZIP",
                    categoriesCount = parsed.categoriesCount,
                    offersCount = parsed.offersCount,
                    channelId = apiConfig.channelId
                )
            } catch (e: Exception) {
                val stageError = e as? CatalogStageException
                val failureStage = stageError?.stage ?: "unknown"
                val failureReason = stageError?.safeReason ?: safeCatalogFailureReason(e)
                val failureDetail = stageError?.safeDetail ?: safeCatalogFailureDetail(e)
                val cached = readCatalogCache()
                if (cached?.structureValid == true) {
                    CatalogRefreshResult(
                        success = true,
                        products = cached.products,
                        message = if (cached.products.isEmpty()) {
                            "I-Retail недоступен, сохранённый каталог пуст"
                        } else {
                            "I-Retail недоступен, показан сохранённый каталог"
                        },
                        source = "I-Retail ZIP cache",
                        categoriesCount = cached.categoriesCount,
                        offersCount = cached.offersCount,
                        channelId = apiConfig.channelId,
                        failureStage = failureStage,
                        failureReason = failureReason,
                        failureDetail = failureDetail
                    )
                } else {
                    CatalogRefreshResult(
                        success = false,
                        products = emptyList(),
                        message = "I-Retail недоступен, исправной серверной копии каталога нет",
                        source = "I-Retail unavailable",
                        channelId = apiConfig.channelId,
                        failureStage = failureStage,
                        failureReason = failureReason,
                        failureDetail = failureDetail
                    )
                }
            }
            onResult(result)
        }.start()
    }

    fun lookupLoyaltyAsync(input: String, onResult: (LoyaltyLookupResult) -> Unit) {
        if (!DeviceBindingStore.get(context).isReady()) {
            onResult(LoyaltyLookupResult(false, "Сначала завершите привязку устройства"))
            return
        }
        val query = input.trim()
        if (query.isBlank()) {
            onResult(LoyaltyLookupResult(false, "Введите код карты, телефон или email"))
            return
        }
        Thread {
            val result = try {
                lookupLoyalty(query)
            } catch (e: Exception) {
                LoyaltyLookupResult(false, "Лояльность I-Retail недоступна (${safeCatalogFailureReason(e)})")
            }
            onResult(result)
        }.start()
    }

    fun loadPaymentMethods(): List<PayMethod> {
        if (apiConfig.enabled) return emptyList()
        return loadPaymentMethodsFromXml()
    }

    fun refreshChannelConfigAsync(onResult: (ChannelConfigRefreshResult) -> Unit) {
        if (!hasBoundConfiguration()) {
            onResult(ChannelConfigRefreshResult(false, emptyList(), "Сначала привяжите устройство", "I-Retail unbound",
                failureReason = "UNBOUND"))
            return
        }
        if (!apiConfig.enabled) {
            onResult(
                ChannelConfigRefreshResult(
                    success = true,
                    paymentMethods = loadPaymentMethodsFromXml(),
                    message = "Удалённый I-Retail отключён; используются локальные способы оплаты",
                    source = "content XML",
                    channelId = apiConfig.channelId
                )
            )
            return
        }

        Thread {
            val result = try {
                val token = authenticate()
                val common = apiFields(token)
                val channel = postFormJson(
                    "iretail/channel/get",
                    common + mapOf("channel_id" to apiConfig.channelId)
                )
                val services = postFormJson(
                    "iretail/channel/get-available-services-in",
                    common + mapOf("channel_id" to apiConfig.channelId)
                )

                if (!channel.optBoolean("status", false)) {
                    throw IllegalStateException("channel rejected")
                }
                if (!services.optBoolean("status", false)) {
                    throw IllegalStateException("available-services rejected")
                }

                val channelResult = channel.optJSONObject("result")
                    ?: throw IllegalStateException("channel result missing")
                require(DeviceBindingProtocol.id(channelResult.opt("id")) == apiConfig.channelId) { "CHANNEL_MISMATCH" }
                require(DeviceBindingProtocol.id(channelResult.opt("profile_id")) == apiConfig.profileId) { "PROFILE_MISMATCH" }
                val serviceResult = services.optJSONObject("result")
                    ?: throw IllegalStateException("available-services result missing")

                val paymentMethods = parseServerPaymentMethods(serviceResult.getJSONArray("services"))
                val channelEnabled = channelResult?.optBooleanNullable("enable")
                val relatedEnabled = channelResult?.optJSONObject("related")?.optBooleanNullable("enabled")
                val userVerified = serviceResult.optBooleanNullable("user_verified")
                val shopVerified = serviceResult.optBooleanNullable("shop_verified")

                ChannelConfigRefreshResult(
                    success = true,
                    paymentMethods = paymentMethods,
                    message = "I-Retail: доступно способов оплаты ${paymentMethods.size}",
                    source = "I-Retail channel",
                    channelId = apiConfig.channelId,
                    channelEnabled = channelEnabled,
                    relatedEnabled = relatedEnabled,
                    userVerified = userVerified,
                    shopVerified = shopVerified
                )
            } catch (e: Exception) {
                ChannelConfigRefreshResult(
                    success = false,
                    paymentMethods = emptyList(),
                    message = "Настройки канала I-Retail недоступны",
                    source = "I-Retail unavailable",
                    channelId = apiConfig.channelId,
                    failureReason = e.javaClass.simpleName.take(80)
                )
            }
            onResult(result)
        }.start()
    }

    private fun loadPaymentMethodsFromXml(): List<PayMethod> {
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

    private fun parseServerPaymentMethods(services: JSONArray?): List<PayMethod> {
        if (services == null) return emptyList()
        val result = mutableListOf<PayMethod>()
        for (i in 0 until services.length()) {
            val service = services.getJSONObject(i)
            val slug = service.optString("slug", "").trim()
            if (slug.isBlank()) throw IllegalStateException("service slug missing")
            val id = service.opt("id")?.toString()?.takeIf { it.isNotBlank() && it != "null" } ?: slug
            val title = service.optString("title", "").trim()
                .ifBlank { service.optString("name", "").trim() }
                .ifBlank { slug }
            // TSO/API uses settings.enable; XML uses enabled. Unknown is not authorization.
            val enabled = service.optJSONObject("settings")?.optBooleanNullable("enable") == true
            result += PayMethod(
                id = id,
                slug = slug,
                title = title,
                enabled = enabled,
                phoneRequired = false
            )
        }
        return result.distinctBy { it.slug.lowercase(Locale.ROOT) + "|" + it.id }
    }

    private fun JSONObject.optBooleanNullable(key: String): Boolean? {
        if (!has(key) || isNull(key)) return null
        return when (val raw = opt(key)) {
            is Boolean -> raw
            is Number -> when (raw.toDouble()) {
                1.0 -> true
                0.0 -> false
                else -> null
            }
            is String -> when (raw.trim().lowercase(Locale.ROOT)) {
                "1", "true", "yes", "on" -> true
                "0", "false", "no", "off" -> false
                else -> null
            }
            else -> null
        }
    }

    private fun downloadCatalogZip(accessToken: String): ByteArray =
        postFormBytes(
            path = "iretail/catalog/download-actual-zip",
            fields = apiFields(accessToken) + mapOf("channel_id" to apiConfig.channelId)
        )

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
        if (!json.optBoolean("status", false)) throw AuthenticationRejectedException()
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
        check(hasBoundConfiguration()) { "UNBOUND" }
        val url = URL(apiConfig.baseUrl.trimEnd('/') + "/" + path.trimStart('/'))
        val payload = fields.entries.joinToString("&") { entry ->
            URLEncoder.encode(entry.key, "UTF-8") + "=" + URLEncoder.encode(entry.value, "UTF-8")
        }.toByteArray(Charsets.UTF_8)
        val rawConnection = url.openConnection()
        if (rawConnection is javax.net.ssl.HttpsURLConnection) {
            IretailTlsCompat.applyIfNeeded(context, url, rawConnection)
        }
        val conn = (rawConnection as HttpURLConnection).apply {
            requestMethod = "POST"
            instanceFollowRedirects = false
            setFixedLengthStreamingMode(payload.size)
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
        if (code !in 200..299) throw IllegalStateException("HTTP $code")
        return body
    }

    private fun parseCatalogZip(zipBytes: ByteArray): ParsedCatalog {
        var categoriesJson: JSONObject? = null
        var offersEntryCount = 0
        val offers = mutableListOf<JSONObject>()
        ZipInputStream(ByteArrayInputStream(zipBytes)).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                val name = entry.name.trimStart('/')
                val text = zip.readBytes().toString(Charsets.UTF_8)
                when {
                    name == "categories.json" -> {
                        categoriesJson = JSONObject(text)
                    }
                    name.startsWith("offers_") && name.endsWith(".json") -> {
                        offersEntryCount++
                        val root = JSONObject(text)
                        if (!root.has("offers")) throw IllegalStateException("offers array missing")
                        val arr = root.optJSONArray("offers")
                            ?: throw IllegalStateException("offers is not an array")
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
        val structureValid = offersEntryCount > 0
        return ParsedCatalog(products, categoryTitles.size, offers.size, structureValid)
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
        val priceMinor = parsePriceMinor(offer.optString("price", "0"))
        val basePriceMinor = parsePriceMinor(offer.optString("base_price", offer.optString("price", "0")))
        val price = (priceMinor / 100L).coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
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
            categoryTitle = categoryTitle,
            priceMinor = priceMinor,
            idYml = offer.optString("id_yml", "").takeIf { it.isNotBlank() && it != "null" },
            typeId = offer.optInt("type_id", 0).takeIf { it > 0 },
            unitId = offer.optInt("unit_id", 0).takeIf { it > 0 },
            catalogCurrency = offer.optString("currency_id", "").takeIf { it.isNotBlank() && it != "null" },
            basePriceMinor = basePriceMinor,
            taxId = offer.optInt("tax_id", 0).takeIf { it > 0 }
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
                val priceMinor = parsePriceMinor(attrs["price"].orEmpty())
                val price = (priceMinor / 100L).coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
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
                    gcode = if (category == "coffee") "Coffee-$offerId" else null,
                    priceMinor = priceMinor
                )
            }
            .filter { it.category == "coffee" || it.category == "micromarket" }
            .distinctBy { it.name.lowercase(Locale.ROOT) + "|" + it.priceMinor + "|" + it.volume }
            .toMutableList()

        if (offers.none { it.category == "micromarket" }) {
            offers.add(Product("local-food-1", "local-food-1", "Сэндвич", "1 шт.", 180, "micromarket", true, heat = true))
        }
        return offers.ifEmpty { fallbackProducts() }
    }

    private fun readCatalogCache(): ParsedCatalog? = synchronized(CATALOG_CACHE_LOCK) {
        for (file in listOf(cacheFile, File(cacheFile.path + ".bak"))) {
            val parsed = try { parseCatalogZip(file.readBytes()) } catch (_: Exception) { null }
            if (parsed?.structureValid == true) return@synchronized parsed
        }
        null
    }

    private fun persistValidatedCatalog(zipBytes: ByteArray) = synchronized(CATALOG_CACHE_LOCK) {
        val validated = parseCatalogZip(zipBytes)
        if (!validated.structureValid) throw IllegalStateException("INVALID_CATALOG_STRUCTURE")
        val atomic = android.util.AtomicFile(cacheFile)
        var stream: java.io.FileOutputStream? = null
        try {
            stream = atomic.startWrite()
            stream.write(zipBytes)
            stream.fd.sync()
            val candidate = cacheFile
            val reparsed = parseCatalogZip(candidate.readBytes())
            if (!reparsed.structureValid) throw IllegalStateException("INVALID_CATALOG_STRUCTURE")
            atomic.finishWrite(stream)
        } catch (e: Exception) {
            if (stream != null) atomic.failWrite(stream)
            throw e
        }
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
        val record = bindingRecord ?: return IretailApiConfig(enabled = true)
        val identity = BindingRecordPolicy.identity(record)
        val channel = BindingRecordPolicy.configuration(record)
        val credentials = BindingCredentials.from(record.getJSONObject("credentials"))
        return IretailApiConfig(
            enabled = true, baseUrl = DeviceBindingProtocol.BASE_URL,
            login = credentials.username, password = credentials.password,
            clientId = credentials.clientId, clientSecret = credentials.clientSecret,
            profileId = DeviceBindingProtocol.id(channel.opt("profile_id")),
            channelId = identity.channelId,
            currencyId = DeviceBindingProtocol.id(channel.getJSONObject("currency").opt("id")),
            deviceCode = record.getString("device_code_encoded"), deviceId = identity.deviceId
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

    private fun safeCatalogFailureReason(error: Exception): String {
        if (error is AuthenticationRejectedException) return "REJECTED"
        val httpCode = Regex("HTTP\\s+(\\d{3})").find(error.message.orEmpty())?.groupValues?.getOrNull(1)
        if (!httpCode.isNullOrBlank()) return "HTTP_$httpCode"
        return when (error) {
            is java.net.UnknownHostException -> "UNKNOWN_HOST"
            is java.net.SocketTimeoutException -> "TIMEOUT"
            is java.net.ConnectException -> "CONNECT"
            is javax.net.ssl.SSLHandshakeException -> "SSL_HANDSHAKE"
            is javax.net.ssl.SSLPeerUnverifiedException -> "SSL_PEER_UNVERIFIED"
            is javax.net.ssl.SSLProtocolException -> "SSL_PROTOCOL"
            is javax.net.ssl.SSLKeyException -> "SSL_KEY"
            is javax.net.ssl.SSLException -> "SSL"
            is org.json.JSONException -> "JSON"
            else -> error.javaClass.simpleName.take(64).ifBlank { "ERROR" }
        }
    }

    private fun safeCatalogFailureDetail(error: Throwable): String {
        val classes = mutableListOf<String>()
        var current: Throwable? = error
        var depth = 0
        while (current != null && depth < 6) {
            val name = current.javaClass.simpleName.take(64).ifBlank { "Throwable" }
            if (classes.lastOrNull() != name) classes.add(name)
            current = current.cause
            depth++
        }
        return classes.joinToString(">").take(240).ifBlank { "unknown" }
    }

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
        val clientSecret: String = "",
        val profileId: String = "",
        val channelId: String = "",
        val currencyId: String = "",
        val deviceCode: String = "",
        val deviceId: String = ""
    )

    private data class ParsedCatalog(
        val products: List<Product>,
        val categoriesCount: Int,
        val offersCount: Int,
        val structureValid: Boolean
    )

    private class CatalogStageException(
        val stage: String,
        val safeReason: String,
        val safeDetail: String
    ) : IllegalStateException("$stage:$safeReason:$safeDetail")

    private class AuthenticationRejectedException : IllegalStateException("authentication rejected")
}

class LocalRetailOrderGateway(private val canCreateOrder: () -> Boolean = { DeviceBindingAccess.isReady() }) {
    private var sequence = 1000
    private var activeOrder: RuntimeOrder? = null

    fun createOrder(lines: List<CartLine>, grossAmountMinor: Long, ibonusDiscountMinor: Long = 0L, loyalty: LocalLoyaltyGateway? = null): RuntimeOrder {
        check(canCreateOrder()) { "UNBOUND_ORDER_BLOCKED" }
        val number = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT).format(Date()) + "-" + (++sequence)
        val safeGrossMinor = grossAmountMinor.coerceAtLeast(0L)
        // This gateway has no proof of a server-authorized bonus redemption.
        // Keep the compatibility argument, but never trust it as an approved discount.
        val safeDiscountMinor = 0L
        val payableMinor = (safeGrossMinor - safeDiscountMinor).coerceAtLeast(0L)
        val order = RuntimeOrder(
            localId = sequence.toString(),
            externalNumber = number,
            amount = (payableMinor / 100L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            items = lines.map { CartLine(it.product, it.quantity, it.ownCup, it.syrupAdded, it.syrupName) },
            grossAmount = (safeGrossMinor / 100L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            ibonusDiscountSum = (safeDiscountMinor / 100L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            loyaltyExternalId = loyalty?.externalId,
            loyaltyBalanceLabel = loyalty?.balanceLabel,
            amountMinor = payableMinor,
            grossAmountMinor = safeGrossMinor,
            ibonusDiscountMinor = safeDiscountMinor
        )
        activeOrder = order
        return order
    }

    fun startPayment(method: PaymentMethod): OperationResult {
        if (!canCreateOrder()) return OperationResult.ERROR
        val order = activeOrder ?: return OperationResult.ERROR
        order.status = OrderStatus.PAYMENT_STARTED
        order.paymentMethod = method
        return OperationResult.SUCCESS
    }

    fun markPaymentConfirmed(): OperationResult {
        if (!canCreateOrder()) return OperationResult.ERROR
        val order = activeOrder ?: return OperationResult.ERROR
        order.status = OrderStatus.PAID
        order.fiscalReceiptUrl = null
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
    fun confirmCupPlaced(): DeviceCommandResult =
        DeviceCommandResult(false, "Подтверждение стакана пока не подключено к реальному исполнителю", 0)

    fun dispenseCoffee(order: RuntimeOrder?): DeviceCommandResult {
        val count = order?.items?.sumOf { it.quantity } ?: 0
        return DeviceCommandResult(false, "Выдача $count поз. не запускалась: исполнитель оборудования не подключён", 0)
    }

    fun heatFood(): DeviceCommandResult =
        DeviceCommandResult(false, "Разогрев не запускался: исполнитель оборудования не подключён", 0)
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
        if (!result.success || !result.loyaltyActive) {
            clear()
            return
        }
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
        // Read-only loyalty stage: caller-supplied amount cannot authorize redemption.
        bonusApplied = 0
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
