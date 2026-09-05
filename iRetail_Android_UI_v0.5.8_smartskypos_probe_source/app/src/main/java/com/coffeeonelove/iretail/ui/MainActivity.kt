package com.coffeeonelove.iretail.ui

import android.app.Activity
import android.graphics.Color
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.ColorDrawable
import android.content.res.Configuration
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.util.TypedValue
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import kotlin.math.roundToInt
import kotlin.math.min
import kotlin.math.max
import java.util.Locale
import java.net.URL
import java.net.HttpURLConnection

class MainActivity : Activity() {
    private val green = 0xFF59BC48.toInt()
    private val dark = 0xFF333333.toInt()
    private val blueGray = 0xFF6D8297.toInt()
    private val red = 0xFFE95B5B.toInt()
    private val panelWhite = 0xFFFFFFFF.toInt()
    private val panelSoft = 0xFFF7F7F7.toInt()

    private val baseWidth = 1080f
    private val baseHeight = 1920f

    private lateinit var root: FrameLayout
    private lateinit var screenImage: ImageView
    private lateinit var hotspotLayer: FrameLayout
    private lateinit var dynamicLayer: FrameLayout
    private lateinit var statusLabel: TextView

    private val handler = Handler(Looper.getMainLooper())
    private val orderGateway = LocalRetailOrderGateway()
    private val machineGateway = LocalMachineGateway()
    private val loyaltyGateway = LocalLoyaltyGateway()
    private val imageCache = mutableMapOf<String, Bitmap>()

    private lateinit var contentRepository: IretailContentRepository
    private var catalog: List<Product> = emptyList()
    private var paymentMethods: List<PayMethod> = emptyList()
    private var catalogDataSource = "content XML"
    private var catalogMessage = "локальный XML-макет"
    private var catalogApiOffersCount = 0
    private var catalogApiCoffeeCount = 0
    private var catalogApiChannelId = ""
    private var catalogHasApiButNoCoffee = false
    private val cart = mutableListOf<CartLine>()
    private val screenHistory = mutableListOf<String>()

    private var currentScreen = "SCREEN_SAVER_COFFEE"
    private var pendingProduct: Product? = null
    private var pendingOwnCup = false
    private var pendingSyrup = false
    private var pendingSyrupName: String? = null
    private var lastPaymentMethod = PaymentMethod.CARD
    private var editingLineIndex = -1
    private var demoStatusVisible = false
    private var couponInput = ""
    private var loyaltyInput = ""
    private var couponApplied = false
    private var recommendationPopupTitle: String? = null
    private var recommendationsHidden = false
    private var languagePopupVisible = false
    private var currentLanguage = "RU"

    private val screenDrawables = mapOf(
        "SCREEN_SAVER_COFFEE" to "screen_saver_coffee",
        "SCREEN_SAVER_LOYALTY" to "screen_saver_loyalty",
        "SCREEN_PROMO_DOUBLE_CASHBACK" to "screen_promo_double_cashback",
        "CATALOG_DEFAULT" to "catalog_default",
        "CATALOG_DEFAULT_VARIANT_1" to "catalog_default_1",
        "CATALOG_DEFAULT_VARIANT_2" to "catalog_default_2",
        "CATALOG_DEFAULT_VARIANT_3" to "catalog_default_3",
        "CATALOG_DEFAULT_VARIANT_4" to "catalog_default_4",
        "CATALOG_WITH_COUPON_AND_FOOD" to "catalog_coupon_food",
        "CATALOG_WITH_COUPON_AND_FOOD_2" to "catalog_coupon_food_1",
        "CATALOG_NEW_ORDER" to "catalog_new_order",
        "ITEM_ADD" to "item_add",
        "ITEM_EDIT" to "item_edit",
        "COUPON_ADD" to "coupon_add",
        "SEARCH_EMPTY_INPUT" to "search_empty_input",
        "SEARCH_COCO" to "search_coco",
        "SEARCH_AMER" to "search_amer",
        "SEARCH_RESULT" to "search_result",
        "SEARCH_NOTHING" to "search_nothing",
        "FOOD_SCAN" to "food_scan",
        "HEAT_FOOD_1" to "heat_food_1",
        "HEAT_FOOD_2" to "heat_food_2",
        "HEAT_FOOD_3" to "heat_food_3",
        "HEAT_FOOD_DONE" to "heat_food_done",
        "MICROMARKET_STEP_1" to "micromarket_1",
        "MICROMARKET_STEP_2" to "micromarket_2",
        "MICROMARKET_STEP_3" to "micromarket_3",
        "TRUST_SINGLE_1" to "trust_single_1",
        "TRUST_SINGLE_2" to "trust_single_2",
        "TRUST_MULTI_1" to "trust_multi_1",
        "TRUST_MULTI_2" to "trust_multi_2",
        "TRUST_MULTI_HEAT_1" to "trust_multi_heat_1",
        "TRUST_MULTI_HEAT_2" to "trust_multi_heat_2",
        "TRUST_MULTI_HEAT_3" to "trust_multi_heat_3",
        "TRUST_PLUS_1" to "trust_plus_1",
        "TRUST_PLUS_2" to "trust_plus_2",
        "TRUST_PLUS_3" to "trust_plus_3",
        "TRUST_PLUS_MULTI_1" to "trust_plus_multi_1",
        "TRUST_PLUS_MULTI_2" to "trust_plus_multi_2",
        "TRUST_PLUS_MULTI_2_1" to "trust_plus_multi_2_1",
        "TRUST_PLUS_MULTI_2_2" to "trust_plus_multi_2_2",
        "TRUST_PLUS_MULTI_3" to "trust_plus_multi_3",
        "TRUST_PLUS_MULTI_ORDER" to "trust_plus_multi_order",
        "TRUST_PLUS_MULTI_ORDER_2" to "trust_plus_multi_order_2",
        "ORDER_DEFAULT" to "order_default",
        "ORDER_VARIANT_1" to "order_1",
        "ORDER_VARIANT_2" to "order_2",
        "ORDER_VARIANT_3" to "order_3",
        "ORDER_VARIANT_4" to "order_4",
        "YOUR_ORDER" to "your_order",
        "YOUR_ORDER_2" to "your_order_2",
        "LOYALTY_LOGIN" to "loyalty_login",
        "LOYALTY_PROFILE" to "loyalty_profile",
        "LOYALTY_PROFILE_FULL" to "loyalty_profile_full",
        "LOYALTY_SUBSCRIPTION" to "loyalty_subscription",
        "LOYALTY_GET_CARD_QR" to "loyalty_get_card_qr",
        "LOYALTY_COFFEE_SUBSCRIPTION_QR" to "loyalty_coffee_subscription_qr",
        "PAYMENT_METHOD_ALL" to "payment_method_all",
        "PAYMENT_METHOD_NO_CASH" to "payment_method_no_cash",
        "PAYMENT_POS" to "payment_pos",
        "PAYMENT_ONLINE_QR" to "payment_online_qr",
        "PAYMENT_ONLINE_CONFIRM" to "payment_online_confirm",
        "PAYMENT_CASH" to "payment_cash",
        "PAYMENT_COMPLETED" to "payment_completed",
        "RECEIPT_EMAIL_INPUT" to "receipt_email_input",
        "RECEIPT_EMAIL_COMPLETE" to "receipt_email_complete",
        "CUP_REQUIRED" to "cup_required",
        "DISPENSE_ONE_PROGRESS" to "dispense_one_progress",
        "DISPENSE_ONE_PROGRESS_ALT" to "dispense_one_progress_alt",
        "DISPENSE_TWO_PROGRESS" to "dispense_two_progress",
        "DISPENSE_THREE_PROGRESS" to "dispense_three_progress",
        "DISPENSE_THREE_PROGRESS_ALT" to "dispense_three_progress_alt",
        "ERROR_APOLOGIZE" to "error_apologize",
        "ERROR_406" to "error_406",
        "SUPPORT_INFO" to "support_info"
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN)
        hideSystemUi()
        contentRepository = IretailContentRepository(this)
        catalog = contentRepository.loadProducts()
        paymentMethods = contentRepository.loadPaymentMethods()
        buildRootView()
        openScreen("SCREEN_SAVER_COFFEE", remember = false)
        refreshCatalogFromIretail()
    }

    private fun refreshCatalogFromIretail() {
        contentRepository.refreshProductsAsync { result ->
            handler.post {
                catalogDataSource = result.source
                catalogMessage = result.message
                catalogApiChannelId = result.channelId
                if (result.success && result.products.isNotEmpty()) {
                    catalog = result.products
                    catalogApiOffersCount = result.products.size
                    catalogApiCoffeeCount = result.products.count { it.category == "coffee" }
                    catalogHasApiButNoCoffee = result.source.startsWith("I-Retail") && catalogApiCoffeeCount == 0
                    catalogMessage = if (catalogHasApiButNoCoffee) {
                        "I-Retail: канал ${result.channelId.ifBlank { "?" }} отдал ${result.offersCount} товаров, кофейных позиций не найдено"
                    } else {
                        result.message
                    }
                    if (currentScreen == "SCREEN_SAVER_COFFEE" || currentScreen == "SCREEN_SAVER_LOYALTY" || currentScreen == "SCREEN_PROMO_DOUBLE_CASHBACK") {
                        openScreen("CATALOG_DEFAULT")
                    } else {
                        rerenderCurrentScreen()
                    }
                    toast(catalogMessage)
                } else {
                    updateStatusLabel()
                }
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUi()
    }

    @Deprecated("Deprecated in Android API, still valid for minSdk 23 without AndroidX dispatcher.")
    override fun onBackPressed() {
        goBackSafely()
    }

    private fun buildRootView() {
        root = FrameLayout(this)
        screenImage = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_XY
            setBackgroundColor(Color.WHITE)
        }
        dynamicLayer = FrameLayout(this)
        hotspotLayer = FrameLayout(this)
        statusLabel = TextView(this).apply {
            setTextColor(Color.WHITE)
            setBackgroundColor(0x66000000)
            textSize = 11f
            gravity = Gravity.CENTER_VERTICAL
            setPadding(12, 4, 12, 4)
            visibility = View.GONE
        }
        root.addView(screenImage, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        root.addView(dynamicLayer, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        root.addView(hotspotLayer, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        val statusParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT)
        statusParams.gravity = Gravity.TOP
        root.addView(statusLabel, statusParams)
        setContentView(root)
    }

    private fun hideSystemUi() {
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN
    }

    private fun openScreen(screenId: String, remember: Boolean = true) {
        handler.removeCallbacksAndMessages(null)
        recommendationPopupTitle = null
        if (remember && currentScreen != screenId) screenHistory.add(currentScreen)
        currentScreen = screenId

        // Сразу очищаем живые слои: иначе на слабом устройстве или в эмуляторе на один кадр
        // смешиваются старый экран, новый PNG и новая альбомная разметка.
        dynamicLayer.removeAllViews()
        hotspotLayer.removeAllViews()
        dynamicLayer.alpha = 0f

        if (isLandscapeScreenNow()) {
            screenImage.setImageDrawable(ColorDrawable(Color.WHITE))
        } else {
            val drawableName = screenDrawables[screenId]
            val resId = if (drawableName == null) 0 else resources.getIdentifier(drawableName, "drawable", packageName)
            if (resId != 0) screenImage.setImageResource(resId) else screenImage.setImageResource(android.R.color.white)
        }

        root.post {
            renderDynamicLayer(screenId)
            renderHotspots(screenId)
            updateStatusLabel()
            applyAutoTransitions(screenId)
            dynamicLayer.animate().alpha(1f).setDuration(90L).start()
        }
        hideSystemUi()
    }

    private fun rerenderCurrentScreen() {
        root.post {
            renderDynamicLayer(currentScreen)
            renderHotspots(currentScreen)
            updateStatusLabel()
        }
    }

    private fun renderHotspots(screenId: String) {
        hotspotLayer.removeAllViews()
        val screenHotspots = when {
            languagePopupVisible -> if (isLandscapeMode()) landscapeLanguagePopupHotspots() else languagePopupHotspots()
            isLandscapeMode() -> landscapeHotspotsFor(screenId) + globalLandscapeHotspots(screenId)
            else -> hotspotsFor(screenId) + globalHotspots(screenId)
        }
        screenHotspots.forEach { hotspot ->
            val view = View(this).apply {
                setBackgroundColor(Color.TRANSPARENT)
                contentDescription = hotspot.label
                isClickable = true
                setOnClickListener { hotspot.onTap.invoke() }
                setOnLongClickListener {
                    toggleDemoStatus()
                    true
                }
            }
            hotspotLayer.addView(view, scaledLayoutParams(hotspot.rect))
        }
    }

    private fun renderDynamicLayer(screenId: String) {
        dynamicLayer.removeAllViews()
        if (isLandscapeMode()) {
            renderLandscapeScreen(screenId)
            if (languagePopupVisible) renderLandscapeLanguagePopup()
            return
        }
        when (screenId) {
            "CATALOG_DEFAULT", "CATALOG_DEFAULT_VARIANT_1", "CATALOG_DEFAULT_VARIANT_2", "CATALOG_DEFAULT_VARIANT_3", "CATALOG_DEFAULT_VARIANT_4", "CATALOG_WITH_COUPON_AND_FOOD", "CATALOG_WITH_COUPON_AND_FOOD_2", "CATALOG_NEW_ORDER" -> renderCatalogOverlay()
            "ITEM_ADD", "ITEM_EDIT" -> renderSelectedProductOverlay(screenId == "ITEM_EDIT")
            "ORDER_DEFAULT", "ORDER_VARIANT_1", "ORDER_VARIANT_2", "ORDER_VARIANT_3", "ORDER_VARIANT_4", "YOUR_ORDER", "YOUR_ORDER_2", "TRUST_PLUS_MULTI_ORDER", "TRUST_PLUS_MULTI_ORDER_2" -> renderCartOverlay(full = true)
            "COUPON_ADD" -> renderCouponInputOverlay()
            "LOYALTY_LOGIN" -> renderLoyaltyInputOverlay()
            "LOYALTY_PROFILE", "LOYALTY_PROFILE_FULL", "LOYALTY_SUBSCRIPTION" -> renderLoyaltyProfileOverlay()
            "LOYALTY_GET_CARD_QR", "LOYALTY_COFFEE_SUBSCRIPTION_QR" -> renderLoyaltyGetCardOverlay()
            "PAYMENT_METHOD_ALL", "PAYMENT_METHOD_NO_CASH" -> renderPaymentMethodsOverlay()
            "PAYMENT_POS", "PAYMENT_CASH", "PAYMENT_ONLINE_QR", "PAYMENT_ONLINE_CONFIRM" -> renderPaymentProgressOverlay()
            "PAYMENT_COMPLETED" -> renderPaymentCompletedOverlay()
        }
        if (languagePopupVisible) renderLanguagePopup()
    }

    private fun isLandscapeMode(): Boolean {
        return root.width > root.height && root.width > 0 && root.height > 0
    }

    private fun isLandscapeScreenNow(): Boolean {
        return isLandscapeMode() || resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
    }

    private fun designWidth(): Float = if (isLandscapeMode()) 1920f else baseWidth
    private fun designHeight(): Float = if (isLandscapeMode()) 1080f else baseHeight

    private fun scaledLayoutParams(rect: RectSpec): FrameLayout.LayoutParams {
        val actualWidth = root.width.coerceAtLeast(1).toFloat()
        val actualHeight = root.height.coerceAtLeast(1).toFloat()
        val xScale = actualWidth / designWidth()
        val yScale = actualHeight / designHeight()
        return FrameLayout.LayoutParams(
            (rect.width * xScale).roundToInt(),
            (rect.height * yScale).roundToInt()
        ).apply {
            leftMargin = (rect.x * xScale).roundToInt()
            topMargin = (rect.y * yScale).roundToInt()
        }
    }

    private fun uiScale(): Float {
        val actualWidth = root.width.coerceAtLeast(1).toFloat()
        val actualHeight = root.height.coerceAtLeast(1).toFloat()
        return min(actualWidth / designWidth(), actualHeight / designHeight()).coerceAtLeast(0.45f)
    }

    private fun scaledTextSize(value: Float): Float = value * uiScale() * 1.18f
    private fun scaledRadius(value: Float): Float = value * uiScale()
    private fun scaledPadding(value: Int): Int = (value * uiScale()).roundToInt().coerceAtLeast(1)
    private fun px(value: Int): Int = (value * uiScale()).roundToInt().coerceAtLeast(1)
    private fun designPxX(value: Int): Int {
        val actualWidth = root.width.coerceAtLeast(1).toFloat()
        return (value * (actualWidth / designWidth())).roundToInt().coerceAtLeast(1)
    }
    private fun designPxY(value: Int): Int {
        val actualHeight = root.height.coerceAtLeast(1).toFloat()
        return (value * (actualHeight / designHeight())).roundToInt().coerceAtLeast(1)
    }

    private fun addLabel(text: String, rect: RectSpec, textSize: Float, color: Int, gravity: Int = Gravity.CENTER, bold: Boolean = false, background: Int = Color.TRANSPARENT): TextView {
        val label = TextView(this).apply {
            this.text = text
            setTextSize(TypedValue.COMPLEX_UNIT_PX, scaledTextSize(textSize))
            setTextColor(color)
            this.gravity = gravity
            includeFontPadding = false
            setPadding(scaledPadding(8), scaledPadding(4), scaledPadding(8), scaledPadding(4))
            setBackgroundColor(background)
            if (bold) setTypeface(Typeface.DEFAULT, Typeface.BOLD)
        }
        dynamicLayer.addView(label, scaledLayoutParams(rect))
        return label
    }

    private fun addButton(text: String, rect: RectSpec, onTap: () -> Unit, background: Int = 0xFF59BC48.toInt(), color: Int = Color.WHITE): TextView {
        val label = addLabel(text, rect, 24f, color, Gravity.CENTER, false, background)
        label.isClickable = true
        label.setOnClickListener { onTap.invoke() }
        return label
    }



    private fun addBox(rect: RectSpec, color: Int = Color.WHITE, corner: Float = 0f): View {
        val box = View(this)
        if (corner > 0f) {
            box.background = GradientDrawable().apply {
                setColor(color)
                cornerRadius = scaledRadius(corner)
            }
        } else {
            box.setBackgroundColor(color)
        }
        dynamicLayer.addView(box, scaledLayoutParams(rect))
        return box
    }

    private fun addRoundedLabel(text: String, rect: RectSpec, textSize: Float, color: Int, gravity: Int = Gravity.CENTER, bold: Boolean = false, background: Int = Color.TRANSPARENT, corner: Float = 16f): TextView {
        val label = TextView(this).apply {
            this.text = text
            setTextSize(TypedValue.COMPLEX_UNIT_PX, scaledTextSize(textSize))
            setTextColor(color)
            this.gravity = gravity
            includeFontPadding = false
            setPadding(scaledPadding(10), scaledPadding(4), scaledPadding(10), scaledPadding(4))
            if (bold) setTypeface(Typeface.DEFAULT, Typeface.BOLD)
            if (background != Color.TRANSPARENT) {
                this.background = GradientDrawable().apply {
                    setColor(background)
                    cornerRadius = scaledRadius(corner)
                }
            }
        }
        dynamicLayer.addView(label, scaledLayoutParams(rect))
        return label
    }

    private fun addImage(drawableName: String, rect: RectSpec): ImageView {
        val image = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.TRANSPARENT)
        }
        val resId = resources.getIdentifier(drawableName, "drawable", packageName)
        if (resId != 0) image.setImageResource(resId)
        dynamicLayer.addView(image, scaledLayoutParams(rect))
        return image
    }

    private fun visualCoffeeProducts(): List<Product> {
        val remoteCoffee = catalog.filter { it.available && it.category == "coffee" }
        val preferred = remoteCoffee.ifEmpty { localCoffeeFallbackProducts() }
        fun pick(vararg words: String): Product? {
            return preferred.firstOrNull { product ->
                val source = (product.name + " " + product.volume).lowercase(Locale.ROOT).replace("ё", "е")
                words.all { source.contains(it.lowercase(Locale.ROOT).replace("ё", "е")) }
            }
        }
        val ordered = listOfNotNull(
            pick("капучино", "200"),
            pick("американо", "200"),
            pick("какао", "200"),
            pick("флэт", "200"),
            pick("американо", "xl"),
            pick("капучино", "xl"),
            pick("эспрессо"),
            pick("латте")
        ).distinctBy { it.id }
        val rest = preferred.filterNot { p -> ordered.any { it.id == p.id } }
        return ordered + rest
    }

    private fun localCoffeeFallbackProducts(): List<Product> = listOf(
        Product("local-cappuccino-200", "local-cappuccino-200", "Капучино", "200мл", 149, "coffee", true, gcode = "Coffee-02"),
        Product("local-americano-200", "local-americano-200", "Американо", "200мл", 149, "coffee", true, gcode = "Coffee-01"),
        Product("local-cacao-200", "local-cacao-200", "Какао", "200мл", 179, "coffee", true, gcode = "Coffee-03"),
        Product("local-flat-white-200", "local-flat-white-200", "Флэт Уайт", "200мл", 179, "coffee", true, gcode = "Coffee-04"),
        Product("local-americano-xl", "local-americano-xl", "Американо XL", "300мл", 189, "coffee", true, gcode = "Coffee-05"),
        Product("local-cappuccino-xl", "local-cappuccino-xl", "Капучино XL", "300мл", 199, "coffee", true, gcode = "Coffee-06"),
        Product("local-espresso", "local-espresso", "Эспрессо", "80мл", 129, "coffee", true, gcode = "Coffee-07"),
        Product("local-latte", "local-latte", "Латте", "300мл", 199, "coffee", true, gcode = "Coffee-08")
    )

    private fun productImageName(product: Product): String {
        val source = (product.name + " " + product.volume).lowercase(Locale.ROOT).replace("ё", "е")
        return when {
            source.contains("капучино") && source.contains("xl") -> "product_cappuccino_xl"
            source.contains("капучино") -> "product_cappuccino"
            source.contains("американо") && source.contains("xl") -> "product_americano_xl"
            source.contains("американо") -> "product_americano"
            source.contains("какао") -> "product_cacao"
            source.contains("флэт") || source.contains("flat") -> "product_flat_white"
            source.contains("эспрессо") || source.contains("espresso") -> "product_espresso"
            source.contains("латте") || source.contains("latte") -> "product_latte"
            else -> "product_cappuccino"
        }
    }

    private fun addProductImage(product: Product, rect: RectSpec): ImageView {
        val image = addImage(productImageName(product), rect)
        setProductImage(image, product)
        return image
    }

    private fun setProductImage(image: ImageView, product: Product) {
        val url = product.imageUrl
        val localResId = resources.getIdentifier(productImageName(product), "drawable", packageName)
        if (localResId != 0) image.setImageResource(localResId)
        if (url.isNullOrBlank()) return
        imageCache[url]?.let {
            image.setImageBitmap(it)
            return
        }
        Thread {
            val bitmap = try {
                val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 6000
                    readTimeout = 9000
                }
                conn.inputStream.use { BitmapFactory.decodeStream(it) }
            } catch (_: Exception) {
                null
            }
            if (bitmap != null) {
                imageCache[url] = bitmap
                handler.post { image.setImageBitmap(bitmap) }
            }
        }.start()
    }

    private fun normalizeProductName(product: Product): String {
        return product.name.replace(Regex("\\s+"), " ").trim()
    }



    private fun renderCatalogOverlay() {
        renderPortraitProductGrid()
        if (cart.isNotEmpty()) {
            renderCartOverlay(full = false)
        }
        if (couponApplied) {
            addRoundedLabel("Купон применён", RectSpec(55, 245, 320, 45), 17f, green, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        }
        addRoundedLabel(catalogStatusText(), RectSpec(595, 250, 440, 38), 13f, blueGray, Gravity.RIGHT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT, 8f)
    }

    private fun catalogStatusText(): String {
        return if (catalogHasApiButNoCoffee) {
            "I-Retail: кофе не найдено, показан макет"
        } else {
            catalogDataSource
        }
    }

    private fun catalogVisibleStatusText(): String {
        if (catalogHasApiButNoCoffee) {
            return "Канал ${catalogApiChannelId.ifBlank { "?" }} отдал ${catalogApiOffersCount} товаров, но среди них нет кофе. Показан кофейный набор из макета."
        }
        return if (!catalogDataSource.startsWith("I-Retail ZIP")) {
            val clean = catalogMessage.replace(Regex("\\s+"), " ").trim()
            if (clean.isBlank()) "Источник: локальный макет" else "Источник: локальный макет — $clean"
        } else {
            ""
        }
    }

    private fun renderPortraitProductGrid() {
        val products = visualCoffeeProducts()
        val gridRect = if (cart.isEmpty()) RectSpec(20, 290, 1040, 840) else RectSpec(20, 290, 1040, 760)
        renderProductScrollGrid(
            products = products,
            rect = gridRect,
            columns = 4,
            cardW = 250,
            cardH = 400,
            gapX = 15,
            gapY = 22,
            imageH = 180,
            titleTextSize = 17f,
            priceTextSize = 18f
        )
        if (products.size > 8) addCatalogScrollHint(gridRect, products.size)
        val statusText = catalogVisibleStatusText()
        if (statusText.isNotBlank()) {
            val y = if (cart.isEmpty()) 1148 else 1064
            addRoundedLabel(statusText, RectSpec(40, y, 1000, 54), 15f, blueGray, Gravity.CENTER, false, 0xFFF8F8F8.toInt(), 12f)
        }
    }

    private fun renderProductScrollGrid(
        products: List<Product>,
        rect: RectSpec,
        columns: Int,
        cardW: Int,
        cardH: Int,
        gapX: Int,
        gapY: Int,
        imageH: Int,
        titleTextSize: Float,
        priceTextSize: Float
    ) {
        val rowsCount = if (products.isEmpty()) 0 else (products.size + columns - 1) / columns
        val contentDesignHeight = rowsCount * cardH + max(0, rowsCount - 1) * gapY
        val needsScroll = contentDesignHeight > rect.height

        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, px(if (needsScroll) 14 else 0), px(if (needsScroll) 24 else 0))
        }

        products.chunked(columns).forEachIndexed { rowIndex, rowProducts ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
            }
            rowProducts.forEachIndexed { columnIndex, product ->
                val card = createProductCardView(product, cardW, cardH, imageH, titleTextSize, priceTextSize)
                val params = LinearLayout.LayoutParams(designPxX(cardW), designPxY(cardH)).apply {
                    if (columnIndex < rowProducts.lastIndex) rightMargin = designPxX(gapX)
                }
                row.addView(card, params)
            }
            val rowParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                if (rowIndex < rowsCount - 1) bottomMargin = designPxY(gapY)
            }
            list.addView(row, rowParams)
        }

        if (needsScroll) {
            val scrollView = ScrollView(this).apply {
                isVerticalScrollBarEnabled = true
                isScrollbarFadingEnabled = false
                scrollBarStyle = View.SCROLLBARS_INSIDE_INSET
                overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
                setBackgroundColor(Color.TRANSPARENT)
                clipToPadding = false
                setPadding(0, 0, px(12), 0)
            }
            scrollView.addView(list, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT))
            addScaledView(scrollView, rect)
        } else {
            addScaledView(list, rect)
        }
    }

    private fun createProductCardView(product: Product, cardW: Int, cardH: Int, imageH: Int, titleTextSize: Float, priceTextSize: Float): FrameLayout {
        val card = FrameLayout(this).apply {
            isClickable = true
            background = GradientDrawable().apply {
                setColor(0xFFFAFAFA.toInt())
                cornerRadius = scaledRadius(10f)
            }
            setOnClickListener { selectProduct(product); openScreen("ITEM_ADD") }
        }

        val image = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.TRANSPARENT)
        }
        setProductImage(image, product)
        card.addView(image, childParams(RectSpec(25, 20, cardW - 50, imageH)))

        val compactCard = cardH <= 330
        val titleY = imageH + if (compactCard) 24 else 30
        val titleH = if (compactCard) 40 else 58
        val volumeY = titleY + titleH + if (compactCard) 8 else 6
        val priceY = volumeY + if (product.volume.isBlank()) 30 else 36

        val title = TextView(this).apply {
            text = shortProductName(product).uppercase(Locale.ROOT)
            setTextSize(TypedValue.COMPLEX_UNIT_PX, scaledTextSize(titleTextSize))
            setTextColor(dark)
            gravity = Gravity.CENTER
            includeFontPadding = false
            setSingleLine(false)
            maxLines = if (compactCard) 2 else 2
            setTypeface(Typeface.DEFAULT, Typeface.BOLD)
            setPadding(px(4), 0, px(4), 0)
        }
        card.addView(title, childParams(RectSpec(10, titleY, cardW - 20, titleH)))

        val volume = TextView(this).apply {
            text = product.volume.replace("мл", " мл")
            setTextSize(TypedValue.COMPLEX_UNIT_PX, scaledTextSize(13f))
            setTextColor(blueGray)
            gravity = Gravity.CENTER
            includeFontPadding = false
            visibility = if (product.volume.isBlank()) View.GONE else View.VISIBLE
        }
        card.addView(volume, childParams(RectSpec(12, volumeY, cardW - 24, 28)))

        val price = TextView(this).apply {
            text = formatMoney(product.price)
            setTextSize(TypedValue.COMPLEX_UNIT_PX, scaledTextSize(priceTextSize))
            setTextColor(green)
            gravity = Gravity.CENTER
            includeFontPadding = false
            setTypeface(Typeface.DEFAULT, Typeface.BOLD)
        }
        card.addView(price, childParams(RectSpec(12, priceY, cardW - 24, 40)))
        return card
    }

    private fun childParams(rect: RectSpec): FrameLayout.LayoutParams {
        return FrameLayout.LayoutParams(designPxX(rect.width), designPxY(rect.height)).apply {
            leftMargin = designPxX(rect.x)
            topMargin = designPxY(rect.y)
        }
    }

    private fun addCatalogScrollHint(rect: RectSpec, count: Int) {
        addBox(RectSpec(rect.x + rect.width - 20, rect.y + 16, 10, rect.height - 32), 0xFF9DB8D4.toInt(), 5f)
        addRoundedLabel("↕", RectSpec(rect.x + rect.width - 64, rect.y + 24, 42, 70), 26f, Color.WHITE, Gravity.CENTER, true, 0xFF7E8FA2.toInt(), 18f)
        addRoundedLabel("Листайте меню • $count поз.", RectSpec(rect.x + rect.width - 300, rect.y - 38, 290, 34), 14f, blueGray, Gravity.RIGHT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT, 0f)
    }

    private fun shortProductName(product: Product): String {
        val name = normalizeProductName(product)
        return if (name.length > 34) name.take(31).trimEnd() + "…" else name
    }

    private fun renderSelectedProductOverlay(editMode: Boolean) {
        val product = pendingProduct ?: visualCoffeeProducts().firstOrNull() ?: catalog.firstOrNull() ?: return

        // Закрываем статичную карточку товара из PNG и рисуем живую карточку поверх неё.
        addBox(RectSpec(360, 330, 360, 420), Color.WHITE, 8f)
        addProductImage(product, RectSpec(405, 335, 270, 235))
        addLabel(normalizeProductName(product).uppercase(), RectSpec(285, 575, 510, 76), 32f, dark, Gravity.CENTER, true, Color.WHITE)
        addLabel(product.volume.replace("мл", " мл"), RectSpec(405, 650, 270, 52), 21f, blueGray, Gravity.CENTER, false, Color.WHITE)
        addLabel(formatMoney(product.price), RectSpec(405, 700, 270, 58), 26f, dark, Gravity.CENTER, true, Color.WHITE)

        // Свой стакан: одна понятная строка вместо дублей из исходной картинки.
        addBox(RectSpec(250, 748, 580, 92), Color.WHITE, 8f)
        addLabel("У меня свой стакан", RectSpec(310, 765, 380, 52), 22f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.WHITE)
        addRoundedLabel(if (pendingOwnCup) "✓" else "", RectSpec(690, 765, 92, 52), 24f, Color.WHITE, Gravity.CENTER, true, if (pendingOwnCup) green else 0xFFE4E4E4.toInt(), 26f)

        // Сиропы: полностью перерисовываем блок, чтобы не было наложений и обрезанных слов.
        addBox(RectSpec(180, 870, 720, 510), panelSoft, 28f)
        val selected = pendingSyrupName
        val header = if (selected == null) "ДОБАВИТЬ СИРОП" else "СИРОП ДОБАВЛЕН"
        addLabel(header, RectSpec(250, 900, 580, 58), 22f, dark, Gravity.CENTER, true, Color.TRANSPARENT)

        val syrupRows = listOf("Ваниль", "Карамель", "Кокос", "Сахар")
        syrupRows.forEachIndexed { index, name ->
            val y = 990 + index * 82
            val isSelected = selected == name || (selected == null && false)
            addLabel(name, RectSpec(285, y, 290, 58), 22f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
            addRoundedLabel(if (isSelected) "✓" else "+", RectSpec(585, y + 5, 62, 52), 26f, if (isSelected) Color.WHITE else green, Gravity.CENTER, true, if (isSelected) green else Color.WHITE, 12f)
            if (isSelected) {
                addRoundedLabel("Удалить", RectSpec(665, y + 4, 150, 52), 20f, Color.WHITE, Gravity.CENTER, true, red, 10f)
            }
        }
        if (selected != null && syrupRows.none { it == selected }) {
            addRoundedLabel("Добавлен сироп", RectSpec(300, 1310, 500, 52), 17f, green, Gravity.CENTER, true, Color.WHITE, 10f)
        }

        if (editMode) {
            addRoundedLabel("Редактирование позиции", RectSpec(240, 1388, 600, 52), 20f, blueGray, Gravity.CENTER, true, Color.TRANSPARENT)
        }
    }

    private fun renderCartOverlay(full: Boolean) {
        if (cart.isEmpty()) return
        val itemCount = cart.sumOf { it.quantity }
        val total = cartTotal()

        if (full) {
            addBox(RectSpec(0, 120, 1080, 1660), Color.WHITE, 0f)
            addBox(RectSpec(45, 230, 990, 1240), Color.WHITE, 26f)
            addLabel("ВАШ ЗАКАЗ", RectSpec(250, 245, 580, 65), 28f, dark, Gravity.CENTER, true, Color.TRANSPARENT)

            val listRect = RectSpec(65, 335, 945, 820)
            addCartScrollList(listRect, rowDesignHeight = 140, compact = false)
            if (cart.size > 5) addScrollHint(listRect)

            addLabel("Сумма", RectSpec(80, 1210, 300, 55), 23f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
            loyaltyOrderNote(full = true)?.let { note ->
                addLabel(note, RectSpec(335, 1182, 655, 42), 16f, blueGray, Gravity.RIGHT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
            }
            addLabel(formatMoney(total), RectSpec(630, 1222, 360, 70), 35f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
            addRoundedLabel("← Назад", RectSpec(70, 1365, 240, 88), 22f, Color.WHITE, Gravity.CENTER, true, blueGray, 14f)
            addTrashButton(RectSpec(340, 1365, 120, 88)) { clearOrder() }
            addRoundedLabel("Оплатить", RectSpec(500, 1365, 490, 88), 24f, Color.WHITE, Gravity.CENTER, true, green, 14f)
        } else {
            addBox(RectSpec(0, 1060, 1080, 640), Color.WHITE, 30f)
            addLabel("ВАШ ЗАКАЗ", RectSpec(250, 1086, 580, 55), 23f, dark, Gravity.CENTER, true, Color.TRANSPARENT)

            val listRect = RectSpec(55, 1160, 970, 235)
            addCartScrollList(listRect, rowDesignHeight = 105, compact = true)
            if (cart.size > 2) addScrollHint(listRect)

            addLabel("Сумма", RectSpec(55, 1410, 250, 55), 22f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
            loyaltyOrderNote(full = false)?.let { note -> addLabel(note, RectSpec(260, 1375, 750, 42), 16f, blueGray, Gravity.RIGHT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT) }
            addLabel(formatMoney(total), RectSpec(630, 1408, 380, 75), 34f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
            addTrashButton(RectSpec(45, 1510, 125, 104)) { clearOrder() }
            addRoundedLabel("Оплатить\n$itemCount товар(ов) • ${formatMoney(total)}", RectSpec(190, 1510, 835, 104), 21f, Color.WHITE, Gravity.CENTER, true, green, 14f)
            if (couponApplied) addRoundedLabel("Купон применён", RectSpec(55, 1630, 340, 45), 16f, green, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        }
    }

    private fun addScaledView(view: View, rect: RectSpec) {
        dynamicLayer.addView(view, scaledLayoutParams(rect))
    }

    private fun addScrollHint(rect: RectSpec) {
        addBox(RectSpec(rect.x + rect.width + 7, rect.y + 10, 10, rect.height - 20), 0xFF6AA3E8.toInt(), 5f)
    }

    private fun addTrashButton(rect: RectSpec, onTap: () -> Unit) {
        val button = FrameLayout(this).apply {
            isClickable = true
            setOnClickListener { onTap.invoke() }
            background = GradientDrawable().apply {
                setColor(red)
                cornerRadius = scaledRadius(14f)
            }
        }
        val iconSize = px((min(rect.width, rect.height) * 0.50f).roundToInt())
        val icon = TrashIconView(this).apply {
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val iconParams = FrameLayout.LayoutParams(iconSize, iconSize).apply {
            gravity = Gravity.CENTER
        }
        button.addView(icon, iconParams)
        addScaledView(button, rect)
    }

    private inner class TrashIconView(context: android.content.Context) : View(context) {
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = px(4).toFloat()
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0f || h <= 0f) return
            val left = w * 0.24f
            val right = w * 0.76f
            val top = h * 0.34f
            val bottom = h * 0.84f
            val lidY = h * 0.27f
            val handleY = h * 0.17f

            canvas.drawLine(w * 0.20f, lidY, w * 0.80f, lidY, strokePaint)
            canvas.drawLine(w * 0.42f, handleY, w * 0.58f, handleY, strokePaint)
            canvas.drawLine(w * 0.46f, handleY, w * 0.42f, lidY, strokePaint)
            canvas.drawLine(w * 0.54f, handleY, w * 0.58f, lidY, strokePaint)

            val body = Path().apply {
                moveTo(left, top)
                lineTo(right, top)
                lineTo(right - w * 0.06f, bottom)
                lineTo(left + w * 0.06f, bottom)
                close()
            }
            canvas.drawPath(body, strokePaint)
            canvas.drawLine(w * 0.42f, top + h * 0.11f, w * 0.42f, bottom - h * 0.10f, strokePaint)
            canvas.drawLine(w * 0.58f, top + h * 0.11f, w * 0.58f, bottom - h * 0.10f, strokePaint)

            // Небольшой белый акцент внизу делает корзину читаемой на маленьких кнопках Android 6.
            canvas.drawCircle(w * 0.50f, bottom + h * 0.03f, max(1f, w * 0.018f), fillPaint)
        }
    }

    private fun addCartScrollList(rect: RectSpec, rowDesignHeight: Int, compact: Boolean) {
        val scrollView = ScrollView(this).apply {
            isVerticalScrollBarEnabled = true
            isScrollbarFadingEnabled = false
            scrollBarStyle = View.SCROLLBARS_INSIDE_INSET
            setBackgroundColor(Color.TRANSPARENT)
            overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
        }
        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, px(18), 0)
        }
        cart.forEachIndexed { index, line ->
            list.addView(createCartRowView(line, index, rect.width - 22, rowDesignHeight, compact))
        }
        scrollView.addView(list, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT))
        addScaledView(scrollView, rect)
    }

    private fun createCartRowView(line: CartLine, index: Int, rowDesignWidth: Int, rowDesignHeight: Int, compact: Boolean): FrameLayout {
        val row = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                setColor(0xFFF8F8F8.toInt())
                cornerRadius = scaledRadius(if (compact) 16f else 18f)
            }
        }
        row.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, px(rowDesignHeight)).apply {
            bottomMargin = px(if (compact) 10 else 15)
        }

        fun childParams(x: Int, y: Int, w: Int, h: Int): FrameLayout.LayoutParams {
            return FrameLayout.LayoutParams(px(w), px(h)).apply {
                leftMargin = px(x)
                topMargin = px(y)
            }
        }

        fun rowLabel(text: String, x: Int, y: Int, w: Int, h: Int, size: Float, color: Int, bold: Boolean = false, gravity: Int = Gravity.LEFT or Gravity.CENTER_VERTICAL) {
            val label = TextView(this).apply {
                this.text = text
                setTextSize(TypedValue.COMPLEX_UNIT_PX, scaledTextSize(size))
                setTextColor(color)
                this.gravity = gravity
                includeFontPadding = false
                if (bold) setTypeface(Typeface.DEFAULT, Typeface.BOLD)
                setPadding(px(4), 0, px(4), 0)
            }
            row.addView(label, childParams(x, y, w, h))
        }

        fun rowButton(text: String, x: Int, y: Int, w: Int, h: Int, bg: Int, onTap: () -> Unit) {
            val button = TextView(this).apply {
                this.text = text
                setTextSize(TypedValue.COMPLEX_UNIT_PX, scaledTextSize(if (text == "Изм.") 14f else 22f))
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                includeFontPadding = false
                if (text != "Изм.") setTypeface(Typeface.DEFAULT, Typeface.BOLD)
                isClickable = true
                setOnClickListener { onTap.invoke() }
                background = GradientDrawable().apply {
                    setColor(bg)
                    cornerRadius = scaledRadius(10f)
                }
            }
            row.addView(button, childParams(x, y, w, h))
        }

        val image = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        setProductImage(image, line.product)

        if (compact) {
            val narrow = rowDesignWidth < 650
            val imageSize = if (narrow) 64 else 76
            val imageX = if (narrow) 8 else 8
            val imageY = if (narrow) 16 else 12
            row.addView(image, childParams(imageX, imageY, imageSize, imageSize))

            val flags = mutableListOf<String>()
            if (line.ownCup) flags.add("свой стакан")
            if (line.syrupAdded) flags.add(line.syrupNameLabel())
            val subtitle = line.product.volume.replace("мл", " мл") + if (flags.isEmpty()) "" else " • " + flags.joinToString(", ")

            if (narrow) {
                rowLabel("${normalizeProductName(line.product)} ×${line.quantity}", 82, 12, 165, 30, 13f, dark, true)
                rowLabel(subtitle, 82, 46, 170, 28, 10f, blueGray, false)
                val bx = rowDesignWidth - 285
                rowButton("−", bx, 22, 58, 54, red) { decreaseLine(index) }
                rowButton("Изм.", bx + 72, 22, 80, 54, blueGray) { editLine(index) }
                rowButton("+", bx + 166, 22, 58, 54, green) { increaseLine(index) }
                rowLabel(formatMoney(line.product.price * line.quantity), rowDesignWidth - 72, 57, 66, 30, 11f, dark, true, Gravity.RIGHT or Gravity.CENTER_VERTICAL)
            } else {
                rowLabel("${normalizeProductName(line.product)} ×${line.quantity}", 92, 9, 445, 32, 15f, dark, true)
                rowLabel(subtitle, 92, 43, 445, 28, 11f, blueGray, false)
                rowLabel(formatMoney(line.product.price * line.quantity), rowDesignWidth - 168, 58, 150, 30, 13f, dark, true, Gravity.RIGHT or Gravity.CENTER_VERTICAL)
                val bx = rowDesignWidth - 350
                rowButton("−", bx, 21, 62, 55, red) { decreaseLine(index) }
                rowButton("Изм.", bx + 74, 21, 84, 55, blueGray) { editLine(index) }
                rowButton("+", bx + 170, 21, 62, 55, green) { increaseLine(index) }
            }
        } else {
            row.addView(image, childParams(10, 12, 98, 98))
            rowLabel(normalizeProductName(line.product).uppercase(), 125, 14, 420, 38, 18f, dark, true)
            val flags = mutableListOf<String>()
            if (line.ownCup) flags.add("свой стакан")
            if (line.syrupAdded) flags.add(line.syrupNameLabel())
            val subtitle = line.product.volume.replace("мл", " мл") + if (flags.isEmpty()) "" else " • " + flags.joinToString(", ")
            rowLabel(subtitle, 125, 56, 470, 32, 13f, blueGray, false)
            rowLabel(formatMoney(line.product.price * line.quantity), rowDesignWidth - 165, 44, 145, 45, 16f, dark, true, Gravity.RIGHT or Gravity.CENTER_VERTICAL)
            val bx = rowDesignWidth - 360
            rowButton("−", bx, 35, 70, 62, red) { decreaseLine(index) }
            rowLabel("×${line.quantity}", bx + 76, 36, 72, 58, 16f, dark, true, Gravity.CENTER)
            rowButton("+", bx + 150, 35, 70, 62, green) { increaseLine(index) }
        }
        return row
    }

    private fun CartLine.syrupNameLabel(): String = syrupName?.let { "сироп: $it" } ?: "сироп"

    private fun renderCouponInputOverlay() {
        val visible = couponInput.padEnd(6, '•').take(6)
        // В макете уже есть крестик и цифровая клавиатура. Рисуем только живое значение поля,
        // чтобы не появлялись второй красный крест и дубли клавиш.
        addLabel(visible, RectSpec(360, 1035, 360, 75), 30f, 0xFF333333.toInt(), Gravity.CENTER, false, Color.WHITE)
    }

    private fun renderLoyaltyInputOverlay() {
        val visible = if (loyaltyInput.isBlank()) "" else loyaltyInput
        // Клавиши и кнопка назад уже есть в исходном экране Figma; оживляем только введённое значение.
        addLabel(visible, RectSpec(130, 565, 390, 70), 24f, 0xFF333333.toInt(), Gravity.CENTER, false, Color.WHITE)
    }

    private fun renderLoyaltyProfileOverlay() {
        val balance = loyaltyGateway.balanceLabel ?: "0 бонусов"
        val coupons = loyaltyGateway.couponsCount
        val available = loyaltyGateway.availableBonusAmount
        addBox(RectSpec(80, 360, 920, 720), Color.WHITE, 28f)
        addLabel("КАРТА ЛОЯЛЬНОСТИ", RectSpec(150, 410, 780, 70), 27f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel("Баланс", RectSpec(170, 520, 250, 50), 21f, blueGray, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
        addLabel(balance, RectSpec(420, 505, 480, 70), 32f, green, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addLabel("Доступно к списанию", RectSpec(170, 610, 430, 50), 19f, blueGray, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
        addLabel(formatMoney(available.coerceAtMost(cartGrossTotal())), RectSpec(600, 598, 300, 65), 27f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        if (coupons > 0) addLabel("Купонов: $coupons", RectSpec(170, 690, 730, 44), 19f, dark, Gravity.CENTER, false, Color.TRANSPARENT)
        val hint = if (available > 0) "Нажмите «Применить бонусы», чтобы уменьшить сумму заказа." else "Карта уже привязана к заказу. Бонусов для списания сейчас нет."
        addLabel(hint, RectSpec(170, 760, 730, 100), 19f, blueGray, Gravity.CENTER, false, Color.TRANSPARENT)
        val btnColor = if (available > 0) green else blueGray
        val buttonText = if (available > 0) "Применить бонусы" else "Вернуться в заказ"
        addRoundedLabel(buttonText, RectSpec(170, 900, 730, 92), 22f, Color.WHITE, Gravity.CENTER, true, btnColor, 16f)
    }

    private fun renderLoyaltyGetCardOverlay() {
        addBox(RectSpec(80, 360, 920, 760), Color.WHITE, 28f)
        addLabel("ПОЛУЧИТЬ КАРТУ", RectSpec(150, 410, 780, 70), 27f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addBox(RectSpec(310, 525, 460, 460), 0xFFF4F6F7.toInt(), 22f)
        addLabel("QR\nрегистрации\nкарты", RectSpec(370, 620, 340, 260), 32f, blueGray, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel("Регистрация новой карты пока оставлена как безопасная заглушка. Для MVP используйте уже выданный код 0736816.", RectSpec(150, 1010, 780, 95), 19f, blueGray, Gravity.CENTER, false, Color.TRANSPARENT)
        addRoundedLabel("Вернуться к вводу кода", RectSpec(170, 1145, 730, 92), 22f, Color.WHITE, Gravity.CENTER, true, green, 16f)
    }

    private fun renderKeypadVisuals(originX: Int, originY: Int, cellW: Int, cellH: Int, gapX: Int, gapY: Int) {
        val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf("⌫", "0", "OK"))
        rows.forEachIndexed { rowIndex, row ->
            row.forEachIndexed { colIndex, key ->
                val x = originX + colIndex * (cellW + gapX)
                val y = originY + rowIndex * (cellH + gapY)
                addLabel(key, RectSpec(x, y, cellW, cellH), 22f, 0xFF333333.toInt(), Gravity.CENTER, true, 0xEEFFFFFF.toInt())
            }
        }
    }

    private fun renderLanguagePopup() {
        addLabel("", RectSpec(0, 0, 1080, 1920), 1f, Color.TRANSPARENT, Gravity.CENTER, false, 0x66000000.toInt())
        addBox(RectSpec(545, 120, 480, 520), Color.WHITE, 28f)
        addLabel("Выберите язык", RectSpec(590, 155, 345, 64), 25f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addRoundedLabel("×", RectSpec(945, 150, 58, 58), 26f, Color.WHITE, Gravity.CENTER, true, red, 12f)
        renderLanguageOption("RU", "Русский", RectSpec(590, 250, 390, 88))
        renderLanguageOption("EN", "English", RectSpec(590, 355, 390, 88))
        renderLanguageOption("KZ", "Қазақша", RectSpec(590, 460, 390, 88))
        addLabel("Локализация текстов будет подключаться через словарь. Сейчас выбор языка сохранён в интерфейсе.", RectSpec(590, 560, 390, 50), 13f, blueGray, Gravity.CENTER, false, Color.TRANSPARENT)
    }

    private fun renderLanguageOption(code: String, title: String, rect: RectSpec) {
        val selected = currentLanguage == code
        val bg = if (selected) 0xFFEAF7E8.toInt() else 0xFFF7F7F7.toInt()
        val label = if (selected) "✓  $title" else title
        addRoundedLabel(label, rect, 22f, if (selected) green else dark, Gravity.CENTER_VERTICAL or Gravity.LEFT, true, bg, 14f)
    }



    private fun renderPaymentMethodsOverlay() {
        // Способы оплаты, иконки и кнопка «Назад» уже отрисованы в макете.
        // Добавляем только сумму, аккуратно над карточками, без повторного текста поверх кнопок.
        val discountText = loyaltyPaymentSuffix()
        addLabel("Сумма к оплате: ${formatMoney(cartTotal())}$discountText", RectSpec(120, 360, 840, 70), 23f, 0xFF333333.toInt(), Gravity.CENTER, true, 0xF2FFFFFF.toInt())
    }

    private fun renderPaymentProgressOverlay() {
        val order = orderGateway.currentOrder()
        val statusText = when (currentScreen) {
            "PAYMENT_POS" -> "Ожидание ответа POS-терминала"
            "PAYMENT_CASH" -> "Ожидание внесения наличных"
            "PAYMENT_ONLINE_QR" -> "Сканируйте QR-код для оплаты"
            else -> "Проверяем оплату и готовим чек"
        }
        addLabel(statusText, RectSpec(145, 1230, 790, 70), 24f, 0xFF333333.toInt(), Gravity.CENTER, true, 0xEEFFFFFF.toInt())
        if (order != null) addLabel("Заказ ${order.externalNumber} • ${formatMoney(order.amount)}", RectSpec(145, 1310, 790, 55), 18f, 0xFF6D8297.toInt(), Gravity.CENTER, false, 0xEEFFFFFF.toInt())

        // В исходном POS-макете сумма была статичной. Закрываем нижний финансовый блок и
        // показываем реальную сумму текущего заказа, чтобы не было расхождения 57 ₽ / 589 ₽.
        val total = order?.amount ?: cartTotal()
        addBox(RectSpec(0, 1560, 1080, 250), Color.WHITE, 0f)
        addLabel("К оплате", RectSpec(30, 1595, 420, 60), 24f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addLabel(formatMoney(total), RectSpec(650, 1585, 390, 80), 40f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addLabel("Комиссия 0,00 ₽", RectSpec(650, 1688, 390, 50), 20f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
    }

    private fun renderPaymentCompletedOverlay() {
        val order = orderGateway.currentOrder()
        if (order != null) {
            // Закрываем статичный демонстрационный чек из PNG и рисуем аккуратную карточку
            // с настоящими данными текущего заказа.
            addBox(RectSpec(60, 270, 960, 760), Color.WHITE, 0f)
            addLabel("✓", RectSpec(120, 330, 120, 100), 46f, green, Gravity.CENTER, true, Color.TRANSPARENT)
            addLabel("ЗАКАЗ ${order.externalNumber}", RectSpec(245, 345, 690, 70), 26f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
            addBox(RectSpec(135, 455, 300, 390), 0xFFF4F6F7.toInt(), 8f)
            addLabel("ЧЕК\nПОДГОТОВЛЕН", RectSpec(155, 575, 260, 120), 22f, blueGray, Gravity.CENTER, true, Color.TRANSPARENT)
            addLabel("Способ оплаты", RectSpec(520, 470, 400, 45), 17f, blueGray, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
            addLabel(paymentMethodTitle(order.paymentMethod), RectSpec(520, 515, 400, 55), 22f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
            addLabel("Номер платежа", RectSpec(520, 595, 400, 45), 17f, blueGray, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
            addLabel(order.localId.padStart(6, '0'), RectSpec(520, 640, 400, 55), 22f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
            addLabel("Сумма", RectSpec(520, 720, 400, 45), 17f, blueGray, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
            addLabel(formatMoney(order.amount), RectSpec(520, 765, 400, 60), 24f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
            addLabel("Чек подготовлен", RectSpec(170, 870, 740, 60), 22f, green, Gravity.CENTER, true, Color.TRANSPARENT)
        }
        if (!recommendationsHidden) renderRecommendationPopupIfNeeded()
        if (recommendationsHidden) addButton("Показать рекомендации", RectSpec(330, 1390, 420, 80), { recommendationsHidden = false; rerenderCurrentScreen() }, 0xFF6D8297.toInt())
    }

    private fun paymentMethodTitle(method: PaymentMethod?): String = when (method) {
        PaymentMethod.CARD -> "Банковская карта"
        PaymentMethod.CASH -> "Наличные"
        PaymentMethod.ONLINE, PaymentMethod.SBER_SPASIBO -> "Онлайн-оплата"
        null -> "Банковская карта"
    }

    private fun renderRecommendationPopupIfNeeded() {
        val title = recommendationPopupTitle ?: return
        addLabel("", RectSpec(0, 0, 1080, 1920), 1f, Color.TRANSPARENT, Gravity.CENTER, false, 0x99000000.toInt())
        addLabel("Мы рекомендуем", RectSpec(135, 620, 810, 70), 25f, 0xFF333333.toInt(), Gravity.CENTER, true, 0xFFFFFFFF.toInt())
        addLabel(title, RectSpec(135, 690, 810, 120), 28f, 0xFF333333.toInt(), Gravity.CENTER, true, 0xFFFFFFFF.toInt())
        addLabel("Предложение добавлено к текущему сценарию. Покупка абонемента или отдельной услуги пойдёт через тот же заказный контур после согласования API.", RectSpec(170, 825, 740, 160), 18f, 0xFF333333.toInt(), Gravity.CENTER, false, 0xFFFFFFFF.toInt())
        addButton("Закрыть", RectSpec(235, 1010, 610, 95), { recommendationPopupTitle = null; rerenderCurrentScreen() }, 0xFF59BC48.toInt())
        addButton("×", RectSpec(855, 605, 70, 70), { recommendationPopupTitle = null; rerenderCurrentScreen() }, 0xFFE95B5B.toInt())
    }


    private fun renderLandscapeScreen(screenId: String) {
        screenImage.setImageDrawable(ColorDrawable(Color.WHITE))
        when {
            screenId in setOf("CATALOG_DEFAULT", "CATALOG_DEFAULT_VARIANT_1", "CATALOG_DEFAULT_VARIANT_2", "CATALOG_DEFAULT_VARIANT_3", "CATALOG_DEFAULT_VARIANT_4",
                "CATALOG_WITH_COUPON_AND_FOOD", "CATALOG_WITH_COUPON_AND_FOOD_2", "CATALOG_NEW_ORDER",
                "ORDER_DEFAULT", "ORDER_VARIANT_1", "ORDER_VARIANT_2", "ORDER_VARIANT_3", "ORDER_VARIANT_4", "YOUR_ORDER", "YOUR_ORDER_2",
                "TRUST_PLUS_MULTI_ORDER", "TRUST_PLUS_MULTI_ORDER_2") -> renderLandscapeCatalogAndOrder()
            screenId == "ITEM_ADD" || screenId == "ITEM_EDIT" -> renderLandscapeItemEditor(screenId == "ITEM_EDIT")
            screenId == "COUPON_ADD" -> renderLandscapeCoupon()
            screenId == "FOOD_SCAN" -> renderLandscapeFoodScan()
            screenId == "LOYALTY_LOGIN" -> renderLandscapeLoyalty()
            screenId == "LOYALTY_PROFILE" || screenId == "LOYALTY_PROFILE_FULL" || screenId == "LOYALTY_SUBSCRIPTION" -> renderLandscapeLoyaltyProfile()
            screenId == "LOYALTY_GET_CARD_QR" || screenId == "LOYALTY_COFFEE_SUBSCRIPTION_QR" -> renderLandscapeLoyaltyGetCard()
            screenId == "PAYMENT_METHOD_ALL" || screenId == "PAYMENT_METHOD_NO_CASH" -> renderLandscapePaymentMethods()
            screenId == "PAYMENT_POS" || screenId == "PAYMENT_CASH" || screenId == "PAYMENT_ONLINE_QR" || screenId == "PAYMENT_ONLINE_CONFIRM" -> renderLandscapePaymentProgress()
            screenId == "PAYMENT_COMPLETED" -> renderLandscapePaymentCompleted()
            else -> renderLandscapeCatalogAndOrder()
        }
    }

    private fun renderLandscapeHeader() {
        addBox(RectSpec(0, 0, 1920, 74), Color.WHITE, 0f)
        addLabel("i-Coffee.me", RectSpec(760, 18, 400, 42), 22f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addRoundedLabel(currentLanguage, RectSpec(1740, 18, 96, 42), 18f, dark, Gravity.CENTER, true, 0xFFF8F8F8.toInt(), 8f)
        addLabel("Техническая поддержка: +7 (495) 000-00-00", RectSpec(25, 1034, 520, 35), 13f, 0xFF777777.toInt(), Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
        addLabel("Информация для потребителей", RectSpec(760, 1034, 400, 35), 13f, green, Gravity.CENTER, false, Color.TRANSPARENT)
        addLabel("ПО разработано  i-Retail.com", RectSpec(1465, 1034, 420, 35), 13f, 0xFF777777.toInt(), Gravity.RIGHT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
    }

    private fun renderLandscapeActionButtons(hasCart: Boolean) {
        val y = 90
        if (hasCart) {
            addRoundedLabel("🎟  ДОБАВИТЬ КУПОН", RectSpec(40, y, 360, 82), 19f, dark, Gravity.CENTER, true, Color.WHITE, 8f)
            addRoundedLabel("♨  РАЗОГРЕТЬ ЕДУ", RectSpec(420, y, 360, 82), 19f, dark, Gravity.CENTER, true, Color.WHITE, 8f)
        } else {
            addRoundedLabel("🎟  ДОБАВИТЬ КУПОН", RectSpec(40, y, 360, 82), 19f, dark, Gravity.CENTER, true, Color.WHITE, 8f)
            addRoundedLabel("▱  ДОБАВИТЬ ЕДУ", RectSpec(420, y, 360, 82), 19f, dark, Gravity.CENTER, true, Color.WHITE, 8f)
            addRoundedLabel("♨  РАЗОГРЕТЬ ЕДУ", RectSpec(800, y, 360, 82), 19f, dark, Gravity.CENTER, true, Color.WHITE, 8f)
        }
    }

    private fun landscapeProductRects(hasCart: Boolean): List<RectSpec> {
        val cardW = if (hasCart) 270 else 420
        val cardH = if (hasCart) 300 else 315
        val startX = 40
        val gap = if (hasCart) 22 else 35
        val y1 = 195
        val y2 = if (hasCart) 515 else 535
        return (0 until 8).map { index ->
            val col = index % 4
            val row = index / 4
            RectSpec(startX + col * (cardW + gap), if (row == 0) y1 else y2, cardW, cardH)
        }
    }

    private fun renderLandscapeCatalogAndOrder() {
        val hasCart = cart.isNotEmpty()
        renderLandscapeHeader()
        renderLandscapeActionButtons(hasCart)
        renderLandscapeProductGrid(hasCart)
        if (hasCart) {
            renderLandscapeCartPanel()
        } else {
            addRoundedLabel("ЧТО ВЫБЕРЕТЕ СЕГОДНЯ?", RectSpec(0, 900, 1920, 70), 30f, 0xFFC7CED6.toInt(), Gravity.CENTER, true, Color.TRANSPARENT, 0f)
        }
    }

    private fun renderLandscapeProductGrid(hasCart: Boolean) {
        val products = visualCoffeeProducts()
        val rect = if (hasCart) RectSpec(40, 195, 1148, 690) else RectSpec(40, 195, 1800, 660)
        renderProductScrollGrid(
            products = products,
            rect = rect,
            columns = 4,
            cardW = if (hasCart) 270 else 420,
            cardH = if (hasCart) 300 else 315,
            gapX = if (hasCart) 22 else 35,
            gapY = 20,
            imageH = if (hasCart) 145 else 155,
            titleTextSize = if (hasCart) 17f else 18f,
            priceTextSize = 18f
        )
        if (products.size > 8) addCatalogScrollHint(rect, products.size)
        val statusText = catalogVisibleStatusText()
        if (statusText.isNotBlank()) {
            val y = if (hasCart) 895 else 868
            val w = if (hasCart) 1148 else 1800
            addRoundedLabel(statusText, RectSpec(40, y, w, 40), 15f, blueGray, Gravity.CENTER, false, 0xFFF8F8F8.toInt(), 12f)
        }
    }

    private fun renderLandscapeProductCard(product: Product, rect: RectSpec) {
        addBox(rect, 0xFFFAFAFA.toInt(), 8f)
        addProductImage(product, RectSpec(rect.x + rect.width / 2 - 90, rect.y + 18, 180, 155))
        addLabel(shortProductName(product).uppercase(), RectSpec(rect.x + 14, rect.y + 180, rect.width - 28, 48), 18f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel(product.volume.replace("мл", " мл"), RectSpec(rect.x + 20, rect.y + 227, rect.width - 40, 34), 15f, blueGray, Gravity.CENTER, false, Color.TRANSPARENT)
        addLabel(formatMoney(product.price), RectSpec(rect.x + 20, rect.y + 260, rect.width - 40, 42), 18f, green, Gravity.CENTER, true, Color.TRANSPARENT)
    }

    private fun renderLandscapeCartPanel() {
        val itemCount = cart.sumOf { it.quantity }
        val total = cartTotal()
        addBox(RectSpec(1230, 90, 650, 920), Color.WHITE, 28f)
        addLabel("ВАШ ЗАКАЗ", RectSpec(1280, 120, 550, 55), 26f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        val listRect = RectSpec(1270, 190, 565, 520)
        addCartScrollList(listRect, rowDesignHeight = 112, compact = true)
        if (cart.size > 4) addScrollHint(listRect)
        addLabel("Сумма", RectSpec(1270, 735, 200, 55), 22f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        loyaltyOrderNote(full = false)?.let { note -> addLabel(note, RectSpec(1335, 700, 495, 42), 15f, blueGray, Gravity.RIGHT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT) }
        addLabel(formatMoney(total), RectSpec(1520, 740, 310, 70), 34f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addTrashButton(RectSpec(1270, 835, 104, 92)) { clearOrder() }
        addRoundedLabel("Оплатить\n$itemCount товар(ов) • ${formatMoney(total)}", RectSpec(1400, 835, 430, 92), 18f, Color.WHITE, Gravity.CENTER, true, green, 14f)
        addRoundedLabel("Оплатить со скидкой", RectSpec(1270, 945, 560, 54), 17f, Color.WHITE, Gravity.CENTER, true, 0xFF7E8FA2.toInt(), 12f)
    }

    private fun renderLandscapeItemEditor(editMode: Boolean) {
        renderLandscapeHeader()
        val product = pendingProduct ?: visualCoffeeProducts().firstOrNull() ?: catalog.firstOrNull() ?: return
        addLabel(if (editMode) "РЕДАКТИРОВАНИЕ ТОВАРА" else "ДОБАВЛЕНИЕ ТОВАРА", RectSpec(70, 98, 760, 62), 29f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addRoundedLabel("×", RectSpec(1760, 96, 74, 74), 34f, Color.WHITE, Gravity.CENTER, true, red, 12f)
        addBox(RectSpec(80, 190, 720, 760), Color.WHITE, 28f)
        addProductImage(product, RectSpec(250, 235, 380, 315))
        addLabel(normalizeProductName(product).uppercase(), RectSpec(125, 560, 630, 70), 33f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel(product.volume.replace("мл", " мл"), RectSpec(230, 635, 420, 45), 20f, blueGray, Gravity.CENTER, false, Color.TRANSPARENT)
        addLabel(formatMoney(product.price), RectSpec(230, 690, 420, 55), 26f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel("У меня свой стакан", RectSpec(195, 765, 340, 58), 22f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
        addRoundedLabel(if (pendingOwnCup) "✓" else "", RectSpec(550, 768, 92, 52), 24f, Color.WHITE, Gravity.CENTER, true, if (pendingOwnCup) green else 0xFFE4E4E4.toInt(), 26f)

        addBox(RectSpec(860, 190, 770, 620), panelSoft, 28f)
        val selected = pendingSyrupName
        addLabel(if (selected == null) "ДОБАВИТЬ СИРОП" else "СИРОП ДОБАВЛЕН", RectSpec(950, 230, 590, 58), 25f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        val syrupRows = listOf("Ваниль", "Карамель", "Кокос", "Сахар")
        syrupRows.forEachIndexed { index, name ->
            val y = 325 + index * 92
            val isSelected = selected == name
            addLabel(name, RectSpec(990, y, 300, 64), 24f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
            addRoundedLabel(if (isSelected) "✓" else "+", RectSpec(1310, y + 6, 62, 52), 26f, if (isSelected) Color.WHITE else green, Gravity.CENTER, true, if (isSelected) green else Color.WHITE, 12f)
            if (isSelected) addRoundedLabel("Удалить", RectSpec(1395, y + 6, 150, 52), 20f, Color.WHITE, Gravity.CENTER, true, red, 10f)
        }
        if (editMode) addRoundedLabel("Редактирование позиции", RectSpec(970, 728, 500, 42), 18f, blueGray, Gravity.CENTER, true, Color.TRANSPARENT)
        addRoundedLabel(if (editMode) "Сохранить изменения" else "Добавить товар в корзину", RectSpec(860, 850, 770, 92), 24f, Color.WHITE, Gravity.CENTER, true, green, 14f)
    }

    private fun renderLandscapeCoupon() {
        renderLandscapeHeader()
        addBox(RectSpec(455, 110, 1010, 850), Color.WHITE, 28f)
        addLabel("ДОБАВЛЕНИЕ КУПОНА", RectSpec(520, 145, 650, 60), 30f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addRoundedLabel("×", RectSpec(1340, 135, 70, 70), 32f, Color.WHITE, Gravity.CENTER, true, red, 10f)
        addLabel("Отсканируйте QR-код купона\nили введите шестизначный номер вручную.", RectSpec(570, 245, 780, 90), 20f, dark, Gravity.CENTER, false, Color.TRANSPARENT)
        addLabel(couponInput.padEnd(6, '•').take(6), RectSpec(720, 360, 480, 90), 34f, dark, Gravity.CENTER, true, Color.WHITE)
        renderKeypadVisuals(735, 485, 135, 82, 18, 12)
    }

    private fun renderLandscapeFoodScan() {
        renderLandscapeHeader()
        addBox(RectSpec(420, 135, 1080, 760), Color.WHITE, 28f)
        addLabel("ДОБАВЛЕНИЕ ЕДЫ", RectSpec(500, 175, 650, 70), 30f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addRoundedLabel("×", RectSpec(1380, 170, 74, 74), 34f, Color.WHITE, Gravity.CENTER, true, red, 12f)
        addLabel("Отсканируйте штрихкод товара\nили добавьте тестовые позиции микромаркета.", RectSpec(560, 300, 800, 120), 27f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addRoundedLabel("Добавить еду в заказ", RectSpec(640, 560, 640, 95), 24f, Color.WHITE, Gravity.CENTER, true, green, 14f)
        addRoundedLabel("← Назад", RectSpec(640, 690, 640, 90), 22f, dark, Gravity.CENTER, true, Color.WHITE, 14f)
    }

    private fun renderLandscapeLoyalty() {
        renderLandscapeHeader()
        addLabel("Система лояльности", RectSpec(650, 95, 620, 60), 30f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addRoundedLabel("←", RectSpec(22, 14, 64, 64), 32f, Color.WHITE, Gravity.CENTER, true, green, 0f)
        addLabel("ВВЕДИТЕ ЦИФРОВОЙ КОД\nИЛИ СКАНИРУЙТЕ QR", RectSpec(185, 230, 620, 130), 35f, green, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addLabel(loyaltyInput, RectSpec(205, 390, 450, 70), 26f, dark, Gravity.CENTER, false, Color.WHITE)
        renderKeypadVisuals(205, 490, 130, 78, 18, 12)
        addBox(RectSpec(1080, 260, 520, 520), 0xFFF4F6F7.toInt(), 26f)
        addLabel("QR\nкарты\nлояльности", RectSpec(1180, 390, 320, 220), 30f, blueGray, Gravity.CENTER, true, Color.TRANSPARENT)
        addRoundedLabel("Получить карту", RectSpec(1080, 820, 520, 86), 23f, Color.WHITE, Gravity.CENTER, true, green, 14f)
    }

    private fun renderLandscapeLoyaltyProfile() {
        renderLandscapeHeader()
        val balance = loyaltyGateway.balanceLabel ?: "0 бонусов"
        val available = loyaltyGateway.availableBonusAmount.coerceAtMost(cartGrossTotal())
        addLabel("Карта лояльности", RectSpec(650, 95, 620, 60), 30f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addRoundedLabel("←", RectSpec(22, 14, 64, 64), 32f, Color.WHITE, Gravity.CENTER, true, green, 0f)
        addBox(RectSpec(520, 220, 880, 520), Color.WHITE, 28f)
        addLabel("КЛИЕНТ НАЙДЕН", RectSpec(600, 255, 720, 60), 28f, green, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel("Баланс", RectSpec(620, 360, 260, 50), 24f, blueGray, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
        addLabel(balance, RectSpec(890, 345, 360, 70), 36f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addLabel("Доступно к списанию", RectSpec(620, 455, 420, 50), 22f, blueGray, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
        addLabel(formatMoney(available), RectSpec(1060, 442, 190, 68), 30f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        val couponsText = if (loyaltyGateway.couponsCount > 0) "Купонов: ${loyaltyGateway.couponsCount}" else "Активных купонов нет"
        addLabel(couponsText, RectSpec(620, 545, 630, 44), 21f, blueGray, Gravity.CENTER, false, Color.TRANSPARENT)
        val hint = if (available > 0) "Бонусы будут переданы в заказ как ibonus_discount_sum." else "Карта уже привязана к заказу. Бонусов для списания сейчас нет."
        addLabel(hint, RectSpec(610, 615, 700, 60), 18f, blueGray, Gravity.CENTER, false, Color.TRANSPARENT)
        val btnColor = if (available > 0) green else blueGray
        val buttonText = if (available > 0) "Применить бонусы" else "Вернуться в заказ"
        addRoundedLabel(buttonText, RectSpec(700, 770, 520, 92), 25f, Color.WHITE, Gravity.CENTER, true, btnColor, 14f)
    }

    private fun renderLandscapeLoyaltyGetCard() {
        renderLandscapeHeader()
        addLabel("Получить карту лояльности", RectSpec(650, 95, 620, 60), 30f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addRoundedLabel("←", RectSpec(22, 14, 64, 64), 32f, Color.WHITE, Gravity.CENTER, true, green, 0f)
        addBox(RectSpec(610, 220, 700, 610), Color.WHITE, 28f)
        addBox(RectSpec(760, 285, 400, 400), 0xFFF4F6F7.toInt(), 22f)
        addLabel("QR\nрегистрации\nкарты", RectSpec(820, 360, 280, 260), 30f, blueGray, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel("Регистрация новой карты пока оставлена как безопасная заглушка. Для проверки используйте код клиента 0736816.", RectSpec(690, 705, 540, 70), 19f, blueGray, Gravity.CENTER, false, Color.TRANSPARENT)
        addRoundedLabel("Вернуться к вводу кода", RectSpec(750, 850, 420, 78), 22f, Color.WHITE, Gravity.CENTER, true, green, 14f)
    }

    private fun renderLandscapePaymentMethods() {
        renderLandscapeHeader()
        addLabel("Выберите способ оплаты", RectSpec(540, 115, 840, 70), 32f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        val discountText = loyaltyPaymentSuffix()
        addLabel("Сумма к оплате: ${formatMoney(cartTotal())}$discountText", RectSpec(560, 220, 800, 55), 23f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        val cards = listOf("💳  Банковская карта", "◎  Наличные", "✓  СберСпасибо")
        cards.forEachIndexed { index, title ->
            addRoundedLabel(title, RectSpec(260 + index * 475, 390, 430, 150), 27f, dark, Gravity.CENTER, true, Color.WHITE, 20f)
        }
        addRoundedLabel("← Назад к заказу", RectSpec(700, 700, 520, 105), 26f, dark, Gravity.CENTER, true, Color.WHITE, 18f)
    }

    private fun renderLandscapePaymentProgress() {
        renderLandscapeHeader()
        val order = orderGateway.currentOrder()
        val title = when (currentScreen) {
            "PAYMENT_POS" -> "ПРИЛОЖИТЕ КАРТУ К ТЕРМИНАЛУ ОПЛАТЫ"
            "PAYMENT_CASH" -> "ВНЕСИТЕ НАЛИЧНЫЕ В КУПЮРОПРИЁМНИК"
            "PAYMENT_ONLINE_QR" -> "СКАНИРУЙТЕ QR-КОД ДЛЯ ОПЛАТЫ"
            else -> "ПРОВЕРЯЕМ ОПЛАТУ И ГОТОВИМ ЧЕК"
        }
        addLabel("Оплата заказа", RectSpec(650, 95, 620, 60), 30f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel(title, RectSpec(230, 220, 1460, 130), 42f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addBox(RectSpec(685, 380, 550, 330), 0xFFF4F6F7.toInt(), 26f)
        addLabel(if (currentScreen == "PAYMENT_ONLINE_QR") "QR" else "POS", RectSpec(785, 445, 350, 160), 56f, blueGray, Gravity.CENTER, true, Color.TRANSPARENT)
        val total = order?.amount ?: cartTotal()
        addLabel("Заказ ${order?.externalNumber ?: ""} • ${formatMoney(total)}", RectSpec(450, 735, 1020, 55), 22f, blueGray, Gravity.CENTER, false, Color.TRANSPARENT)
        addLabel("К оплате", RectSpec(70, 890, 400, 60), 25f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addLabel(formatMoney(total), RectSpec(1400, 880, 420, 75), 40f, dark, Gravity.RIGHT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
    }

    private fun renderLandscapePaymentCompleted() {
        renderLandscapeHeader()
        val order = orderGateway.currentOrder()
        addLabel("Завершение оплаты", RectSpec(650, 95, 620, 60), 30f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addBox(RectSpec(120, 190, 1060, 550), Color.WHITE, 20f)
        addLabel("✓", RectSpec(180, 245, 120, 95), 46f, green, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel("ЗАКАЗ ${order?.externalNumber ?: ""}", RectSpec(325, 260, 760, 70), 27f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addBox(RectSpec(240, 360, 260, 260), 0xFFF4F6F7.toInt(), 8f)
        addLabel("ЧЕК\nПОДГОТОВЛЕН", RectSpec(260, 430, 220, 110), 21f, blueGray, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel("Способ оплаты", RectSpec(610, 365, 360, 45), 17f, blueGray, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
        addLabel(paymentMethodTitle(order?.paymentMethod), RectSpec(610, 410, 380, 55), 22f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addLabel("Сумма", RectSpec(610, 500, 360, 45), 17f, blueGray, Gravity.LEFT or Gravity.CENTER_VERTICAL, false, Color.TRANSPARENT)
        addLabel(formatMoney(order?.amount ?: cartTotal()), RectSpec(610, 545, 380, 55), 24f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addLabel("МЫ РЕКОМЕНДУЕМ", RectSpec(1230, 190, 560, 55), 28f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addRoundedLabel("С картой дешевле\nПодробнее →", RectSpec(1230, 270, 560, 110), 20f, Color.WHITE, Gravity.CENTER, true, 0xFF2E6A2E.toInt(), 14f)
        addRoundedLabel("Абонемент на кофе\nПодробнее →", RectSpec(1230, 405, 560, 110), 20f, Color.WHITE, Gravity.CENTER, true, 0xFF555555.toInt(), 14f)
        addRoundedLabel("Горячие туры\nПодробнее →", RectSpec(1230, 540, 560, 110), 20f, Color.WHITE, Gravity.CENTER, true, 0xFF6D8297.toInt(), 14f)
        addRoundedLabel("Новый заказ", RectSpec(1230, 820, 560, 95), 28f, Color.WHITE, Gravity.CENTER, true, green, 14f)
        if (!recommendationsHidden) renderLandscapeRecommendationPopup()
    }

    private fun renderLandscapeRecommendationPopup() {
        val title = recommendationPopupTitle ?: return
        addLabel("", RectSpec(0, 0, 1920, 1080), 1f, Color.TRANSPARENT, Gravity.CENTER, false, 0x99000000.toInt())
        addBox(RectSpec(555, 285, 810, 420), Color.WHITE, 0f)
        addRoundedLabel("×", RectSpec(1280, 270, 78, 78), 32f, Color.WHITE, Gravity.CENTER, true, red, 10f)
        addLabel("Мы рекомендуем", RectSpec(610, 320, 700, 60), 28f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel(title, RectSpec(610, 390, 700, 75), 32f, dark, Gravity.CENTER, true, Color.TRANSPARENT)
        addLabel("Предложение добавлено к текущему сценарию.", RectSpec(640, 490, 640, 80), 22f, dark, Gravity.CENTER, false, Color.TRANSPARENT)
        addRoundedLabel("Закрыть", RectSpec(720, 600, 480, 80), 25f, Color.WHITE, Gravity.CENTER, true, green, 14f)
    }

    private fun renderLandscapeLanguagePopup() {
        addLabel("", RectSpec(0, 0, 1920, 1080), 1f, Color.TRANSPARENT, Gravity.CENTER, false, 0x66000000.toInt())
        addBox(RectSpec(1330, 80, 520, 445), Color.WHITE, 28f)
        addLabel("Выберите язык", RectSpec(1370, 115, 360, 58), 26f, dark, Gravity.LEFT or Gravity.CENTER_VERTICAL, true, Color.TRANSPARENT)
        addRoundedLabel("×", RectSpec(1775, 110, 58, 58), 26f, Color.WHITE, Gravity.CENTER, true, red, 12f)
        renderLanguageOption("RU", "Русский", RectSpec(1370, 200, 420, 72))
        renderLanguageOption("EN", "English", RectSpec(1370, 292, 420, 72))
        renderLanguageOption("KZ", "Қазақша", RectSpec(1370, 384, 420, 72))
    }

    private fun globalLandscapeHotspots(screenId: String): List<Hotspot> {
        val modalScreens = setOf("ITEM_ADD", "ITEM_EDIT", "COUPON_ADD", "FOOD_SCAN")
        return if (screenId !in modalScreens) listOf(area("Выбор языка", 1700, 0, 220, 90) { languagePopupVisible = true; rerenderCurrentScreen() }) else emptyList()
    }

    private fun landscapeLanguagePopupHotspots(): List<Hotspot> = listOf(
        area("Закрыть выбор языка", 0, 0, 1920, 1080) { languagePopupVisible = false; rerenderCurrentScreen() },
        area("Закрыть выбор языка", 1775, 110, 80, 80) { languagePopupVisible = false; rerenderCurrentScreen() },
        area("Русский язык", 1370, 200, 420, 72) { setInterfaceLanguage("RU") },
        area("English language", 1370, 292, 420, 72) { setInterfaceLanguage("EN") },
        area("Kazakh language", 1370, 384, 420, 72) { setInterfaceLanguage("KZ") }
    )

    private fun landscapeHotspotsFor(screenId: String): List<Hotspot> = when {
        screenId in setOf("CATALOG_DEFAULT", "CATALOG_DEFAULT_VARIANT_1", "CATALOG_DEFAULT_VARIANT_2", "CATALOG_DEFAULT_VARIANT_3", "CATALOG_DEFAULT_VARIANT_4",
            "CATALOG_WITH_COUPON_AND_FOOD", "CATALOG_WITH_COUPON_AND_FOOD_2", "CATALOG_NEW_ORDER",
            "ORDER_DEFAULT", "ORDER_VARIANT_1", "ORDER_VARIANT_2", "ORDER_VARIANT_3", "ORDER_VARIANT_4", "YOUR_ORDER", "YOUR_ORDER_2",
            "TRUST_PLUS_MULTI_ORDER", "TRUST_PLUS_MULTI_ORDER_2") -> landscapeCatalogHotspots()
        screenId == "ITEM_ADD" -> landscapeItemHotspots(editMode = false)
        screenId == "ITEM_EDIT" -> landscapeItemHotspots(editMode = true)
        screenId == "COUPON_ADD" -> landscapeCouponHotspots()
        screenId == "FOOD_SCAN" -> listOf(
            area("Закрыть добавление еды", 1380, 170, 90, 90) { openCatalogByCart() },
            area("Добавить еду", 640, 560, 640, 100) { addFoodToCart() },
            area("Назад", 640, 690, 640, 95) { openCatalogByCart() }
        )
        screenId == "LOYALTY_LOGIN" -> landscapeLoyaltyHotspots()
        screenId == "LOYALTY_PROFILE" || screenId == "LOYALTY_PROFILE_FULL" || screenId == "LOYALTY_SUBSCRIPTION" -> listOf(
            area("Назад из лояльности", 0, 0, 110, 90) { openOrderOrCatalog() },
            area("Применить бонусы", 700, 770, 520, 92) { applyLoyaltyBonusAndReturn() }
        )
        screenId == "LOYALTY_GET_CARD_QR" || screenId == "LOYALTY_COFFEE_SUBSCRIPTION_QR" -> listOf(
            area("Назад к вводу лояльности", 0, 0, 110, 90) { openScreen("LOYALTY_LOGIN") },
            area("Вернуться к вводу кода", 750, 850, 420, 78) { openScreen("LOYALTY_LOGIN") }
        )
        screenId == "PAYMENT_METHOD_ALL" || screenId == "PAYMENT_METHOD_NO_CASH" -> listOf(
            area("Оплата картой", 260, 390, 430, 150) { startPayment(PaymentMethod.CARD) },
            area("Оплата наличными", 735, 390, 430, 150) { startPayment(PaymentMethod.CASH) },
            area("Онлайн / СберСпасибо", 1210, 390, 430, 150) { startPayment(PaymentMethod.ONLINE) },
            area("Назад к заказу", 700, 700, 520, 105) { openOrderOrCatalog() }
        )
        screenId == "PAYMENT_POS" || screenId == "PAYMENT_CASH" || screenId == "PAYMENT_ONLINE_QR" || screenId == "PAYMENT_ONLINE_CONFIRM" -> listOf(
            area("Подтвердить оплату", 0, 80, 1920, 860) { finishPayment() },
            area("Отмена оплаты", 0, 940, 420, 140) { openScreen("PAYMENT_METHOD_ALL") }
        )
        screenId == "PAYMENT_COMPLETED" -> landscapePaymentCompletedHotspots()
        else -> landscapeCatalogHotspots()
    }

    private fun landscapeCatalogHotspots(): List<Hotspot> {
        val hasCart = cart.isNotEmpty()
        val items = mutableListOf<Hotspot>()
        if (hasCart) {
            items.add(area("Добавить купон", 40, 90, 360, 82) { openScreen("COUPON_ADD") })
            items.add(area("Разогреть еду", 420, 90, 360, 82) { openScreen("HEAT_FOOD_1") })
        } else {
            items.add(area("Добавить купон", 40, 90, 360, 82) { openScreen("COUPON_ADD") })
            items.add(area("Добавить еду", 420, 90, 360, 82) { openScreen("FOOD_SCAN") })
            items.add(area("Разогреть еду", 800, 90, 360, 82) { openScreen("HEAT_FOOD_1") })
        }
        if (hasCart) {
            items.add(area("Очистить заказ", 1270, 835, 104, 92) { clearOrder() })
            items.add(area("Оплатить заказ", 1400, 835, 430, 92) { goToPaymentMethod() })
            items.add(area("Оплатить со скидкой", 1270, 945, 560, 54) { openScreen("LOYALTY_LOGIN") })
        }
        return items
    }

    private fun landscapeItemHotspots(editMode: Boolean): List<Hotspot> = listOf(
        area("Закрыть добавление товара", 1760, 96, 90, 90) { if (editMode) openOrderOrCatalog() else openCatalogByCart() },
        area("Переключить свой стакан", 185, 748, 470, 90) { pendingOwnCup = !pendingOwnCup; rerenderCurrentScreen() },
        area("Добавить сироп ваниль", 980, 315, 600, 80) { addSyrup("Ваниль") },
        area("Добавить сироп карамель", 980, 407, 600, 80) { addSyrup("Карамель") },
        area("Добавить сироп кокос", 980, 499, 600, 80) { addSyrup("Кокос") },
        area("Добавить сахар", 980, 591, 600, 80) { addSyrup("Сахар") },
        area("Удалить сироп", 1380, 315, 220, 360) { if (pendingSyrup) { pendingSyrup = false; pendingSyrupName = null; rerenderCurrentScreen() } },
        area("Добавить товар в корзину", 860, 850, 770, 100) { if (editMode) { applyEditToFirstCartLine(); openOrderOrCatalog(); toast("Изменения сохранены") } else addPendingProductToCart() }
    )

    private fun landscapeCouponHotspots(): List<Hotspot> = keypadHotspots(
        originX = 735,
        originY = 485,
        cellW = 135,
        cellH = 82,
        gapX = 18,
        gapY = 12,
        onDigit = { appendCouponDigit(it) },
        onBackspace = { if (couponInput.isNotEmpty()) { couponInput = couponInput.dropLast(1); rerenderCurrentScreen() } },
        onEnter = { applyCoupon() }
    ) + listOf(
        area("Закрыть купон", 1340, 135, 90, 90) { openCatalogByCart() },
        area("Клик вне купона", 0, 0, 430, 1080) { openCatalogByCart() },
        area("Клик вне купона справа", 1490, 0, 430, 1080) { openCatalogByCart() }
    )

    private fun landscapeLoyaltyHotspots(): List<Hotspot> = keypadHotspots(
        originX = 205,
        originY = 490,
        cellW = 130,
        cellH = 78,
        gapX = 18,
        gapY = 12,
        onDigit = { appendLoyaltyDigit(it) },
        onBackspace = { if (loyaltyInput.isNotEmpty()) { loyaltyInput = loyaltyInput.dropLast(1); rerenderCurrentScreen() } },
        onEnter = { submitLoyaltyInput() }
    ) + listOf(
        area("Назад из лояльности", 0, 0, 110, 90) { openCatalogByCart() },
        area("Получить карту", 1080, 820, 520, 86) { openScreen("LOYALTY_GET_CARD_QR") }
    )

    private fun landscapePaymentCompletedHotspots(): List<Hotspot> {
        if (recommendationPopupTitle != null) {
            return listOf(
                area("Закрыть рекомендацию", 1280, 270, 95, 95) { recommendationPopupTitle = null; rerenderCurrentScreen() },
                area("Закрыть рекомендацию кнопкой", 720, 600, 480, 80) { recommendationPopupTitle = null; rerenderCurrentScreen() }
            )
        }
        return mutableListOf(
            area("Новый заказ", 1230, 820, 560, 95) { resetToIdle() },
            area("Перейти к выдаче", 120, 190, 1060, 550) { openScreen("CUP_REQUIRED") },
            area("Рекомендация 1", 1230, 270, 560, 110) { showRecommendation("С картой дешевле") },
            area("Рекомендация 2", 1230, 405, 560, 110) { showRecommendation("Абонемент на кофе") },
            area("Рекомендация 3", 1230, 540, 560, 110) { showRecommendation("Горячие туры") }
        )
    }

    private fun globalHotspots(screenId: String): List<Hotspot> {
        val modalScreens = setOf("ITEM_ADD", "ITEM_EDIT", "COUPON_ADD", "FOOD_SCAN", "RECEIPT_EMAIL_INPUT", "RECEIPT_EMAIL_COMPLETE")
        val screensWithTopFlag = !screenId.startsWith("SCREEN_SAVER") && screenId !in modalScreens
        return if (screensWithTopFlag) listOf(area("Выбор языка", 920, 40, 150, 120) { languagePopupVisible = true; rerenderCurrentScreen() }) else emptyList()
    }

    private fun languagePopupHotspots(): List<Hotspot> = listOf(
        area("Закрыть выбор языка", 0, 0, 1080, 1920) { languagePopupVisible = false; rerenderCurrentScreen() },
        area("Закрыть выбор языка", 945, 150, 70, 70) { languagePopupVisible = false; rerenderCurrentScreen() },
        area("Русский язык", 590, 250, 390, 88) { setInterfaceLanguage("RU") },
        area("English language", 590, 355, 390, 88) { setInterfaceLanguage("EN") },
        area("Kazakh language", 590, 460, 390, 88) { setInterfaceLanguage("KZ") }
    )

    private fun hotspotsFor(screenId: String): List<Hotspot> = when (screenId) {
        "SCREEN_SAVER_COFFEE", "SCREEN_SAVER_LOYALTY", "SCREEN_PROMO_DOUBLE_CASHBACK" -> listOf(
            area("Начать выбор кофе", 150, 1580, 780, 220) { startNewOrder() },
            area("Любое касание заставки", 0, 0, 1080, 1920) { startNewOrder() }
        )

        "CATALOG_DEFAULT", "CATALOG_DEFAULT_VARIANT_1", "CATALOG_DEFAULT_VARIANT_2", "CATALOG_DEFAULT_VARIANT_3", "CATALOG_DEFAULT_VARIANT_4" -> catalogHotspots(hasOrder = false)
        "CATALOG_WITH_COUPON_AND_FOOD", "CATALOG_WITH_COUPON_AND_FOOD_2", "CATALOG_NEW_ORDER" -> catalogHotspots(hasOrder = true)

        "ITEM_ADD" -> itemAddHotspots()
        "ITEM_EDIT" -> itemEditHotspots()
        "COUPON_ADD" -> couponHotspots()

        "SEARCH_EMPTY_INPUT" -> listOf(
            area("Закрыть поиск", 890, 0, 120, 120) { openCatalogByCart() },
            area("Поиск: coco", 70, 0, 520, 110) { openScreen("SEARCH_COCO") },
            area("Клавиатура / подтвердить ввод", 0, 1460, 1080, 340) { openScreen("SEARCH_RESULT") },
            area("Раскрыть заказ", 0, 1360, 1080, 100) { if (cart.isEmpty()) toast("Корзина пуста") else openScreen("ORDER_DEFAULT") }
        )

        "SEARCH_COCO", "SEARCH_AMER", "SEARCH_RESULT" -> listOf(
            area("Закрыть поиск", 890, 0, 120, 120) { openCatalogByCart() },
            area("Выбрать найденный товар", 20, 260, 1040, 980) { selectProduct(2); openScreen("ITEM_ADD") },
            area("Оплатить найденный товар", 190, 1600, 840, 150) { selectProduct(2); addPendingProductToCart(openPayment = true) }
        )

        "SEARCH_NOTHING" -> listOf(
            area("Закрыть поиск", 890, 0, 120, 120) { openCatalogByCart() },
            area("Повторить поиск", 80, 1380, 920, 160) { openScreen("SEARCH_EMPTY_INPUT") }
        )

        "FOOD_SCAN" -> listOf(
            area("Закрыть добавление еды", 780, 430, 180, 180) { openCatalogByCart() },
            area("Хорошо / добавить товар еды", 350, 1220, 380, 150) { addFoodToCart() },
            area("Назад из добавления еды", 290, 1560, 500, 180) { openCatalogByCart() },
            area("Назад верхний", 0, 0, 180, 160) { openCatalogByCart() }
        )

        "MICROMARKET_STEP_1", "TRUST_SINGLE_1", "TRUST_MULTI_1", "TRUST_PLUS_1", "TRUST_PLUS_MULTI_1", "TRUST_MULTI_HEAT_1" -> listOf(
            area("Продолжить микромаркет", 90, 1420, 900, 170) { openNextMicromarketStep(screenId) },
            area("Назад", 0, 0, 170, 160) { openCatalogByCart() }
        )

        "MICROMARKET_STEP_2", "TRUST_SINGLE_2", "TRUST_MULTI_2", "TRUST_PLUS_2", "TRUST_PLUS_MULTI_2", "TRUST_PLUS_MULTI_2_1", "TRUST_PLUS_MULTI_2_2", "TRUST_MULTI_HEAT_2" -> listOf(
            area("Подтвердить товары микромаркета", 90, 1420, 900, 170) { openNextMicromarketStep(screenId) },
            area("Назад", 0, 0, 170, 160) { openCatalogByCart() }
        )

        "MICROMARKET_STEP_3", "TRUST_PLUS_3", "TRUST_PLUS_MULTI_3", "TRUST_MULTI_HEAT_3" -> listOf(
            area("Добавить товары в заказ", 90, 1420, 900, 170) { addFoodToCart() },
            area("Назад", 0, 0, 170, 160) { openCatalogByCart() }
        )

        "TRUST_PLUS_MULTI_ORDER", "TRUST_PLUS_MULTI_ORDER_2", "ORDER_DEFAULT", "ORDER_VARIANT_1", "ORDER_VARIANT_2", "ORDER_VARIANT_3", "ORDER_VARIANT_4", "YOUR_ORDER", "YOUR_ORDER_2" -> orderHotspots()

        "LOYALTY_LOGIN" -> loyaltyHotspots()

        "LOYALTY_PROFILE", "LOYALTY_PROFILE_FULL", "LOYALTY_SUBSCRIPTION" -> listOf(
            area("Назад", 0, 0, 120, 120) { openOrderOrCatalog() },
            area("Закрыть лояльность", 900, 0, 130, 130) { openOrderOrCatalog() },
            area("Применить бонусы", 120, 1450, 840, 160) { applyLoyaltyBonusAndReturn() }
        )

        "LOYALTY_GET_CARD_QR", "LOYALTY_COFFEE_SUBSCRIPTION_QR" -> listOf(
            area("Назад", 0, 0, 120, 120) { openScreen("LOYALTY_LOGIN") },
            area("Закрыть QR лояльности", 900, 0, 130, 130) { openScreen("LOYALTY_LOGIN") },
            area("Вернуться", 120, 1600, 840, 160) { openScreen("LOYALTY_LOGIN") },
            area("Вернуться к вводу кода", 170, 1145, 730, 92) { openScreen("LOYALTY_LOGIN") }
        )

        "PAYMENT_METHOD_ALL", "PAYMENT_METHOD_NO_CASH" -> listOf(
            area("Оплата картой", 175, 465, 710, 215) { startPayment(PaymentMethod.CARD) },
            area("Оплата наличными", 175, 740, 710, 215) { startPayment(PaymentMethod.CASH) },
            area("Онлайн / СберСпасибо", 175, 1020, 710, 215) { startPayment(PaymentMethod.ONLINE) },
            area("Назад к заказу", 0, 0, 160, 140) { openOrderOrCatalog() },
            area("Назад к заказу", 175, 1420, 710, 215) { openOrderOrCatalog() }
        )

        "PAYMENT_POS", "PAYMENT_CASH", "PAYMENT_ONLINE_QR", "PAYMENT_ONLINE_CONFIRM" -> listOf(
            area("Подтвердить оплату", 0, 0, 1080, 1700) { finishPayment() },
            area("Отмена оплаты", 0, 1700, 300, 220) { openScreen("PAYMENT_METHOD_ALL") }
        )

        "PAYMENT_COMPLETED" -> paymentCompletedHotspots()

        "RECEIPT_EMAIL_INPUT" -> listOf(
            area("Закрыть чек", 900, 0, 130, 130) { openScreen("PAYMENT_COMPLETED") },
            area("Отправить чек", 120, 1480, 840, 160) { openScreen("RECEIPT_EMAIL_COMPLETE") }
        )

        "RECEIPT_EMAIL_COMPLETE" -> listOf(
            area("Закрыть отправку чека", 120, 1480, 840, 160) { openScreen("PAYMENT_COMPLETED") },
            area("Новый заказ", 0, 0, 1080, 1920) { resetToIdle() }
        )

        "CUP_REQUIRED" -> listOf(
            area("Стаканчик поставлен", 120, 1470, 840, 170) { machineGateway.confirmCupPlaced(); openDispenseByCart() },
            area("Помощь", 760, 1720, 300, 120) { openScreen("SUPPORT_INFO") },
            area("Назад к завершению оплаты", 0, 0, 180, 150) { openScreen("PAYMENT_COMPLETED") }
        )

        "DISPENSE_ONE_PROGRESS", "DISPENSE_ONE_PROGRESS_ALT", "DISPENSE_TWO_PROGRESS", "DISPENSE_THREE_PROGRESS", "DISPENSE_THREE_PROGRESS_ALT" -> listOf(
            area("Завершить выдачу", 0, 0, 1080, 1720) { finishDispense() },
            area("Помощь", 760, 1720, 300, 120) { openScreen("SUPPORT_INFO") }
        )

        "HEAT_FOOD_1" -> listOf(
            area("Далее разогрев 1", 120, 1460, 840, 170) { openScreen("HEAT_FOOD_2") },
            area("Назад", 0, 0, 180, 160) { openCatalogByCart() }
        )
        "HEAT_FOOD_2" -> listOf(
            area("Далее разогрев 2", 120, 1460, 840, 170) { openScreen("HEAT_FOOD_3") },
            area("Назад", 0, 0, 180, 160) { openScreen("HEAT_FOOD_1") }
        )
        "HEAT_FOOD_3" -> listOf(
            area("Запустить разогрев", 120, 1460, 840, 170) { machineGateway.heatFood(); openScreen("HEAT_FOOD_DONE") },
            area("Назад", 0, 0, 180, 160) { openScreen("HEAT_FOOD_2") }
        )
        "HEAT_FOOD_DONE" -> listOf(
            area("Продолжить заказ", 120, 1460, 840, 170) { openCatalogByCart() }
        )

        "ERROR_APOLOGIZE", "ERROR_406" -> listOf(area("Вернуться к заставке", 0, 0, 1080, 1920) { resetToIdle() })

        "SUPPORT_INFO" -> listOf(
            area("Закрыть информацию", 0, 0, 1080, 180) { openCatalogByCart() },
            area("Новый заказ", 0, 1700, 1080, 220) { resetToIdle() }
        )

        else -> listOf(area("Назад", 0, 0, 1080, 1920) { goBackSafely() })
    }

    private fun itemAddHotspots(): List<Hotspot> = listOf(
        area("Закрыть добавление товара", 910, 120, 150, 150) { openCatalogByCart() },
        area("Переключить свой стакан", 310, 730, 460, 130) { pendingOwnCup = !pendingOwnCup; rerenderCurrentScreen() },
        area("Добавить сироп ваниль", 350, 970, 420, 90) { addSyrup("Ваниль") },
        area("Добавить сироп карамель", 350, 1065, 420, 90) { addSyrup("Карамель") },
        area("Добавить сироп кокос", 350, 1160, 420, 90) { addSyrup("Кокос") },
        area("Добавить сахар", 350, 1255, 420, 90) { addSyrup("Сахар") },
        area("Удалить сироп", 625, 960, 250, 390) { if (pendingSyrup) { pendingSyrup = false; pendingSyrupName = null; rerenderCurrentScreen() } },
        area("Добавить товар в корзину", 160, 1460, 760, 160) { addPendingProductToCart() },
        area("Оплатить со скидкой", 40, 1690, 1000, 160) { addPendingProductToCart(openLoyalty = true) }
    )

    private fun itemEditHotspots(): List<Hotspot> = listOf(
        area("Закрыть редактирование", 910, 120, 150, 150) { openOrderOrCatalog() },
        area("Переключить свой стакан", 310, 730, 460, 130) { pendingOwnCup = !pendingOwnCup; rerenderCurrentScreen() },
        area("Добавить сироп", 350, 970, 420, 375) { addSyrup("Сахар") },
        area("Удалить сироп", 625, 960, 250, 390) { if (pendingSyrup) { pendingSyrup = false; pendingSyrupName = null; rerenderCurrentScreen() } },
        area("Применить изменения", 160, 1460, 760, 160) { applyEditToFirstCartLine(); openOrderOrCatalog(); toast("Изменения сохранены") }
    )

    private fun couponHotspots(): List<Hotspot> = keypadHotspots(
        originX = 340,
        originY = 1170,
        cellW = 130,
        cellH = 85,
        gapX = 8,
        gapY = 5,
        onDigit = { appendCouponDigit(it) },
        onBackspace = { if (couponInput.isNotEmpty()) { couponInput = couponInput.dropLast(1); rerenderCurrentScreen() } },
        onEnter = { applyCoupon() }
    ) + listOf(
        area("Закрыть купон", 800, 240, 140, 120) { openCatalogByCart() },
        area("Закрыть купон верх", 910, 120, 150, 150) { openCatalogByCart() }
    )

    private fun loyaltyHotspots(): List<Hotspot> = keypadHotspots(
        originX = 130,
        originY = 665,
        cellW = 120,
        cellH = 80,
        gapX = 15,
        gapY = 8,
        onDigit = { appendLoyaltyDigit(it) },
        onBackspace = { if (loyaltyInput.isNotEmpty()) { loyaltyInput = loyaltyInput.dropLast(1); rerenderCurrentScreen() } },
        onEnter = { submitLoyaltyInput() }
    ) + listOf(
        area("Назад из лояльности", 0, 0, 110, 110) { openCatalogByCart() },
        area("Получить карту лояльности", 110, 1320, 860, 390) { openScreen("LOYALTY_GET_CARD_QR") }
    )

    private fun keypadHotspots(originX: Int, originY: Int, cellW: Int, cellH: Int, gapX: Int, gapY: Int, onDigit: (String) -> Unit, onBackspace: () -> Unit, onEnter: () -> Unit): List<Hotspot> {
        val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf("back", "0", "enter"))
        val result = mutableListOf<Hotspot>()
        rows.forEachIndexed { rowIndex, row ->
            row.forEachIndexed { colIndex, key ->
                val x = originX + colIndex * (cellW + gapX)
                val y = originY + rowIndex * (cellH + gapY)
                result.add(area("Клавиша $key", x, y, cellW, cellH) {
                    when (key) {
                        "back" -> onBackspace()
                        "enter" -> onEnter()
                        else -> onDigit(key)
                    }
                })
            }
        }
        return result
    }

    private fun orderHotspots(): List<Hotspot> {
        val items = mutableListOf<Hotspot>()
        items.add(area("Назад к каталогу", 70, 1400, 240, 90) { openCatalogByCart() })
        items.add(area("Очистить заказ", 340, 1400, 240, 90) { clearOrder() })
        items.add(area("Оплатить заказ", 610, 1400, 380, 90) { goToPaymentMethod() })
        cart.take(5).forEachIndexed { index, _ ->
            val y = 340 + index * 155
            items.add(area("Минус товар $index", 635, y + 30, 70, 70) { decreaseLine(index) })
            items.add(area("Плюс товар $index", 790, y + 30, 70, 70) { increaseLine(index) })
            items.add(area("Редактировать товар $index", 75, y, 545, 125) { editLine(index) })
        }
        items.add(area("Назад верх", 0, 0, 170, 150) { openCatalogByCart() })
        return items
    }

    private fun paymentCompletedHotspots(): List<Hotspot> {
        if (recommendationPopupTitle != null) {
            return listOf(
                area("Закрыть рекомендацию", 820, 570, 140, 120) { recommendationPopupTitle = null; rerenderCurrentScreen() },
                area("Закрыть рекомендацию кнопкой", 230, 990, 620, 130) { recommendationPopupTitle = null; rerenderCurrentScreen() }
            )
        }
        val base = mutableListOf(
            area("Отправить чек", 560, 760, 300, 100) { openScreen("RECEIPT_EMAIL_INPUT") },
            area("Новый заказ", 20, 1730, 1040, 140) { resetToIdle() },
            area("Перейти к выдаче", 0, 920, 1080, 360) { openScreen("CUP_REQUIRED") }
        )
        if (recommendationsHidden) {
            base.add(area("Показать рекомендации", 330, 1390, 420, 90) { recommendationsHidden = false; rerenderCurrentScreen() })
        } else {
            base.add(area("Рекомендация 1", 45, 1390, 310, 250) { showRecommendation("Абонемент на кофе") })
            base.add(area("Рекомендация 2", 385, 1390, 310, 250) { showRecommendation("Двойной кешбэк") })
            base.add(area("Рекомендация 3", 725, 1390, 310, 250) { showRecommendation("Карта лояльности") })
            base.add(area("Закрыть предложения", 900, 1280, 130, 130) { recommendationsHidden = true; rerenderCurrentScreen() })
        }
        return base
    }

    private fun catalogHotspots(hasOrder: Boolean): List<Hotspot> {
        val items = mutableListOf<Hotspot>()
        if (hasOrder) {
            items.add(area("Добавить купон", 15, 90, 520, 150) { openScreen("COUPON_ADD") })
            items.add(area("Разогреть еду", 550, 90, 520, 150) { openScreen("HEAT_FOOD_1") })
        } else {
            items.add(area("Добавить купон", 15, 90, 335, 150) { openScreen("COUPON_ADD") })
            items.add(area("Добавить еду", 360, 90, 340, 150) { openScreen("FOOD_SCAN") })
            items.add(area("Разогреть еду", 715, 90, 335, 150) { openScreen("HEAT_FOOD_1") })
        }
        items.add(area("Информация для пользователей", 380, 1840, 340, 70) { openScreen("SUPPORT_INFO") })
        items.add(area("Поиск", 180, 1360, 720, 170) { openScreen("SEARCH_EMPTY_INPUT") })

        if (hasOrder) {
            items.add(area("Раскрыть заказ", 40, 1090, 1000, 80) { openOrderOrCatalog() })
            items.add(area("Удалить первый товар", 690, 1200, 80, 70) { decreaseLine(0) })
            items.add(area("Редактировать первый товар", 778, 1200, 110, 70) { editLine(0) })
            items.add(area("Добавить ещё первый товар", 892, 1200, 90, 70) { increaseLine(0) })
            items.add(area("Очистить заказ", 45, 1485, 130, 110) { clearOrder() })
            items.add(area("Оплатить", 190, 1485, 835, 110) { goToPaymentMethod() })
            items.add(area("Оплатить со скидкой", 40, 1710, 1000, 140) { openScreen("LOYALTY_LOGIN") })
        }
        return items
    }

    private fun area(label: String, x: Int, y: Int, width: Int, height: Int, onTap: () -> Unit): Hotspot = Hotspot(label, RectSpec(x, y, width, height), onTap)

    private fun applyAutoTransitions(screenId: String) {
        when (screenId) {
            "PAYMENT_POS", "PAYMENT_CASH", "PAYMENT_ONLINE_CONFIRM" -> handler.postDelayed({ finishPayment() }, 2600)
            "PAYMENT_ONLINE_QR" -> handler.postDelayed({ openScreen("PAYMENT_ONLINE_CONFIRM") }, 1800)
            "DISPENSE_ONE_PROGRESS", "DISPENSE_ONE_PROGRESS_ALT", "DISPENSE_TWO_PROGRESS", "DISPENSE_THREE_PROGRESS", "DISPENSE_THREE_PROGRESS_ALT" -> handler.postDelayed({ finishDispense() }, 4200)
        }
    }

    private fun startNewOrder() {
        cart.clear()
        pendingProduct = null
        pendingOwnCup = false
        pendingSyrup = false
        pendingSyrupName = null
        editingLineIndex = -1
        couponInput = ""
        loyaltyInput = ""
        couponApplied = false
        loyaltyGateway.clear()
        recommendationsHidden = false
        recommendationPopupTitle = null
        languagePopupVisible = false
        screenHistory.clear()
        openScreen("CATALOG_DEFAULT", remember = false)
    }

    private fun openCatalogByCart() {
        openScreen(if (cart.isEmpty()) "CATALOG_DEFAULT" else "CATALOG_WITH_COUPON_AND_FOOD")
    }

    private fun openOrderOrCatalog() {
        if (cart.isEmpty()) openScreen("CATALOG_DEFAULT") else openScreen("ORDER_DEFAULT")
    }

    private fun selectProduct(product: Product) {
        pendingProduct = product
        pendingOwnCup = false
        pendingSyrup = false
        pendingSyrupName = null
    }

    private fun selectProduct(index: Int) {
        val coffee = visualCoffeeProducts()
        pendingProduct = coffee.getOrNull(index) ?: coffee.firstOrNull() ?: catalog.firstOrNull()
        pendingOwnCup = false
        pendingSyrup = false
        pendingSyrupName = null
    }

    private fun addSyrup(name: String = "Ваниль") {
        pendingSyrup = true
        pendingSyrupName = name
        toast("Сироп добавлен")
        rerenderCurrentScreen()
    }

    private fun addPendingProductToCart(openPayment: Boolean = false, openLoyalty: Boolean = false) {
        val product = pendingProduct ?: catalog.firstOrNull()
        if (product == null) {
            toast("Каталог пуст")
            return
        }
        val existing = cart.firstOrNull { it.product.id == product.id && it.ownCup == pendingOwnCup && it.syrupAdded == pendingSyrup && it.syrupName == pendingSyrupName }
        if (existing == null) cart.add(CartLine(product, 1, pendingOwnCup, pendingSyrup, pendingSyrupName)) else existing.quantity++
        toast("Добавлено: ${product.name}")
        if (openPayment) goToPaymentMethod() else if (openLoyalty) openScreen("LOYALTY_LOGIN") else openCatalogByCart()
    }

    private fun applyEditToFirstCartLine() {
        val line = cart.getOrNull(editingLineIndex).let { it ?: cart.firstOrNull() } ?: return
        line.ownCup = pendingOwnCup
        line.syrupAdded = pendingSyrup
        line.syrupName = pendingSyrupName
        editingLineIndex = -1
    }

    private fun editLine(index: Int) {
        val line = cart.getOrNull(index)
        if (line == null) {
            toast("В заказе нет позиции для редактирования")
            return
        }
        pendingProduct = line.product
        pendingOwnCup = line.ownCup
        pendingSyrup = line.syrupAdded
        pendingSyrupName = if (line.syrupAdded) line.syrupName ?: "Ваниль" else null
        editingLineIndex = index
        openScreen("ITEM_EDIT")
    }

    private fun increaseLine(index: Int) {
        cart.getOrNull(index)?.quantity = (cart.getOrNull(index)?.quantity ?: 0) + 1
        rerenderCurrentScreen()
    }

    private fun decreaseLine(index: Int) {
        val line = cart.getOrNull(index) ?: return
        if (line.quantity > 1) line.quantity-- else cart.removeAt(index)
        if (cart.isEmpty()) openScreen("CATALOG_DEFAULT") else rerenderCurrentScreen()
    }

    private fun addFoodToCart() {
        val foodProducts = catalog.filter { it.category == "micromarket" }
        foodProducts.forEach { product ->
            val existing = cart.firstOrNull { it.product.id == product.id }
            if (existing == null) cart.add(CartLine(product)) else existing.quantity++
        }
        toast("Товары микромаркета добавлены в заказ")
        openScreen("ORDER_DEFAULT")
    }

    private fun clearOrder() {
        cart.clear()
        pendingProduct = null
        pendingOwnCup = false
        pendingSyrup = false
        pendingSyrupName = null
        editingLineIndex = -1
        couponApplied = false
        loyaltyGateway.clear()
        recommendationsHidden = false
        recommendationPopupTitle = null
        languagePopupVisible = false
        screenHistory.clear()
        toast("Заказ очищен")
        openScreen("CATALOG_DEFAULT", remember = false)
    }

    private fun goToPaymentMethod() {
        if (cart.isEmpty()) {
            toast("Нельзя оплатить пустой заказ")
            return
        }
        orderGateway.createOrder(cart, cartGrossTotal(), orderDiscount(), loyaltyGateway)
        openScreen("PAYMENT_METHOD_ALL")
    }

    private fun startPayment(method: PaymentMethod) {
        if (cart.isEmpty()) {
            toast("Нельзя оплатить пустой заказ")
            return
        }
        lastPaymentMethod = method
        val startResult = orderGateway.startPayment(method)
        if (startResult != OperationResult.SUCCESS) {
            orderGateway.createOrder(cart, cartGrossTotal(), orderDiscount(), loyaltyGateway)
            orderGateway.startPayment(method)
        }
        when (method) {
            PaymentMethod.CARD -> openScreen("PAYMENT_POS")
            PaymentMethod.CASH -> openScreen("PAYMENT_CASH")
            PaymentMethod.ONLINE, PaymentMethod.SBER_SPASIBO -> openScreen("PAYMENT_ONLINE_QR")
        }
    }

    private fun finishPayment() {
        if (cart.isEmpty()) {
            openScreen("PAYMENT_METHOD_ALL")
            toast("Пустой заказ не может быть оплачен")
            return
        }
        val result = orderGateway.completePayment()
        if (result == OperationResult.SUCCESS) {
            toast("Оплата принята локальным контуром. Проверьте внешний POS при боевом запуске.")
            openScreen("PAYMENT_COMPLETED")
        } else {
            openScreen("ERROR_406")
        }
    }

    private fun openDispenseByCart() {
        orderGateway.markCooking()
        val count = cart.sumOf { it.quantity }
        when {
            count <= 1 -> openScreen("DISPENSE_ONE_PROGRESS")
            count == 2 -> openScreen("DISPENSE_TWO_PROGRESS")
            else -> openScreen("DISPENSE_THREE_PROGRESS")
        }
    }

    private fun finishDispense() {
        val result = machineGateway.dispenseCoffee(orderGateway.currentOrder())
        if (result.success) {
            orderGateway.markReady()
            toast(result.message)
            openScreen("PAYMENT_COMPLETED")
        } else {
            openScreen("ERROR_APOLOGIZE")
        }
    }

    private fun openNextMicromarketStep(screenId: String) {
        when (screenId) {
            "MICROMARKET_STEP_1" -> openScreen("MICROMARKET_STEP_2")
            "MICROMARKET_STEP_2" -> openScreen("MICROMARKET_STEP_3")
            "TRUST_SINGLE_1" -> openScreen("TRUST_SINGLE_2")
            "TRUST_MULTI_1" -> openScreen("TRUST_MULTI_2")
            "TRUST_PLUS_1" -> openScreen("TRUST_PLUS_2")
            "TRUST_PLUS_2" -> openScreen("TRUST_PLUS_3")
            "TRUST_PLUS_MULTI_1" -> openScreen("TRUST_PLUS_MULTI_2")
            "TRUST_PLUS_MULTI_2" -> openScreen("TRUST_PLUS_MULTI_3")
            "TRUST_PLUS_MULTI_2_1" -> openScreen("TRUST_PLUS_MULTI_3")
            "TRUST_PLUS_MULTI_2_2" -> openScreen("TRUST_PLUS_MULTI_3")
            "TRUST_MULTI_HEAT_1" -> openScreen("TRUST_MULTI_HEAT_2")
            "TRUST_MULTI_HEAT_2" -> openScreen("TRUST_MULTI_HEAT_3")
            else -> addFoodToCart()
        }
    }

    private fun appendCouponDigit(digit: String) {
        if (couponInput.length < 6) couponInput += digit
        rerenderCurrentScreen()
    }

    private fun applyCoupon() {
        if (couponInput.length < 6) {
            toast("Введите 6 цифр купона")
            return
        }
        couponApplied = true
        toast("Купон применён")
        openCatalogByCart()
    }

    private fun appendLoyaltyDigit(digit: String) {
        if (loyaltyInput.length < 12) loyaltyInput += digit
        rerenderCurrentScreen()
    }

    private fun submitLoyaltyInput() {
        if (loyaltyInput.isBlank()) {
            toast("Введите код карты")
            return
        }
        toast("Проверяем карту лояльности…")
        contentRepository.lookupLoyaltyAsync(loyaltyInput) { result ->
            handler.post {
                if (result.success) {
                    loyaltyGateway.loginSuccess(result)
                    toast(result.message)
                    openScreen("LOYALTY_PROFILE")
                } else {
                    toast(result.message)
                    rerenderCurrentScreen()
                }
            }
        }
    }

    private fun setInterfaceLanguage(code: String) {
        currentLanguage = code
        languagePopupVisible = false
        toast(when (code) {
            "EN" -> "Language: English"
            "KZ" -> "Тіл: Қазақша"
            else -> "Язык: Русский"
        })
        rerenderCurrentScreen()
    }

    private fun showRecommendation(title: String) {
        recommendationPopupTitle = title
        rerenderCurrentScreen()
    }

    private fun goBackSafely() {
        if (currentScreen == "LOYALTY_GET_CARD_QR" || currentScreen == "LOYALTY_COFFEE_SUBSCRIPTION_QR") {
            openScreen("LOYALTY_LOGIN")
            return
        }
        if (currentScreen == "LOYALTY_PROFILE" || currentScreen == "LOYALTY_PROFILE_FULL" || currentScreen == "LOYALTY_SUBSCRIPTION") {
            openOrderOrCatalog()
            return
        }
        if (currentScreen == "LOYALTY_LOGIN") {
            openCatalogByCart()
            return
        }
        if (screenHistory.isNotEmpty()) {
            val previous = screenHistory.removeAt(screenHistory.lastIndex)
            openScreen(previous, remember = false)
        } else {
            openCatalogByCart()
        }
    }

    private fun resetToIdle() {
        cart.clear()
        pendingProduct = null
        pendingOwnCup = false
        pendingSyrup = false
        pendingSyrupName = null
        editingLineIndex = -1
        couponInput = ""
        loyaltyInput = ""
        couponApplied = false
        loyaltyGateway.clear()
        recommendationPopupTitle = null
        recommendationsHidden = false
        languagePopupVisible = false
        screenHistory.clear()
        openScreen("SCREEN_SAVER_COFFEE", remember = false)
    }

    private fun cartGrossTotal(): Int = cart.sumOf { it.product.price * it.quantity }

    private fun orderDiscount(): Int = loyaltyGateway.bonusApplied.coerceAtMost(cartGrossTotal()).coerceAtLeast(0)

    private fun cartTotal(): Int = (cartGrossTotal() - orderDiscount()).coerceAtLeast(0)

    private fun formatMoney(value: Int): String = "$value,00 ₽"

    private fun loyaltyOrderNote(full: Boolean): String? {
        if (!loyaltyGateway.attachedToOrder && orderDiscount() <= 0) return null
        val discount = orderDiscount()
        return if (discount > 0) {
            if (full) "До скидки ${formatMoney(cartGrossTotal())} • iBonus −${formatMoney(discount)}" else "iBonus −${formatMoney(discount)}"
        } else {
            val balance = loyaltyGateway.balanceLabel?.takeIf { it.isNotBlank() } ?: "0 бонусов"
            "Карта лояльности • $balance • скидка 0 ₽"
        }
    }

    private fun loyaltyPaymentSuffix(): String {
        val discount = orderDiscount()
        return when {
            discount > 0 -> " • iBonus −${formatMoney(discount)}"
            loyaltyGateway.attachedToOrder -> " • карта лояльности, скидка 0 ₽"
            else -> ""
        }
    }

    private fun applyLoyaltyBonusAndReturn() {
        val bonus = loyaltyGateway.applyBonus(cartGrossTotal())
        if (bonus > 0) {
            toast("Бонусы применены: ${formatMoney(bonus)}")
        } else if (loyaltyGateway.loggedIn) {
            toast("Карта лояльности применена. Бонусов для списания нет")
        } else {
            toast("Сначала введите код карты")
        }
        openOrderOrCatalog()
    }

    private fun toggleDemoStatus() {
        demoStatusVisible = !demoStatusVisible
        updateStatusLabel()
    }

    private fun updateStatusLabel() {
        statusLabel.visibility = if (demoStatusVisible) View.VISIBLE else View.GONE
        if (demoStatusVisible) {
            val total = cartTotal()
            statusLabel.text = "UI v0.5.7 | $currentScreen | товаров: ${cart.sumOf { it.quantity }} | сумма: $total ₽ | данные: $catalogDataSource | $catalogMessage | оплата: локальный адаптер"
        }
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }
}
