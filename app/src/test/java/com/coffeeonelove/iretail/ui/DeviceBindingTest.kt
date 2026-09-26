package com.coffeeonelove.iretail.ui

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class DeviceBindingTest {
    private class MemoryStorage : BindingStorage {
        var value: JSONObject? = null
        var failWrites = false
        override fun read(): JSONObject? = value?.let { JSONObject(it.toString()) }
        override fun write(record: JSONObject) {
            if (failWrites) throw java.io.IOException("synthetic disk failure")
            value = JSONObject(record.toString())
        }
    }
    private class FakeTransport : BindingTransport {
        val calls = mutableListOf<Pair<String, Map<String, String>>>()
        var registration: JSONObject = JSONObject("""{"status":true,"result":{"device_id":41,"device_inner_id":2,"channel_id":81,"type_slug":"vending","counters":{"order_counter":0}}}""")
        var channel: JSONObject = JSONObject("""{"status":true,"result":{"id":81,"profile_id":61,"currency":{"id":643,"code":"RUB"}}}""")
        var authentication = JSONObject("""{"status":true,"result":{"access_token":"synthetic-only"}}""")
        var failRegistration = false
        var beforeRegistration: (() -> Unit)? = null
        override fun post(path: String, fields: Map<String, String>): JSONObject {
            calls += path to fields
            return when (path) {
                "user/authentication" -> authentication
                "iretail/device/get-device-info" -> JSONObject("""{"status":true,"result":{"id":41,"channel_id":81,"type":{"slug":"vending"},"code":"DO_NOT_LOG"}}""")
                "iretail/device/register" -> {
                    beforeRegistration?.invoke()
                    if (failRegistration) throw java.net.SocketTimeoutException("synthetic lost response")
                    registration
                }
                "iretail/channel/get" -> channel
                else -> error("Forbidden endpoint in test: $path")
            }
        }
    }
    private fun credentials() = BindingCredentials("synthetic-user", "synthetic-password", "SYNTHETIC_CLIENT", "synthetic-secret")
    private fun setup(): Triple<MemoryStorage, FakeTransport, DeviceBindingEngine> {
        val s = MemoryStorage(); val t = FakeTransport()
        return Triple(s, t, DeviceBindingEngine(s, t))
    }
    private fun rejects(action: () -> Unit) {
        try { action(); fail("Expected rejection") } catch (_: IllegalArgumentException) { }
        catch (_: IllegalStateException) { } catch (_: java.io.IOException) { }
    }
    @Test fun newInstallationIsNotBound() { assertFalse(BindingRecordPolicy.ready(null)) }
    @Test fun pinIsNotDeviceIdAndKeepsLeadingZero() {
        val encoded = DeviceBindingProtocol.encodeActivationPin("0001")
        assertEquals(32, encoded.length)
        assertTrue(encoded.matches(Regex("[0-9a-f]{32}")))
        assertNotEquals("0001", encoded)
        assertNotEquals(DeviceBindingProtocol.encodeActivationPin("1000"), encoded)
    }
    @Test fun invalidPinsRejectedLocally() {
        for (pin in listOf("", "12", "12345", "12a4", " 1234", "１２３４")) rejects { DeviceBindingProtocol.encodeActivationPin(pin) }
    }
    @Test fun IDsRejectZeroNegativeFractionAndBoolean() {
        for (id in listOf(null, 0, -1, true, 41.0, "1e2", "00", " 41", "2147483648")) rejects { DeviceBindingProtocol.id(id) }
    }
    @Test fun credentialToStringDoesNotLeak() {
        val value = credentials().toString()
        assertFalse(value.contains("synthetic-password")); assertFalse(value.contains("synthetic-secret"))
    }
    @Test fun authFailureDoesNotSendRegistration() {
        val (s,t,e) = setup(); t.authentication = JSONObject("""{"status":false}""")
        rejects { e.activate(credentials(), "0001", "41") }
        assertNull(s.read()); assertEquals(1, t.calls.size)
    }
    @Test fun wrongTargetDoesNotConsumePin() {
        val (s,t,e) = setup(); rejects { e.activate(credentials(), "0001", "42") }
        assertNull(s.read()); assertFalse(t.calls.any { it.first.endsWith("/register") })
    }
    @Test fun storageMustCommitBeforeRegistration() {
        val (s,t,e) = setup(); s.failWrites = true
        rejects { e.activate(credentials(), "0001", "41") }
        assertFalse(t.calls.any { it.first.endsWith("/register") })
    }
    @Test fun pendingRecordAlreadyExistsAtNetworkSend() {
        val (s,t,e) = setup()
        t.beforeRegistration = { assertEquals("REGISTERING", s.read()!!.getString("stage")) }
        e.activate(credentials(), "0001", "41")
        assertEquals("BOUND", s.read()!!.getString("stage"))
    }
    @Test fun successfulRegistrationUsesReturnedIdentifiers() {
        val (s,t,e) = setup(); e.activate(credentials(), "0001", "41")
        val identity = BindingRecordPolicy.identity(s.read()!!)
        assertEquals("41", identity.deviceId); assertEquals("81", identity.channelId)
        assertEquals("2", identity.deviceInnerId); assertEquals("vending", identity.typeSlug)
        assertFalse(BindingRecordPolicy.ready(s.read()))
        val sent = t.calls.single { it.first.endsWith("/register") }.second
        assertEquals(DeviceBindingProtocol.encodeActivationPin("0001"), sent["device_code"])
        assertFalse(sent.values.contains("0001"))
    }
    @Test fun successfulReplyPreservesCountersWithoutInventingThem() {
        val (s,_,e) = setup(); e.activate(credentials(), "0001", "41")
        assertEquals(0, s.read()!!.getJSONObject("registration").getJSONObject("result").getJSONObject("counters").getInt("order_counter"))
        assertFalse(s.read()!!.has("shift_id"))
    }
    @Test fun lostReplySurvivesNewEngineAndBlocksRetry() {
        val (s,t,e) = setup(); t.failRegistration = true
        rejects { e.activate(credentials(), "0001", "41") }
        assertEquals("REGISTERING", s.read()!!.getString("stage"))
        val calls = t.calls.size
        rejects { DeviceBindingEngine(s,t).activate(credentials(), "0002", "41") }
        assertEquals(calls, t.calls.size)
    }
    @Test fun explicitRejectionAllowsOnlyManualNewAttempt() {
        val (s,t,e) = setup(); t.registration = JSONObject("""{"status":false,"result":{"code":123}}""")
        rejects { e.activate(credentials(), "0001", "41") }
        assertEquals("REJECTED", s.read()!!.getString("stage"))
        assertTrue(BindingRecordPolicy.canBegin(s.read()))
        assertEquals(1, t.calls.count { it.first.endsWith("/register") })
    }
    @Test fun malformedSuccessIsSavedAndCannotRepeat() {
        val (s,t,e) = setup(); t.registration.getJSONObject("result").remove("device_inner_id")
        rejects { e.activate(credentials(), "0001", "41") }
        assertEquals("RESPONSE_RECEIVED", s.read()!!.getString("stage"))
        assertTrue(s.read()!!.has("registration")); assertFalse(BindingRecordPolicy.canBegin(s.read()))
    }
    @Test fun unknownStatusDoesNotCountAsDefiniteRejection() {
        val (s,t,e) = setup(); t.registration = JSONObject("""{"status":"true"}""")
        rejects { e.activate(credentials(), "0001", "41") }
        assertEquals("REGISTERING", s.read()!!.getString("stage"))
    }
    @Test fun returnedDifferentChannelCannotGrantBinding() {
        val (s,t,e) = setup(); t.registration.getJSONObject("result").put("channel_id", 82)
        rejects { e.activate(credentials(), "0001", "41") }
        assertFalse(BindingRecordPolicy.ready(s.read())); assertFalse(BindingRecordPolicy.canBegin(s.read()))
    }
    @Test fun missingConfigurationCannotOpenCustomerUI() {
        val (s,_,e) = setup(); e.activate(credentials(), "0001", "41")
        rejects { e.markReady(true,true) }; assertFalse(BindingRecordPolicy.ready(s.read()))
    }
    @Test fun configurationFailureKeepsConfirmedBinding() {
        val (s,t,e) = setup(); e.activate(credentials(), "0001", "41")
        t.channel = JSONObject("""{"status":false}""")
        rejects { e.configure() }
        assertEquals("BOUND", s.read()!!.getString("stage")); assertEquals("41", BindingRecordPolicy.identity(s.read()!!).deviceId)
    }
    @Test fun currencyMismatchNeverPretendsToBeRubles() {
        val (s,t,e) = setup(); e.activate(credentials(), "0001", "41")
        t.channel.getJSONObject("result").getJSONObject("currency").put("id",840).put("code","USD")
        rejects { e.configure() }; assertEquals("BOUND", s.read()!!.getString("stage"))
    }
    @Test fun dataBootstrapRequiresBothCatalogAndServices() {
        val (s,_,e) = setup(); e.activate(credentials(), "0001", "41"); e.configure()
        rejects { e.markReady(true,false) }; rejects { e.markReady(false,true) }
        assertFalse(BindingRecordPolicy.ready(s.read()))
        e.markReady(true,true); assertTrue(BindingRecordPolicy.ready(s.read()))
    }
    @Test fun configuredRetryNeverCallsRegisterAgain() {
        val (_,t,e) = setup(); e.activate(credentials(), "0001", "41"); e.configure(); e.configure()
        assertEquals(1, t.calls.count { it.first.endsWith("/register") })
    }
    @Test fun cacheScopeIncludesInstallationAndServerIdentity() {
        val (s,_,e) = setup(); e.activate(credentials(), "0001", "41"); e.configure()
        val a = s.read()!!; val b = JSONObject(a.toString()).put("binding_id", java.util.UUID.randomUUID().toString())
        assertNotEquals(BindingRecordPolicy.cacheScope(a), BindingRecordPolicy.cacheScope(b))
        assertTrue(BindingRecordPolicy.cacheScope(a).matches(Regex("[0-9a-f]{64}")))
    }
    @Test fun forgedLocalFlagWithoutServerResultDoesNotBind() {
        assertFalse(BindingRecordPolicy.ready(JSONObject("""{"stage":"READY","catalog_ready":true,"services_ready":true,"device_id":41,"channel_id":81}""")))
    }
    @Test fun financialReleaseIsClosedEvenWithBinding() { assertFalse(DeviceBindingProtocol.FINANCIAL_OPERATIONS_ENABLED) }
    @Test fun unboundLocalOrderCreationIsBlocked() {
        val gateway = LocalRetailOrderGateway { false }
        rejects { gateway.createOrder(emptyList(), 100) }
        assertEquals(OperationResult.ERROR, gateway.startPayment(PaymentMethod.CARD))
    }
    @Test fun workflowUsesNoFinancialOrTelemetryEndpoints() {
        val (_,t,e) = setup(); e.activate(credentials(), "0001", "41"); e.configure(); e.markReady(true,true)
        assertEquals(setOf("user/authentication","iretail/device/get-device-info","iretail/device/register","iretail/channel/get"),t.calls.map { it.first }.toSet())
    }
}
