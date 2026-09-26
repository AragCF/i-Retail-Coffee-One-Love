from pathlib import Path
import re, subprocess
root = Path.cwd()
u = root / 'app/src/main/java/com/coffeeonelove/iretail/ui'
BASE = '58622dcbb7de6dfcc7a622522fc5878bd10a7cad'
# Existing source files must still be exactly the tested v127 baseline.
new_allowed = {
 '.github/workflows/prepare-device-binding-128.yml', 'tools/prepare_device_binding_128.py',
 'app/src/main/java/com/coffeeonelove/iretail/ui/DeviceBindingCore.kt',
 'app/src/main/java/com/coffeeonelove/iretail/ui/DeviceBindingStore.kt',
 'app/src/main/java/com/coffeeonelove/iretail/ui/DeviceBindingRuntime.kt',
 'app/src/main/java/com/coffeeonelove/iretail/ui/DeviceBindingActivity.kt',
 'app/src/test/java/com/coffeeonelove/iretail/ui/DeviceBindingTest.kt'
}
changed = set(subprocess.check_output(['git','diff','--name-only',BASE,'HEAD'], text=True).splitlines())
assert changed <= new_allowed, ('Unexpected base changes', sorted(changed-new_allowed))
p=u/'IntegrationGateways.kt'; s=p.read_text()
def rep(a,b):
 global s
 assert a in s, a[:160]
 s=s.replace(a,b,1)
rep('    private val apiConfig: IretailApiConfig by lazy { loadApiConfig() }\n    private val cacheFile: File by lazy { File(context.filesDir, "iretail_catalog_cache.zip") }', '''    private val bindingRecord: JSONObject? by lazy {
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
''')
rep('    fun loadProducts(): List<Product> {\n        if (cacheFile.exists()) {\n            val cached = try { parseCatalogZip(cacheFile.readBytes()) } catch (_: Exception) { null }\n            if (cached?.structureValid == true) return cached.products\n        }', '''    fun loadProducts(): List<Product> {
        if (!hasBoundConfiguration()) return emptyList()
        val cached = readCatalogCache()
        if (cached?.structureValid == true) return cached.products''')
rep('    fun refreshProductsAsync(onResult: (CatalogRefreshResult) -> Unit) {', '''    fun refreshProductsAsync(onResult: (CatalogRefreshResult) -> Unit) {
        if (!hasBoundConfiguration()) {
            onResult(CatalogRefreshResult(false, emptyList(), "Сначала привяжите устройство", "I-Retail unbound",
                failureStage = "binding", failureReason = "UNBOUND"))
            return
        }''')
rep('val cached = try { parseCatalogZip(cacheFile.readBytes()) } catch (_: Exception) { null }','val cached = readCatalogCache()')
rep('    fun lookupLoyaltyAsync(input: String, onResult: (LoyaltyLookupResult) -> Unit) {', '''    fun lookupLoyaltyAsync(input: String, onResult: (LoyaltyLookupResult) -> Unit) {
        if (!DeviceBindingStore.get(context).isReady()) {
            onResult(LoyaltyLookupResult(false, "Сначала завершите привязку устройства"))
            return
        }''')
rep('    fun refreshChannelConfigAsync(onResult: (ChannelConfigRefreshResult) -> Unit) {', '''    fun refreshChannelConfigAsync(onResult: (ChannelConfigRefreshResult) -> Unit) {
        if (!hasBoundConfiguration()) {
            onResult(ChannelConfigRefreshResult(false, emptyList(), "Сначала привяжите устройство", "I-Retail unbound",
                failureReason = "UNBOUND"))
            return
        }''')
rep('                val serviceResult = services.optJSONObject("result")', '''                require(DeviceBindingProtocol.id(channelResult.opt("id")) == apiConfig.channelId) { "CHANNEL_MISMATCH" }
                require(DeviceBindingProtocol.id(channelResult.opt("profile_id")) == apiConfig.profileId) { "PROFILE_MISMATCH" }
                val serviceResult = services.optJSONObject("result")''')
rep('            val enabled = if (service.has("enabled")) service.optBooleanNullable("enabled") == true else true', '''            // TSO/API uses settings.enable; XML uses enabled. Unknown is not authorization.
            val enabled = service.optJSONObject("settings")?.optBooleanNullable("enable") == true''')
rep('                LoyaltyLookupResult(false, "Лояльность I-Retail недоступна: ${e.cleanMessage()}")', '                LoyaltyLookupResult(false, "Лояльность I-Retail недоступна (${safeCatalogFailureReason(e)})")')
rep('throw IllegalStateException("HTTP $code: ${body.toString(Charsets.UTF_8).take(160)}")','throw IllegalStateException("HTTP $code")')
rep('    private fun postFormBytes(path: String, fields: Map<String, String>): ByteArray {', '''    private fun postFormBytes(path: String, fields: Map<String, String>): ByteArray {
        check(hasBoundConfiguration()) { "UNBOUND" }''')
rep('            requestMethod = "POST"','            requestMethod = "POST"\n            instanceFollowRedirects = false\n            setFixedLengthStreamingMode(payload.size)')
start=s.index('    private fun loadApiConfig(): IretailApiConfig {'); end=s.index('    private fun normalizePhone(',start)
s=s[:start]+'''    private fun loadApiConfig(): IretailApiConfig {
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

'''+s[end:]
start=s.index('    private data class IretailApiConfig('); end=s.index('    private data class ParsedCatalog',start)
block=re.sub(r'val (clientSecret|profileId|channelId|currencyId|deviceCode|deviceId): String = "[^"]*"',r'val \1: String = ""',s[start:end])
s=s[:start]+block+s[end:]
start=s.index('    private fun persistValidatedCatalog(zipBytes: ByteArray) {');end=s.index('    private fun readAsset(',start)
s=s[:start]+'''    private fun readCatalogCache(): ParsedCatalog? = synchronized(CATALOG_CACHE_LOCK) {
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

'''+s[end:]
rep('class LocalRetailOrderGateway {','class LocalRetailOrderGateway(private val canCreateOrder: () -> Boolean = { DeviceBindingAccess.isReady() }) {')
needle='    fun createOrder(lines: List<CartLine>, grossAmountMinor: Long, ibonusDiscountMinor: Long = 0L, loyalty: LocalLoyaltyGateway? = null): RuntimeOrder {'
rep(needle,needle+'\n        check(canCreateOrder()) { "UNBOUND_ORDER_BLOCKED" }')
for name in ['startPayment(method: PaymentMethod)', 'markPaymentConfirmed()']:
 needle='    fun '+name+': OperationResult {'
 rep(needle,needle+'\n        if (!canCreateOrder()) return OperationResult.ERROR')
p.write_text(s)
p=u/'MainActivity.kt';s=p.read_text()
rep('        applyMachineModeRuntime(machineModeConfig)\n', '        applyMachineModeRuntime(machineModeConfig)\n        if (!requireDeviceBinding()) return\n')
rep('        setIntent(intent)\n','        setIntent(intent)\n        if (!requireDeviceBinding()) return\n')
rep('        super.onStart()\n', '        super.onStart()\n        if (isFinishing || !requireDeviceBinding()) return\n')
rep('    private fun openScreen(screenId: String, remember: Boolean = true) {', '    private fun openScreen(screenId: String, remember: Boolean = true) {\n        if (!requireDeviceBinding()) return')
rep('    private fun submitLoyaltyInput() {','    private fun submitLoyaltyInput() {\n        if (!requireDeviceBinding()) return')
rep('    private fun startPayment(method: PaymentMethod) {', '''    private fun startPayment(method: PaymentMethod) {
        if (!requireDeviceBinding()) return
        if (!DeviceBindingAccess.financialAllowed()) {
            toast("Финансовые операции отложены. Сейчас проверяем привязку и API.")
            return
        }''')
rep('    private fun startRealCardPayment() {','    private fun startRealCardPayment() {\n        if (!requireDeviceBinding() || !DeviceBindingAccess.financialAllowed()) return')
rep('    private fun openDispenseByCart() {','    private fun openDispenseByCart() {\n        if (!requireDeviceBinding() || !DeviceBindingAccess.financialAllowed()) return')
rep('    private fun finishDispense() {','    private fun finishDispense() {\n        if (!requireDeviceBinding() || !DeviceBindingAccess.financialAllowed()) return')
rep('    private fun paymentMethodAllowedByServer(method: PaymentMethod): Boolean {','    private fun paymentMethodAllowedByServer(method: PaymentMethod): Boolean {\n        if (!DeviceBindingAccess.financialAllowed()) return false')
rep('    private fun paymentMethodBlockedCaption(method: PaymentMethod): String {','    private fun paymentMethodBlockedCaption(method: PaymentMethod): String {\n        if (!DeviceBindingAccess.financialAllowed()) return "Платежи отложены: проверяем API"')
rep('positiveTestRequested && debuggable && machineModeConfig.standalone && realPosEnabled','positiveTestRequested && debuggable && machineModeConfig.standalone && realPosEnabled && DeviceBindingAccess.financialAllowed()')
rep('    private fun maybeRunSbpLiveQrGenerationProbe(intent: android.content.Intent?, source: String) {','    private fun maybeRunSbpLiveQrGenerationProbe(intent: android.content.Intent?, source: String) {\n        if (!DeviceBindingAccess.financialAllowed()) return')
needle='    private fun buildRootView() {'
rep(needle,'''    private fun requireDeviceBinding(): Boolean {
        if (DeviceBindingStore.get(this).isReady()) return true
        if (!isFinishing) {
            android.util.Log.i("IretailBinding", "CUSTOMER_UI_BLOCKED")
            startActivity(android.content.Intent(this, DeviceBindingActivity::class.java).apply {
                addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP)
            })
            finish()
        }
        return false
    }

'''+needle)
s=s.replace('UI v0.5.127 |','UI v0.5.128 |');p.write_text(s)
p=root/'app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java';s=p.read_text()
rep('    public void startPayment(String amountRub, Listener listener) {\n        if (listener == null) return;', '''    public void startPayment(String amountRub, Listener listener) {
        if (listener == null) return;
        if (!com.coffeeonelove.iretail.ui.DeviceBindingAccess.financialAllowed()) {
            deliverResult(listener, PaymentResult.local("-", "BLOCKED", "API_PHASE_NO_FINANCIAL", "Платежи отложены: проверяем API и привязку"));
            return;
        }''')
needle='    public void startSbpLiveQrGenerationProbe(SbpLiveQrProbeListener listener) {'
rep(needle,needle+'''
        if (!com.coffeeonelove.iretail.ui.DeviceBindingAccess.financialAllowed()) {
            if (listener != null) main.post(() -> listener.onFinal(PaymentResult.local("-", "BLOCKED", "API_PHASE_NO_FINANCIAL", "Финансовые пробы отключены")));
            return;
        }''')
p.write_text(s)
p=root/'app/src/main/AndroidManifest.xml';s=p.read_text()
rep('        <activity\n            android:name=".ui.MainActivity"', '''        <activity
            android:name=".ui.DeviceBindingActivity"
            android:exported="false"
            android:launchMode="singleTask"
            android:windowSoftInputMode="adjustResize" />
        <activity
            android:name=".ui.MainActivity"''')
p.write_text(s)
p=root/'app/src/main/assets/content/iretail-api.json'
p.write_text('''{
  "enabled": true,
  "base_url": "https://my.i-retail.com/api/",
  "client_id": "IRETAIL_TERMINAL",
  "provisioning": "device_binding_wizard",
  "binding_required": true
}
''')
p=root/'app/src/test/java/com/coffeeonelove/iretail/ui/ApiLifecycleSafetyTest.kt'
p.write_text(p.read_text().replace('val gateway = LocalRetailOrderGateway()', 'val gateway = LocalRetailOrderGateway { true }'))
p=root/'app/build.gradle';s=p.read_text().replace('versionCode 127','versionCode 128').replace("versionName '0.5.127-api-lifecycle-safety'","versionName '0.5.128-device-binding'")
s=s.replace("testImplementation 'junit:junit:4.13.2'", "testImplementation 'junit:junit:4.13.2'\n    testImplementation 'org.json:json:20240303'")
p.write_text(s)
for p in root.glob('*.bat'):
 raw=p.read_bytes();new=raw.replace(b'0.5.127-api-lifecycle-safety',b'0.5.128-device-binding')
 if new!=raw:p.write_bytes(new)
p=root/'.github/workflows/android-build.yml';p.write_text(p.read_text().replace('iRetail-v0.5.126-debug-apk','iRetail-v0.5.128-debug-apk'))
p=u/'MachineModeRuntime.kt';s=p.read_text()
rep('    @Volatile var started: Boolean = false', '''    @Volatile private var customerStarted: Boolean = false
    @Volatile var bindingStarted: Boolean = false
    var started: Boolean
        get() = customerStarted || bindingStarted
        set(value) { customerStarted = value }''')
p.write_text(s)
for p in list((root/'app/src/main/java/com/coffeeonelove/iretail/pos').glob('*Activity.kt'))+list((root/'app/src/main/java/com/coffeeonelove/iretail/vendotek').glob('*Activity.kt')):
 s=p.read_text()
 rep('        super.onCreate(savedInstanceState)', '''        super.onCreate(savedInstanceState)
        if (!com.coffeeonelove.iretail.ui.DeviceBindingStore.get(this).isReady()) {
            startActivity(android.content.Intent(this, com.coffeeonelove.iretail.ui.MainActivity::class.java))
            finish()
            return
        }''')
 p.write_text(s)
p=u/'OrderSyncDraft.kt';s=p.read_text()
a=s.index('    private fun readNonSecretConfig(): DraftConfig {');b=s.index('    private fun readEvidence()',a)
s=s[:a]+'''    private fun readNonSecretConfig(): DraftConfig {
        return try {
            val record = DeviceBindingStore.get(context).configuredRecord() ?: return DraftConfig()
            val identity = BindingRecordPolicy.identity(record)
            val channel = BindingRecordPolicy.configuration(record)
            DraftConfig(channelId = identity.channelId, deviceId = identity.deviceId,
                currencyId = DeviceBindingProtocol.id(channel.getJSONObject("currency").opt("id")))
        } catch (_: Exception) { DraftConfig() }
    }

'''+s[b:];p.write_text(s)
print('BINDING_SOURCE_PREPARED')
