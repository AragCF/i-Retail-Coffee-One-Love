#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        print(f"[OK] {label}: already applied")
        return
    if old not in text:
        raise SystemExit(f"[ERROR] {label}: expected source block not found in {path}")
    text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"[OK] {label}")


# 1. Main application version.
app_gradle = ROOT / "app/build.gradle"
replace_once(
    app_gradle,
    "        versionCode 20\n        versionName '0.5.10-smartskypos-transaction-lookup'",
    "        versionCode 21\n        versionName '0.5.20-main-ui-kozen-aoa'",
    "app version 0.5.20",
)

# 2. JL22 must explicitly advertise USB host usage.
manifest = ROOT / "app/src/main/AndroidManifest.xml"
replace_once(
    manifest,
    '    <uses-permission android:name="android.permission.INTERNET" />\n',
    '    <uses-permission android:name="android.permission.INTERNET" />\n'
    '    <uses-feature android:name="android.hardware.usb.host" android:required="true" />\n',
    "USB host feature",
)

# 3. Main UI: wire card payments to the AOA client while keeping real POS disabled by default.
main = ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt"
replace_once(
    main,
    "import android.app.Activity\n",
    "import android.app.Activity\nimport com.coffeeonelove.iretail.pos.KozenAoaPaymentClient\n",
    "MainActivity import Kozen client",
)

replace_once(
    main,
    "    private val loyaltyGateway = LocalLoyaltyGateway()\n    private val imageCache = mutableMapOf<String, Bitmap>()\n",
    "    private val loyaltyGateway = LocalLoyaltyGateway()\n"
    "    private lateinit var cardPaymentClient: KozenAoaPaymentClient\n"
    "    private var realPosEnabled = false\n"
    "    private var cardPaymentBusy = false\n"
    "    private var cardPaymentStatus = \"\"\n"
    "    private val imageCache = mutableMapOf<String, Bitmap>()\n",
    "MainActivity payment state",
)

replace_once(
    main,
    "        contentRepository = IretailContentRepository(this)\n"
    "        catalog = contentRepository.loadProducts()\n",
    "        contentRepository = IretailContentRepository(this)\n"
    "        realPosEnabled = intent?.getBooleanExtra(\"real_pos_enabled\", false) == true\n"
    "        cardPaymentClient = KozenAoaPaymentClient(this)\n"
    "        catalog = contentRepository.loadProducts()\n",
    "MainActivity initialize AOA client",
)

replace_once(
    main,
    "    override fun onWindowFocusChanged(hasFocus: Boolean) {\n"
    "        super.onWindowFocusChanged(hasFocus)\n"
    "        if (hasFocus) hideSystemUi()\n"
    "    }\n\n",
    "    override fun onWindowFocusChanged(hasFocus: Boolean) {\n"
    "        super.onWindowFocusChanged(hasFocus)\n"
    "        if (hasFocus) hideSystemUi()\n"
    "    }\n\n"
    "    override fun onDestroy() {\n"
    "        if (::cardPaymentClient.isInitialized) cardPaymentClient.shutdown()\n"
    "        super.onDestroy()\n"
    "    }\n\n",
    "MainActivity shutdown AOA client",
)

replace_once(
    main,
    "            \"PAYMENT_POS\" -> \"Ожидание ответа POS-терминала\"\n",
    "            \"PAYMENT_POS\" -> cardPaymentStatus.ifBlank { \"Подключение к POS-терминалу…\" }\n",
    "portrait POS status",
)

replace_once(
    main,
    "            \"PAYMENT_POS\" -> \"ПРИЛОЖИТЕ КАРТУ К ТЕРМИНАЛУ ОПЛАТЫ\"\n",
    "            \"PAYMENT_POS\" -> cardPaymentStatus.ifBlank { \"ПОДКЛЮЧЕНИЕ К POS-ТЕРМИНАЛУ…\" }.uppercase(Locale.ROOT)\n",
    "landscape POS status",
)

replace_once(
    main,
    "        screenId == \"PAYMENT_POS\" || screenId == \"PAYMENT_CASH\" || screenId == \"PAYMENT_ONLINE_QR\" || screenId == \"PAYMENT_ONLINE_CONFIRM\" -> listOf(\n"
    "            area(\"Подтвердить оплату\", 0, 80, 1920, 860) { finishPayment() },\n"
    "            area(\"Отмена оплаты\", 0, 940, 420, 140) { openScreen(\"PAYMENT_METHOD_ALL\") }\n"
    "        )\n",
    "        screenId == \"PAYMENT_POS\" -> listOf(\n"
    "            area(\"Назад к способам оплаты\", 0, 940, 420, 140) {\n"
    "                if (cardPaymentBusy) toast(\"Дождитесь ответа терминала\") else openScreen(\"PAYMENT_METHOD_ALL\")\n"
    "            }\n"
    "        )\n"
    "        screenId == \"PAYMENT_CASH\" || screenId == \"PAYMENT_ONLINE_QR\" || screenId == \"PAYMENT_ONLINE_CONFIRM\" -> listOf(\n"
    "            area(\"Подтвердить оплату\", 0, 80, 1920, 860) { finishPayment() },\n"
    "            area(\"Отмена оплаты\", 0, 940, 420, 140) { openScreen(\"PAYMENT_METHOD_ALL\") }\n"
    "        )\n",
    "landscape payment hotspots",
)

replace_once(
    main,
    "        \"PAYMENT_POS\", \"PAYMENT_CASH\", \"PAYMENT_ONLINE_QR\", \"PAYMENT_ONLINE_CONFIRM\" -> listOf(\n"
    "            area(\"Подтвердить оплату\", 0, 0, 1080, 1700) { finishPayment() },\n"
    "            area(\"Отмена оплаты\", 0, 1700, 300, 220) { openScreen(\"PAYMENT_METHOD_ALL\") }\n"
    "        )\n",
    "        \"PAYMENT_POS\" -> listOf(\n"
    "            area(\"Назад к способам оплаты\", 0, 1700, 300, 220) {\n"
    "                if (cardPaymentBusy) toast(\"Дождитесь ответа терминала\") else openScreen(\"PAYMENT_METHOD_ALL\")\n"
    "            }\n"
    "        )\n\n"
    "        \"PAYMENT_CASH\", \"PAYMENT_ONLINE_QR\", \"PAYMENT_ONLINE_CONFIRM\" -> listOf(\n"
    "            area(\"Подтвердить оплату\", 0, 0, 1080, 1700) { finishPayment() },\n"
    "            area(\"Отмена оплаты\", 0, 1700, 300, 220) { openScreen(\"PAYMENT_METHOD_ALL\") }\n"
    "        )\n",
    "portrait payment hotspots",
)

replace_once(
    main,
    "            \"PAYMENT_POS\", \"PAYMENT_CASH\", \"PAYMENT_ONLINE_CONFIRM\" -> handler.postDelayed({ finishPayment() }, 2600)\n",
    "            \"PAYMENT_CASH\", \"PAYMENT_ONLINE_CONFIRM\" -> handler.postDelayed({ finishPayment() }, 2600)\n",
    "remove fake POS auto-success",
)

old_start_finish = '''    private fun startPayment(method: PaymentMethod) {
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
'''

new_start_finish = '''    private fun startPayment(method: PaymentMethod) {
        if (cart.isEmpty()) {
            toast("Нельзя оплатить пустой заказ")
            return
        }
        if (method == PaymentMethod.CARD && !realPosEnabled) {
            toast("Реальный Kozen POS отключён. Запустите тестовый режим явным параметром real_pos_enabled=true.")
            return
        }
        lastPaymentMethod = method
        val startResult = orderGateway.startPayment(method)
        if (startResult != OperationResult.SUCCESS) {
            orderGateway.createOrder(cart, cartGrossTotal(), orderDiscount(), loyaltyGateway)
            orderGateway.startPayment(method)
        }
        when (method) {
            PaymentMethod.CARD -> {
                openScreen("PAYMENT_POS")
                startRealCardPayment()
            }
            PaymentMethod.CASH -> openScreen("PAYMENT_CASH")
            PaymentMethod.ONLINE, PaymentMethod.SBER_SPASIBO -> openScreen("PAYMENT_ONLINE_QR")
        }
    }

    private fun startRealCardPayment() {
        val order = orderGateway.currentOrder()
        if (order == null || order.amount <= 0) {
            toast("Не удалось определить сумму заказа")
            openScreen("PAYMENT_METHOD_ALL")
            return
        }
        if (cardPaymentBusy) {
            toast("Предыдущая операция оплаты ещё не завершена")
            return
        }

        val amount = String.format(Locale.US, "%d.00", order.amount)
        cardPaymentBusy = true
        cardPaymentStatus = if (cardPaymentClient.hasUnresolvedPayment()) {
            "Проверяем предыдущую незавершённую оплату…"
        } else {
            "Подключаемся к Kozen…"
        }
        rerenderCurrentScreen()

        cardPaymentClient.startPayment(amount, object : KozenAoaPaymentClient.Listener {
            override fun onStatus(message: String) {
                cardPaymentStatus = message
                if (currentScreen == "PAYMENT_POS") rerenderCurrentScreen()
            }

            override fun onResult(result: KozenAoaPaymentClient.PaymentResult) {
                cardPaymentBusy = false
                cardPaymentStatus = result.userMessage()
                when {
                    result.isApproved() -> {
                        val completed = orderGateway.completePayment()
                        if (completed == OperationResult.SUCCESS) {
                            toast("Оплата подтверждена Kozen / SmartSkyPOS. RRN ${result.rrn}")
                            openScreen("PAYMENT_COMPLETED")
                        } else {
                            openScreen("ERROR_406")
                        }
                    }
                    result.isDeclined() -> {
                        toast("Оплата отклонена: ${result.userMessage()} (rc=${result.rc})")
                        openScreen("PAYMENT_METHOD_ALL")
                    }
                    result.isUncertain() -> {
                        toast("Результат оплаты не определён. Повтор запрещён до проверки статуса.")
                        if (currentScreen == "PAYMENT_POS") rerenderCurrentScreen() else openScreen("PAYMENT_POS")
                    }
                    else -> {
                        toast(result.userMessage())
                        openScreen("PAYMENT_METHOD_ALL")
                    }
                }
            }
        })
    }

    private fun finishPayment() {
        if (lastPaymentMethod == PaymentMethod.CARD) {
            toast("Оплата картой завершается только по достоверному ответу Kozen")
            return
        }
        if (cart.isEmpty()) {
            openScreen("PAYMENT_METHOD_ALL")
            toast("Пустой заказ не может быть оплачен")
            return
        }
        val result = orderGateway.completePayment()
        if (result == OperationResult.SUCCESS) {
            toast("Оплата принята локальным контуром.")
            openScreen("PAYMENT_COMPLETED")
        } else {
            openScreen("ERROR_406")
        }
    }
'''
replace_once(main, old_start_finish, new_start_finish, "real card payment flow")

# Reset only the display state between completed/new orders. Persisted unresolved-payment safety is owned by KozenAoaPaymentClient.
replace_once(
    main,
    "        screenHistory.clear()\n        openScreen(\"CATALOG_DEFAULT\", remember = false)\n",
    "        screenHistory.clear()\n"
    "        cardPaymentBusy = false\n"
    "        cardPaymentStatus = \"\"\n"
    "        openScreen(\"CATALOG_DEFAULT\", remember = false)\n",
    "reset card payment UI state",
)

# 4. Harden Kozen service ownership itself, not only Activity debounce.
service = ROOT / "kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java"
replace_once(service, '    private static final String BRIDGE_VERSION = "0.5.0";', '    private static final String BRIDGE_VERSION = "0.5.2";', "bridge protocol version")
replace_once(
    service,
    "    private volatile IBinder smartSkyBinder;\n    private volatile boolean smartSkyBound;\n",
    "    private volatile IBinder smartSkyBinder;\n"
    "    private volatile boolean smartSkyBound;\n"
    "    private volatile boolean smartSkyBindingRequested;\n",
    "SmartSky bind request guard field",
)
replace_once(
    service,
    "            smartSkyBinder = service;\n            smartSkyBound = true;\n",
    "            smartSkyBinder = service;\n            smartSkyBound = true;\n            smartSkyBindingRequested = false;\n",
    "SmartSky connected bind guard",
)
replace_once(
    service,
    "            smartSkyBinder = null;\n            smartSkyBound = false;\n            Log.w(TAG, \"SMARTSKY_DISCONNECTED component=\" + name);\n",
    "            smartSkyBinder = null;\n            smartSkyBound = false;\n            smartSkyBindingRequested = false;\n            Log.w(TAG, \"SMARTSKY_DISCONNECTED component=\" + name);\n",
    "SmartSky disconnected bind guard",
)
replace_once(
    service,
    "            smartSkyBinder = null;\n            smartSkyBound = false;\n            Log.w(TAG, \"SMARTSKY_BINDING_DIED component=\" + name);\n            bindSmartSky();\n",
    "            smartSkyBinder = null;\n            smartSkyBound = false;\n            smartSkyBindingRequested = false;\n            Log.w(TAG, \"SMARTSKY_BINDING_DIED component=\" + name);\n            bindSmartSky();\n",
    "SmartSky binding died guard",
)
replace_once(
    service,
    "            smartSkyBinder = null;\n            smartSkyBound = false;\n            Log.e(TAG, \"SMARTSKY_NULL_BINDING component=\" + name);\n",
    "            smartSkyBinder = null;\n            smartSkyBound = false;\n            smartSkyBindingRequested = false;\n            Log.e(TAG, \"SMARTSKY_NULL_BINDING component=\" + name);\n",
    "SmartSky null binding guard",
)
replace_once(
    service,
    "        final UsbAccessory selected = accessory;\n"
    "        synchronized (accessoryLock) {\n"
    "            closeAccessoryLocked();\n"
    "            ioThread = new Thread(() -> runBridge(selected), \"iretail-kozen-production-bridge\");\n"
    "            ioThread.start();\n"
    "        }\n",
    "        final UsbAccessory selected = accessory;\n"
    "        synchronized (accessoryLock) {\n"
    "            if (ioThread != null && ioThread.isAlive()) {\n"
    "                Log.i(TAG, \"SERVICE_START_DUPLICATE_IGNORED activeThread=true bridge=\" + BRIDGE_VERSION);\n"
    "                return START_NOT_STICKY;\n"
    "            }\n"
    "            closeAccessoryLocked();\n"
    "            ioThread = new Thread(() -> runBridge(selected), \"iretail-kozen-production-bridge\");\n"
    "            ioThread.start();\n"
    "        }\n",
    "service-level single AOA owner",
)
replace_once(
    service,
    "        smartSkyBinder = null;\n        smartSkyBound = false;\n        super.onDestroy();\n",
    "        smartSkyBinder = null;\n"
    "        smartSkyBound = false;\n"
    "        smartSkyBindingRequested = false;\n"
    "        super.onDestroy();\n",
    "reset SmartSky bind guard on destroy",
)
replace_once(
    service,
    "    private void bindSmartSky() {\n"
    "        if (smartSkyBound && smartSkyBinder != null && smartSkyBinder.isBinderAlive()) return;\n"
    "        try {\n"
    "            Intent intent = new Intent(SMARTSKY_ACTION);\n"
    "            intent.setComponent(new ComponentName(SMARTSKY_PACKAGE, SMARTSKY_SERVICE));\n"
    "            boolean ok = bindService(intent, smartSkyConnection, Context.BIND_AUTO_CREATE);\n"
    "            Log.i(TAG, \"SMARTSKY_BIND_REQUEST ok=\" + ok);\n"
    "            if (!ok) {\n"
    "                smartSkyBound = false;\n"
    "                smartSkyBinder = null;\n"
    "            }\n"
    "        } catch (Exception e) {\n"
    "            smartSkyBound = false;\n"
    "            smartSkyBinder = null;\n"
    "            Log.e(TAG, \"SMARTSKY_BIND_ERROR \" + e.getClass().getSimpleName() + \": \" + safe(e.getMessage()));\n"
    "        }\n"
    "    }\n",
    "    private void bindSmartSky() {\n"
    "        if (smartSkyBound && smartSkyBinder != null && smartSkyBinder.isBinderAlive()) return;\n"
    "        if (smartSkyBindingRequested) return;\n"
    "        smartSkyBindingRequested = true;\n"
    "        try {\n"
    "            Intent intent = new Intent(SMARTSKY_ACTION);\n"
    "            intent.setComponent(new ComponentName(SMARTSKY_PACKAGE, SMARTSKY_SERVICE));\n"
    "            boolean ok = bindService(intent, smartSkyConnection, Context.BIND_AUTO_CREATE);\n"
    "            Log.i(TAG, \"SMARTSKY_BIND_REQUEST ok=\" + ok);\n"
    "            if (!ok) {\n"
    "                smartSkyBindingRequested = false;\n"
    "                smartSkyBound = false;\n"
    "                smartSkyBinder = null;\n"
    "            }\n"
    "        } catch (Exception e) {\n"
    "            smartSkyBindingRequested = false;\n"
    "            smartSkyBound = false;\n"
    "            smartSkyBinder = null;\n"
    "            Log.e(TAG, \"SMARTSKY_BIND_ERROR \" + e.getClass().getSimpleName() + \": \" + safe(e.getMessage()));\n"
    "        }\n"
    "    }\n",
    "single SmartSky bind request",
)

bridge_gradle = ROOT / "kozenBridge/build.gradle"
replace_once(
    bridge_gradle,
    "        versionCode 8\n        versionName '0.5.1-production-start-debounce'",
    "        versionCode 9\n        versionName '0.5.2-production-session-owner'",
    "Kozen bridge version 0.5.2",
)

bridge_activity = ROOT / "kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/BridgeActivity.java"
replace_once(
    bridge_activity,
    '        title.setText("i-Retail Kozen Payment Bridge 0.5.1\\nUSB/AOA → SmartSkyPOS");',
    '        title.setText("i-Retail Kozen Payment Bridge 0.5.2\\nUSB/AOA → SmartSkyPOS");',
    "Kozen bridge UI version",
)

print("[SUCCESS] v0.5.20 source integration materialized")
