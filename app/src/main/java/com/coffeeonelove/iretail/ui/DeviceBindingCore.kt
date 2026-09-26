package com.coffeeonelove.iretail.ui

import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

/** Protocol compatibility is deliberately separate from credentials storage. */
object DeviceBindingProtocol {
    const val BASE_URL = "https://my.i-retail.com/api/"
    const val FINANCIAL_OPERATIONS_ENABLED = false
    private const val DEVICE_SALT = "5Hu3I7H6WRFGR2EYanBs4xmPDI11gKuckA52NAMk"
    val supportedTypes = setOf("coffee_machine", "vending", "self_service_terminal", "workplace_cashier")

    fun encodeActivationPin(pin: String): String {
        require(pin.matches(Regex("[0-9]{4}"))) { "ACTIVATION_PIN_FORMAT" }
        // Exact Java TSO wire encoding, NOT password hashing or encryption for storage.
        return digest("MD5", pin + DEVICE_SALT)
    }

    fun digest(algorithm: String, value: String): String = MessageDigest.getInstance(algorithm)
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it.toInt() and 255) }

    fun id(value: Any?): String {
        val text = when (value) {
            is String -> value
            is Int, is Long -> value.toString()
            else -> ""
        }
        require(text.matches(Regex("[1-9][0-9]{0,9}")) &&
            text.toLongOrNull()?.let { it <= Int.MAX_VALUE.toLong() } == true) { "INVALID_ID" }
        return text
    }

    fun result(json: JSONObject): JSONObject {
        if (json.opt("status") != true) throw BindingFailure("API_REJECTED")
        return json.optJSONObject("result") ?: throw BindingFailure("MALFORMED_RESPONSE")
    }
}

class BindingFailure(val reason: String) : IllegalStateException(reason)

/** No generated toString: passwords never become log output accidentally. */
class BindingCredentials(val username: String, val password: String,
                         val clientId: String, val clientSecret: String) {
    fun validate() {
        require(username.isNotBlank() && username.length <= 160) { "USERNAME_REQUIRED" }
        require(password.isNotEmpty() && password.length <= 256) { "PASSWORD_REQUIRED" }
        require(clientId.isNotBlank() && clientId.length <= 128) { "CLIENT_ID_REQUIRED" }
        require(clientSecret.isNotBlank() && clientSecret.length <= 256) { "CLIENT_SECRET_REQUIRED" }
    }
    fun json(): JSONObject = JSONObject().put("username", username).put("password", password)
        .put("client_id", clientId).put("client_secret", clientSecret)
    override fun toString(): String = "BindingCredentials([REDACTED])"
    companion object {
        fun from(json: JSONObject): BindingCredentials = BindingCredentials(
            json.getString("username"), json.getString("password"),
            json.getString("client_id"), json.getString("client_secret")).also { it.validate() }
    }
}

interface BindingStorage {
    /** null means absent, not corrupt: read/decryption errors MUST throw. */
    fun read(): JSONObject?
    fun write(record: JSONObject)
}

interface BindingTransport {
    fun post(path: String, fields: Map<String, String>): JSONObject
}

data class BindingIdentity(val deviceId: String, val deviceInnerId: String,
                           val channelId: String, val typeSlug: String)

object BindingRecordPolicy {
    fun identity(record: JSONObject): BindingIdentity {
        require(record.getInt("schema") == 1) { "BINDING_SCHEMA" }
        UUID.fromString(record.getString("binding_id"))
        val r = DeviceBindingProtocol.result(record.getJSONObject("registration"))
        val identity = BindingIdentity(DeviceBindingProtocol.id(r.opt("device_id")),
            DeviceBindingProtocol.id(r.opt("device_inner_id")), DeviceBindingProtocol.id(r.opt("channel_id")),
            r.getString("type_slug"))
        require(identity.deviceId == DeviceBindingProtocol.id(record.opt("expected_device_id"))) { "DEVICE_MISMATCH" }
        require(identity.channelId == DeviceBindingProtocol.id(record.opt("expected_channel_id"))) { "CHANNEL_MISMATCH" }
        require(identity.typeSlug in DeviceBindingProtocol.supportedTypes) { "UNSUPPORTED_DEVICE_TYPE" }
        return identity
    }

    fun configuration(record: JSONObject): JSONObject {
        val identity = identity(record)
        val channel = DeviceBindingProtocol.result(record.getJSONObject("channel"))
        require(DeviceBindingProtocol.id(channel.opt("id")) == identity.channelId) { "CHANNEL_MISMATCH" }
        DeviceBindingProtocol.id(channel.opt("profile_id"))
        val currency = channel.getJSONObject("currency")
        // Existing UI formats RUB only. Never silently display another currency as rubles.
        require(DeviceBindingProtocol.id(currency.opt("id")) == "643" && currency.getString("code") == "RUB") {
            "UNSUPPORTED_CURRENCY"
        }
        return channel
    }

    fun ready(record: JSONObject?): Boolean = try {
        record != null && record.optString("stage") == "READY" &&
            record.opt("catalog_ready") == true && record.opt("services_ready") == true &&
            configuration(record).length() > 0 &&
            BindingCredentials.from(record.getJSONObject("credentials")).clientId.isNotBlank()
    } catch (_: Exception) { false }

    fun configured(record: JSONObject?): Boolean = try {
        record != null && record.optString("stage") in setOf("CONFIGURED", "READY") && configuration(record).length() > 0
    } catch (_: Exception) { false }

    fun canBegin(record: JSONObject?): Boolean = record == null || record.optString("stage") == "REJECTED"

    fun cacheScope(record: JSONObject): String {
        val identity = identity(record)
        val channel = configuration(record)
        val installation = UUID.fromString(record.getString("binding_id")).toString()
        return DeviceBindingProtocol.digest("SHA-256", DeviceBindingProtocol.BASE_URL + "|" + installation + "|" +
            identity.deviceId + "|" + identity.channelId + "|" + channel.get("profile_id"))
    }
}

/** Synchronous, testable core. Caller serializes it across Activity recreation. */
class DeviceBindingEngine(private val storage: BindingStorage, private val transport: BindingTransport) {
    fun authenticate(credentials: BindingCredentials): String {
        credentials.validate()
        val r = DeviceBindingProtocol.result(transport.post("user/authentication", mapOf(
            "username" to credentials.username, "password" to credentials.password,
            "client_id" to credentials.clientId, "client_secret" to credentials.clientSecret)))
        return r.optString("access_token", "").takeIf { it.isNotBlank() && it != "null" }
            ?: throw BindingFailure("TOKEN_MISSING")
    }

    private fun fields(c: BindingCredentials, token: String) = mapOf("client_id" to c.clientId,
        "client_secret" to c.clientSecret, "access_token" to token)

    fun activate(credentials: BindingCredentials, pin: String, expectedDeviceId: String) {
        if (!BindingRecordPolicy.canBegin(storage.read())) throw BindingFailure("ACTIVATION_REPEAT_BLOCKED")
        val expected = DeviceBindingProtocol.id(expectedDeviceId)
        val encoded = DeviceBindingProtocol.encodeActivationPin(pin)
        val token = authenticate(credentials)
        val common = fields(credentials, token)
        // Read-only check of the explicitly entered target before consuming a one-time PIN.
        val device = DeviceBindingProtocol.result(transport.post("iretail/device/get-device-info",
            common + ("device_id" to expected)))
        require(DeviceBindingProtocol.id(device.opt("id")) == expected) { "DEVICE_MISMATCH" }
        val channelId = DeviceBindingProtocol.id(device.opt("channel_id"))
        val type = device.getJSONObject("type").getString("slug")
        require(type in DeviceBindingProtocol.supportedTypes) { "UNSUPPORTED_DEVICE_TYPE" }
        val record = JSONObject().put("schema", 1).put("stage", "REGISTERING")
            .put("binding_id", UUID.randomUUID().toString()).put("submitted_at", System.currentTimeMillis())
            .put("expected_device_id", expected).put("expected_channel_id", channelId)
            .put("credentials", credentials.json()).put("device_code_encoded", encoded)
        // Durable BEFORE send. An exception, HTTP error, crash or lost reply blocks automatic retry.
        storage.write(record)
        val response = transport.post("iretail/device/register", common + ("device_code" to encoded))
        if (response.opt("status") == false) {
            storage.write(record.put("stage", "REJECTED"))
            throw BindingFailure("ACTIVATION_REJECTED")
        }
        if (response.opt("status") != true) throw BindingFailure("ACTIVATION_OUTCOME_UNKNOWN")
        // Save even an unexpected successful response before parsing, never lose proof or resend it.
        record.put("registration", response).put("stage", "RESPONSE_RECEIVED")
        storage.write(record)
        val identity = BindingRecordPolicy.identity(record)
        require(identity.typeSlug == type) { "DEVICE_TYPE_CHANGED" }
        storage.write(record.put("stage", "BOUND"))
    }

    fun configure() {
        val record = storage.read() ?: throw BindingFailure("UNBOUND")
        if (record.optString("stage") !in setOf("BOUND", "CONFIGURED", "READY"))
            throw BindingFailure("ACTIVATION_RESULT_REQUIRES_REVIEW")
        val identity = BindingRecordPolicy.identity(record)
        val credentials = BindingCredentials.from(record.getJSONObject("credentials"))
        val token = authenticate(credentials)
        val channel = transport.post("iretail/channel/get", fields(credentials, token) + ("channel_id" to identity.channelId))
        val candidate = JSONObject(record.toString()).put("channel", channel)
        BindingRecordPolicy.configuration(candidate)
        // A network failure does not overwrite the old record or unbind the installation.
        storage.write(candidate.put("stage", "CONFIGURED").put("catalog_ready", false).put("services_ready", false))
    }

    fun markReady(catalogReady: Boolean, servicesReady: Boolean) {
        val record = storage.read() ?: throw BindingFailure("UNBOUND")
        require(record.optString("stage") == "CONFIGURED") { "NOT_CONFIGURED" }
        BindingRecordPolicy.configuration(record)
        require(catalogReady && servicesReady) { "BOOTSTRAP_INCOMPLETE" }
        storage.write(record.put("catalog_ready", true).put("services_ready", true).put("stage", "READY"))
    }
}
