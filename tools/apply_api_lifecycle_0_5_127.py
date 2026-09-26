"""Base-checked preparation of v0.5.127; no API or device operations.

The temporary CI workflow tests and builds the result before committing it.
All source preimages must match BASE; changes are prepared before writing.
"""
from pathlib import Path
import hashlib
import re
import subprocess

BASE = 'c76b33bd1457f5f17c058a8a24e5fbcea0f0010a'
BRANCH = 'v0.5.127-api-lifecycle-safety'
VERSION = '0.5.127-api-lifecycle-safety'
ROOT = Path(__file__).resolve().parents[1]
UI = 'app/src/main/java/com/coffeeonelove/iretail/ui/'
changed = {}


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def original(path):
    data = (ROOT / path).read_bytes()
    if data != git('show', BASE + ':' + path):
        raise RuntimeError('Base mismatch: ' + path)
    return data.decode('utf-8')


def replace(text, old, new, label):
    if text.count(old) != 1:
        raise RuntimeError('Expected exactly one anchor: ' + label)
    return text.replace(old, new, 1)


def section(text, start, end, change):
    if text.count(start) != 1 or text.count(end) != 1:
        raise RuntimeError('Ambiguous section: ' + start)
    a, b = text.index(start), text.index(end)
    if b <= a:
        raise RuntimeError('Invalid section bounds')
    return text[:a] + change(text[a:b]) + text[b:]


def put(path, text):
    changed[path] = text.encode('utf-8')


def new_file(path, text):
    if (ROOT / path).exists():
        raise RuntimeError('New path already exists: ' + path)
    put(path, text)


if git('branch', '--show-current').decode().strip() != BRANCH:
    raise SystemExit('Refusing to modify a different branch')
if git('status', '--porcelain').strip():
    raise SystemExit('Working tree must be clean')

main = original(UI + 'MainActivity.kt')
main = replace(main,
    '    private val syncHandler = Handler(Looper.getMainLooper())\n',
    '''    private val syncHandler = Handler(Looper.getMainLooper())
    // Screen navigation clears handler, but must not discard completed API reads.
    private val apiResultHandler = Handler(Looper.getMainLooper())
    private val catalogReadGate = ApiRequestGate()
    private val channelReadGate = ApiRequestGate()
    private val loyaltyReadGate = ApiRequestGate()
    @Volatile private var apiOwnerDestroyed = false
    private var apiUiStarted = false
    private var apiUiNeedsRender = false
    private var apiUiHasStarted = false
    private var lastResumeRefreshMs = 0L
''', 'API handlers')
main = replace(main,
    '''        override fun run() {
            if (::contentRepository.isInitialized && !fiscalPositivePaymentTestMode) {
''',
    '''        override fun run() {
            if (!apiUiStarted || apiOwnerDestroyed || isFinishing) return
            if (::contentRepository.isInitialized && !fiscalPositivePaymentTestMode) {
''', 'periodic owner guard')
main = replace(main,
    '''        MainUiVisibility.started = true
        syncHandler.removeCallbacks(periodicServerRefresh)
''',
    '''        MainUiVisibility.started = true
        apiUiStarted = true
        if (::root.isInitialized && apiUiNeedsRender) renderApiChanges()
        val now = android.os.SystemClock.elapsedRealtime()
        if (apiUiHasStarted && ::contentRepository.isInitialized && !isFinishing &&
            !fiscalPositivePaymentTestMode && now - lastResumeRefreshMs >= 30_000L) {
            lastResumeRefreshMs = now
            refreshCatalogFromIretail(silent = true)
            refreshChannelConfigFromIretail(silent = true)
        }
        apiUiHasStarted = true
        syncHandler.removeCallbacks(periodicServerRefresh)
''', 'resume data refresh')
main = replace(main,
    '''    override fun onStop() {
        syncHandler.removeCallbacks(periodicServerRefresh)
''',
    '''    override fun onStop() {
        apiUiStarted = false
        loyaltyReadGate.invalidate()
        syncHandler.removeCallbacks(periodicServerRefresh)
''', 'stop owner')
main = replace(main,
    '''    override fun onDestroy() {
        MainUiVisibility.started = false
''',
    '''    override fun onDestroy() {
        apiOwnerDestroyed = true
        apiUiStarted = false
        catalogReadGate.close()
        channelReadGate.close()
        loyaltyReadGate.close()
        apiResultHandler.removeCallbacksAndMessages(null)
        syncHandler.removeCallbacks(periodicServerRefresh)
        MainUiVisibility.started = false
''', 'destroy owner')


def change_read(body, method, gate):
    body = replace(body,
        '        contentRepository.' + method + ' { result ->\n            handler.post {\n',
        '        if (apiOwnerDestroyed || isFinishing || !::contentRepository.isInitialized) return\n'
        '        val ticket = ' + gate + '.tryBegin() ?: return\n'
        '        contentRepository.' + method + ' { result ->\n'
        '            if (apiOwnerDestroyed) {\n'
        '                ' + gate + '.complete(ticket)\n'
        '                return@' + method + '\n'
        '            }\n'
        '            apiResultHandler.post {\n'
        '                if (!' + gate + '.complete(ticket) || apiOwnerDestroyed || isFinishing || isDestroyed) return@post\n',
        method)
    body = body.replace('if (!silent &&\n', 'if (!silent && apiUiStarted &&\n')
    body = body.replace('rerenderCurrentScreen()', 'renderApiChanges()')
    body = body.replace('updateStatusLabel()', 'renderApiChanges()')
    body = body.replace('toast(', 'toastApi(')
    body = body.replace('                    renderApiChanges()\n                    renderApiChanges()', '                    renderApiChanges()')
    return body

main = section(main, '    private fun refreshCatalogFromIretail(',
    '    private fun refreshChannelConfigFromIretail(',
    lambda b: change_read(b, 'refreshProductsAsync', 'catalogReadGate'))
main = section(main, '    private fun refreshChannelConfigFromIretail(',
    '    override fun onWindowFocusChanged(',
    lambda b: change_read(b, 'refreshChannelConfigAsync', 'channelReadGate'))
main = replace(main, '    override fun onWindowFocusChanged(hasFocus: Boolean) {',
    '''    private fun renderApiChanges() {
        if (apiOwnerDestroyed || isFinishing || isDestroyed) return
        apiUiNeedsRender = true
        if (!apiUiStarted || !::root.isInitialized) return
        apiUiNeedsRender = false
        root.post {
            if (apiOwnerDestroyed || isFinishing || isDestroyed) return@post
            if (!apiUiStarted) {
                apiUiNeedsRender = true
                return@post
            }
            renderDynamicLayer(currentScreen)
            renderHotspots(currentScreen)
            updateStatusLabel()
        }
    }

    private fun toastApi(message: String) {
        if (apiUiStarted && !apiOwnerDestroyed && !isFinishing) toast(message)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {''', 'API rendering')
main = replace(main,
    '''    private fun openScreen(screenId: String, remember: Boolean = true) {
        handler.removeCallbacksAndMessages(null)
''',
    '''    private fun openScreen(screenId: String, remember: Boolean = true) {
        if (currentScreen == "LOYALTY_LOGIN" && screenId != currentScreen) {
            loyaltyReadGate.invalidate()
        }
        handler.removeCallbacksAndMessages(null)
''', 'loyalty navigation')
main = section(main, '    private fun submitLoyaltyInput() {',
    '    private fun setInterfaceLanguage(', lambda _:
    '''    private fun submitLoyaltyInput() {
        val query = loyaltyInput.trim()
        if (query.isBlank()) {
            toast("Введите код карты")
            return
        }
        if (apiOwnerDestroyed || !apiUiStarted || isFinishing) return
        val ticket = loyaltyReadGate.tryBegin()
        if (ticket == null) {
            toast("Предыдущая проверка карты ещё не завершена")
            return
        }
        toast("Проверяем карту лояльности…")
        contentRepository.lookupLoyaltyAsync(query) { result ->
            if (apiOwnerDestroyed) {
                loyaltyReadGate.complete(ticket)
                return@lookupLoyaltyAsync
            }
            apiResultHandler.post {
                if (!loyaltyReadGate.complete(ticket) || apiOwnerDestroyed || isFinishing || isDestroyed) return@post
                if (!apiUiStarted || currentScreen != "LOYALTY_LOGIN" || loyaltyInput.trim() != query) return@post
                if (result.success && result.loyaltyActive) {
                    loyaltyGateway.loginSuccess(result)
                    toast(result.message)
                    openScreen("LOYALTY_PROFILE")
                } else {
                    toast(result.message)
                    renderApiChanges()
                }
            }
        }
    }

''')
main = replace(main, '    private fun resetToIdle() {\n',
    '    private fun resetToIdle() {\n        loyaltyReadGate.invalidate()\n', 'new client session')
main = section(main, '    private fun orderDiscountMinor(): Long {',
    '    private fun cartTotalMinor()', lambda _:
    '''    private fun orderDiscountMinor(): Long {
        // Balance is not authorization to redeem. No server redemption contract yet.
        return 0L
    }

''')
main = main.replace('UI v0.5.126 |', 'UI v0.5.127 |')
put(UI + 'MainActivity.kt', main)

repo = original(UI + 'IntegrationGateways.kt')
repo = replace(repo,
    '''                if (!services.optBoolean("status", false)) {''',
    '''                if (!channel.optBoolean("status", false)) {
                    throw IllegalStateException("channel rejected")
                }
                if (!services.optBoolean("status", false)) {''', 'channel envelope')
repo = replace(repo,
    '''                val channelResult = channel.optJSONObject("result")\n''',
    '''                val channelResult = channel.optJSONObject("result")
                    ?: throw IllegalStateException("channel result missing")
''', 'channel required result')
repo = replace(repo,
    'parseServerPaymentMethods(serviceResult.optJSONArray("services"))',
    'parseServerPaymentMethods(serviceResult.getJSONArray("services"))', 'services required array')
repo = replace(repo,
    '            val service = services.optJSONObject(i) ?: continue',
    '            val service = services.getJSONObject(i)', 'malformed service is not a missing service')
repo = replace(repo,
    '            if (slug.isBlank()) continue',
    '            if (slug.isBlank()) throw IllegalStateException("service slug missing")', 'service key')
repo = replace(repo,
    '            val enabled = if (service.has("enabled")) service.optBoolean("enabled", false) else true',
    '            val enabled = if (service.has("enabled")) service.optBooleanNullable("enabled") == true else true',
    'numeric service enabled')
repo = replace(repo,
    '            is Number -> raw.toInt() != 0',
    '''            is Number -> when (raw.toDouble()) {
                1.0 -> true
                0.0 -> false
                else -> null
            }''', 'unknown numeric flag')
repo = replace(repo,
    '        val safeDiscountMinor = ibonusDiscountMinor.coerceIn(0L, safeGrossMinor)',
    '''        // This gateway has no proof of a server-authorized bonus redemption.
        // Keep the compatibility argument, but never trust it as an approved discount.
        val safeDiscountMinor = 0L''', 'order redemption boundary')
repo = replace(repo,
    '        bonusApplied = maxAmount.coerceAtMost(availableBonusAmount).coerceAtLeast(0)',
    '''        // Read-only loyalty stage: caller-supplied amount cannot authorize redemption.
        bonusApplied = 0''', 'gateway redemption boundary')
repo = replace(repo,
    '    fun loginSuccess(result: LoyaltyLookupResult) {\n        loggedIn = true',
    '''    fun loginSuccess(result: LoyaltyLookupResult) {
        if (!result.success || !result.loyaltyActive) {
            clear()
            return
        }
        loggedIn = true''', 'loyalty success validation')
put(UI + 'IntegrationGateways.kt', repo)

new_file(UI + 'ApiRequestGate.java', r'''package com.coffeeonelove.iretail.ui;

/** One active read per owner. Invalidation rejects the result, not the running I/O. */
public final class ApiRequestGate {
    private long sequence;
    private long generation;
    private long activeTicket;
    private long activeGeneration;
    private boolean closed;

    public synchronized Long tryBegin() {
        if (closed || activeTicket != 0L) return null;
        activeTicket = ++sequence;
        activeGeneration = generation;
        return activeTicket;
    }

    /** A foreign or repeated completion must not release a newer request. */
    public synchronized boolean complete(long ticket) {
        if (ticket == 0L || ticket != activeTicket) return false;
        boolean accepted = !closed && activeGeneration == generation;
        activeTicket = 0L;
        return accepted;
    }

    /** Keep the occupied slot until the running read actually returns. */
    public synchronized void invalidate() {
        generation++;
    }

    public synchronized void close() {
        closed = true;
        generation++;
    }
}
''')

gradle = original('app/build.gradle')
gradle = replace(gradle, 'versionCode 126', 'versionCode 127', 'app code')
gradle = replace(gradle, "versionName '0.5.126-server-managed-integrations'",
    "versionName '" + VERSION + "'", 'app name')
gradle = replace(gradle, "    implementation 'com.google.zxing:core:3.5.4'",
    "    implementation 'com.google.zxing:core:3.5.4'\n    testImplementation 'junit:junit:4.13.2'", 'JVM tests only')
put('app/build.gradle', gradle)

new_file('app/src/test/java/com/coffeeonelove/iretail/ui/ApiLifecycleSafetyTest.kt', r'''package com.coffeeonelove.iretail.ui

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ApiLifecycleSafetyTest {
    @Test fun parallelReadDoesNotStart() {
        val gate = ApiRequestGate()
        val ticket = gate.tryBegin()!!
        assertNull(gate.tryBegin())
        assertTrue(gate.complete(ticket))
        assertNotNull(gate.tryBegin())
    }
    @Test fun oldSessionCannotApplyOrOverlap() {
        val gate = ApiRequestGate()
        val ticket = gate.tryBegin()!!
        gate.invalidate()
        assertNull(gate.tryBegin())
        assertFalse(gate.complete(ticket))
        val next = gate.tryBegin()!!
        assertFalse(gate.complete(ticket))
        assertNull(gate.tryBegin())
        assertTrue(gate.complete(next))
    }
    @Test fun destroyedOwnerRejectsResult() {
        val gate = ApiRequestGate()
        val ticket = gate.tryBegin()!!
        gate.close()
        assertFalse(gate.complete(ticket))
        assertNull(gate.tryBegin())
    }
    @Test fun duplicateOrForeignCallbackCannotFreeSlot() {
        val gate = ApiRequestGate()
        val ticket = gate.tryBegin()!!
        assertFalse(gate.complete(ticket + 1))
        assertNull(gate.tryBegin())
        assertTrue(gate.complete(ticket))
        assertFalse(gate.complete(ticket))
    }
    @Test fun concurrentAttemptsHaveOneWinner() {
        val gate = ApiRequestGate()
        val pool = Executors.newFixedThreadPool(8)
        try {
            val results = (1..64).map { pool.submit(Callable { gate.tryBegin() }) }
            assertEquals(1, results.count { it.get(5, TimeUnit.SECONDS) != null })
        } finally { pool.shutdownNow() }
    }
    private fun client() = LoyaltyLookupResult(
        true, "Synthetic client", balanceLabel = "1000 test points",
        availableBonusAmount = 1000, externalId = "synthetic-client", loyaltyActive = true
    )
    @Test fun availableBalanceDoesNotAuthorizeRedemption() {
        val gateway = LocalLoyaltyGateway()
        gateway.loginSuccess(client())
        for (amount in listOf(-1, 0, 10, 1000, Int.MAX_VALUE)) {
            assertEquals(0, gateway.applyBonus(amount))
            assertEquals(0, gateway.bonusApplied)
        }
        assertTrue(gateway.attachedToOrder)
        assertEquals("synthetic-client", gateway.externalId)
    }
    @Test fun failedLookupCannotAttachClient() {
        val gateway = LocalLoyaltyGateway()
        gateway.loginSuccess(client())
        gateway.loginSuccess(client().copy(success = false))
        assertFalse(gateway.loggedIn)
        assertFalse(gateway.attachedToOrder)
        assertNull(gateway.externalId)
    }
    @Test fun disabledProgramCannotAttachClient() {
        val gateway = LocalLoyaltyGateway()
        gateway.loginSuccess(client().copy(loyaltyActive = false))
        assertFalse(gateway.loggedIn)
        assertEquals(0, gateway.applyBonus(100))
    }
    @Test fun orderGatewayCannotAcceptInventedBonusDiscount() {
        val gateway = LocalRetailOrderGateway()
        val product = Product("test", name = "Synthetic coffee", volume = "200ml",
            price = 123, category = "coffee", available = true, priceMinor = 12345L)
        val line = CartLine(product)
        for (discount in listOf(-1L, 0L, 50L, 12345L, Long.MAX_VALUE)) {
            val order = gateway.createOrder(listOf(line), 12345L, discount)
            assertEquals(12345L, order.amountMinor)
            assertEquals(12345L, order.grossAmountMinor)
            assertEquals(0L, order.ibonusDiscountMinor)
            assertEquals(0, order.ibonusDiscountSum)
        }
    }
    @Test fun clearingClientRemovesIdentity() {
        val gateway = LocalLoyaltyGateway()
        gateway.loginSuccess(client())
        gateway.clear()
        assertFalse(gateway.loggedIn)
        assertNull(gateway.externalId)
        assertNull(gateway.balanceLabel)
        assertEquals(0, gateway.bonusApplied)
    }
}
''')

# Only current-version references in executable entry points; older historical
# versions are not renamed. ASCII is a byte-for-byte subset of CP866.
for path in [ROOT / 'BUILD_WINDOWS_CLI.bat', *sorted(ROOT.glob('MAIN_*.bat'))]:
    rel = path.relative_to(ROOT).as_posix()
    data = path.read_bytes()
    updated = data.replace(b'0.5.126-server-managed-integrations', VERSION.encode())
    updated = updated.replace(b'0.5.125-sbp-server-config-doc-audit', VERSION.encode())
    if rel == 'BUILD_WINDOWS_CLI.bat':
        updated = updated.replace(b'v0.5.126 server-managed integrations', b'v0.5.127 API lifecycle safety')
    if updated != data:
        original(rel)
        if not updated.isascii():
            raise RuntimeError('Manual encoding review needed: ' + rel)
        if re.search(rb'^\s*chcp\b', updated, re.M | re.I):
            raise RuntimeError('Unexpected code-page command: ' + rel)
        changed[rel] = updated

verify = original('tools/verify_v0_5_126_server_managed_integrations.py')
verify = replace(verify, 'require("versionCode 126" in gradle, "versionCode must be 126")',
    'require(bool(re.search(r"versionCode\\s+(\\d+)", gradle)) and int(re.search(r"versionCode\\s+(\\d+)", gradle).group(1)) >= 126, "versionCode must be >=126")', 'forward-compatible code guard')
verify = replace(verify,
    'require("0.5.126-server-managed-integrations" in gradle, "versionName mismatch")',
    'require(bool(re.search(r"versionName\\s+\'[0-9]+\\.[0-9]+\\.[0-9]+[^\']*\'", gradle)), "versionName missing")',
    'forward-compatible name guard')
put('tools/verify_v0_5_126_server_managed_integrations.py', verify)

new_file('tools/verify_v0_5_127_api_lifecycle.py', r'''from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
ui = root / 'app/src/main/java/com/coffeeonelove/iretail/ui'
main = (ui / 'MainActivity.kt').read_text(encoding='utf-8')
gateway = (ui / 'IntegrationGateways.kt').read_text(encoding='utf-8')
checks = {}
for method, end, gate in [
    ('refreshCatalogFromIretail', 'refreshChannelConfigFromIretail', 'catalogReadGate'),
    ('refreshChannelConfigFromIretail', 'renderApiChanges', 'channelReadGate'),
    ('submitLoyaltyInput', 'setInterfaceLanguage', 'loyaltyReadGate'),
]:
    part = main.split('private fun ' + method + '(', 1)[1].split('private fun ' + end + '(', 1)[0]
    checks[method + ' separate result handler'] = 'apiResultHandler.post' in part and 'handler.post' not in part
    checks[method + ' owns ticket'] = gate + '.tryBegin()' in part and gate + '.complete(ticket)' in part
    checks[method + ' rejects destroyed owner'] = 'apiOwnerDestroyed' in part and 'isDestroyed' in part
checks['reset invalidates loyalty request'] = 'private fun resetToIdle() {\n        loyaltyReadGate.invalidate()' in main
checks['new screen cannot cancel API handler'] = 'loyaltyReadGate.invalidate()' in main and main.count('apiResultHandler.removeCallbacksAndMessages(null)') == 1
checks['both channel replies checked'] = '!channel.optBoolean("status", false)' in gateway and '!services.optBoolean("status", false)' in gateway
checks['services array mandatory'] = 'serviceResult.getJSONArray("services")' in gateway
checks['order ignores unconfirmed discount'] = 'val safeDiscountMinor = 0L' in gateway
checks['local bonus cap removed'] = 'bonusApplied = maxAmount.coerceAtMost' not in gateway
checks['UI discount is zero'] = 'return 0L' in main.split('private fun orderDiscountMinor()', 1)[1].split('private fun cartTotalMinor()', 1)[0]
checks['no new payment calls'] = all(x not in gateway for x in ['iretail/order/synchronize', 'iretail/payment-in/create', 'admin/device/create'])
for name, passed in checks.items():
    print(('[OK] ' if passed else '[FAIL] ') + name)
if not all(checks.values()):
    raise SystemExit('API lifecycle verification failed')
print('API_LIFECYCLE_STATIC_OK checks=' + str(len(checks)))
''')

# All replacements were checked before the first write.
for name, data in changed.items():
    target = ROOT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    print('PREPARED', name, hashlib.sha256(data).hexdigest())
(ROOT / '.git' / 'api-127-paths.txt').write_text('\n'.join(changed) + '\n', encoding='utf-8')
print('PREPARED_FILES', len(changed))
