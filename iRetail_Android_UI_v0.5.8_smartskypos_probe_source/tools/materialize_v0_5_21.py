from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / 'app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt'
MANIFEST = ROOT / 'app/src/main/AndroidManifest.xml'
GRADLE = ROOT / 'app/build.gradle'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


main = MAIN.read_text(encoding='utf-8')

main = replace_once(
    main,
    '''    private lateinit var cardPaymentClient: KozenAoaPaymentClient\n    private var realPosEnabled = false\n    private var cardPaymentBusy = false\n    private var cardPaymentStatus = ""\n''',
    '''    private lateinit var cardPaymentClient: KozenAoaPaymentClient\n    private var machineModeConfig = MachineModeConfig(MachineModeStore.MODE_KIOSK, false)\n    private var realPosEnabled = false\n    private var cardPaymentBusy = false\n    private var cardPaymentStatus = ""\n''',
    'main fields'
)

main = replace_once(
    main,
    '''    override fun onCreate(savedInstanceState: Bundle?) {\n        super.onCreate(savedInstanceState)\n        window.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN)\n        hideSystemUi()\n        contentRepository = IretailContentRepository(this)\n        realPosEnabled = intent?.getBooleanExtra("real_pos_enabled", false) == true\n        cardPaymentClient = KozenAoaPaymentClient(this)\n        catalog = contentRepository.loadProducts()\n        paymentMethods = contentRepository.loadPaymentMethods()\n        buildRootView()\n        openScreen("SCREEN_SAVER_COFFEE", remember = false)\n        refreshCatalogFromIretail()\n    }\n''',
    '''    override fun onCreate(savedInstanceState: Bundle?) {\n        super.onCreate(savedInstanceState)\n        machineModeConfig = MachineModeStore.resolve(this, intent)\n        realPosEnabled = machineModeConfig.realPosEnabled\n        applyMachineModeRuntime(machineModeConfig)\n\n        if (intent?.getBooleanExtra("configure_only", false) == true) {\n            android.util.Log.i("IretailMachineMode", "CONFIGURE_ONLY mode=${machineModeConfig.mode} realPos=$realPosEnabled")\n            finishAndRemoveTask()\n            return\n        }\n\n        window.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN)\n        hideSystemUi()\n        contentRepository = IretailContentRepository(this)\n        cardPaymentClient = KozenAoaPaymentClient(this)\n        catalog = contentRepository.loadProducts()\n        paymentMethods = contentRepository.loadPaymentMethods()\n        buildRootView()\n        openScreen("SCREEN_SAVER_COFFEE", remember = false)\n        refreshCatalogFromIretail()\n    }\n\n    override fun onNewIntent(intent: android.content.Intent?) {\n        super.onNewIntent(intent)\n        setIntent(intent)\n        machineModeConfig = MachineModeStore.resolve(this, intent)\n        realPosEnabled = machineModeConfig.realPosEnabled\n        applyMachineModeRuntime(machineModeConfig)\n        android.util.Log.i("IretailMachineMode", "NEW_INTENT mode=${machineModeConfig.mode} realPos=$realPosEnabled")\n        if (intent?.getBooleanExtra("configure_only", false) == true) finishAndRemoveTask()\n    }\n\n    override fun onStart() {\n        super.onStart()\n        MainUiVisibility.started = true\n        if (machineModeConfig.standalone) ForegroundKeeperService.ensureRunning(this)\n    }\n\n    override fun onStop() {\n        MainUiVisibility.started = false\n        super.onStop()\n    }\n''',
    'onCreate lifecycle'
)

main = replace_once(
    main,
    '''    override fun onDestroy() {\n        if (::cardPaymentClient.isInitialized) cardPaymentClient.shutdown()\n        super.onDestroy()\n    }\n''',
    '''    override fun onDestroy() {\n        MainUiVisibility.started = false\n        if (::cardPaymentClient.isInitialized) cardPaymentClient.shutdown()\n        super.onDestroy()\n    }\n''',
    'onDestroy'
)

main = replace_once(
    main,
    '''        if (method == PaymentMethod.CARD && !realPosEnabled) {\n            toast("Реальный Kozen POS отключён. Запустите тестовый режим явным параметром real_pos_enabled=true.")\n            return\n        }\n''',
    '''        if (method == PaymentMethod.CARD && !realPosEnabled) {\n            val modeTitle = if (machineModeConfig.standalone) "автономный" else "кофейный киоск"\n            toast("Оплата картой отключена в режиме «$modeTitle». Включите POS один раз скриптом настройки режима.")\n            return\n        }\n''',
    'card disabled message'
)

# v0.5.20 already renders live cardPaymentStatus in portrait and landscape.
# Do not touch those blocks here; machine modes only change lifecycle/configuration policy.

MAIN.write_text(main, encoding='utf-8')

manifest = MANIFEST.read_text(encoding='utf-8')
manifest = replace_once(
    manifest,
    '''    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-feature android:name="android.hardware.usb.host" android:required="true" />\n''',
    '''    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />\n    <uses-feature android:name="android.hardware.usb.host" android:required="true" />\n''',
    'manifest permission'
)
manifest = replace_once(
    manifest,
    '''        <activity\n            android:name=".ui.MainActivity"\n            android:exported="true">\n''',
    '''        <service\n            android:name=".ui.ForegroundKeeperService"\n            android:exported="false"\n            android:stopWithTask="false" />\n        <receiver\n            android:name=".ui.BootReceiver"\n            android:enabled="true"\n            android:exported="true">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED" />\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />\n            </intent-filter>\n        </receiver>\n        <activity\n            android:name=".ui.MainActivity"\n            android:exported="true"\n            android:launchMode="singleTask">\n''',
    'manifest components'
)
MANIFEST.write_text(manifest, encoding='utf-8')

gradle = GRADLE.read_text(encoding='utf-8')
gradle = replace_once(gradle, "        versionCode 21\n        versionName '0.5.20-main-ui-kozen-aoa'\n", "        versionCode 22\n        versionName '0.5.21-machine-modes'\n", 'app version')
GRADLE.write_text(gradle, encoding='utf-8')

print('v0.5.21 source materialized successfully')
