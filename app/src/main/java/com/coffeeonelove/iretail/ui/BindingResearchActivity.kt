package com.coffeeonelove.iretail.ui

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URL
import java.net.URLEncoder
import java.util.LinkedHashSet
import java.util.zip.ZipInputStream
import javax.net.ssl.HttpsURLConnection

class BindingResearchActivity : Activity() {
    private lateinit var label: TextView
    private val main = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        label = TextView(this).apply {
            text = "Исследование привязки i-Retail…"
            textSize = 22f
            setTextColor(Color.DKGRAY)
            setPadding(32, 48, 32, 32)
        }
        setContentView(label)
        val extras = intent.getStringExtra("probe_ids").orEmpty()
        Thread {
            val report = BindingResearchRunner(applicationContext).run(extras)
            val outDir = File(getExternalFilesDir(null), "binding_research").apply { mkdirs() }
            val out = File(outDir, "latest.json")
            out.writeText(report.toString(2), Charsets.UTF_8)
            android.util.Log.i("IretailBindingResearch", "DONE result=" + report.optString("result") + " path=" + out.absolutePath)
            main.post {
                label.text = "Исследование завершено: " + report.optString("result") + "\nОтчёт подготовлен для сценария Windows."
            }
        }.start()
    }
}

private class BindingResearchRunner(private val context: android.content.Context) {
    private val allowedJson = setOf(
        "user/authentication",
        "iretail/device/get-device-info",
        "iretail/device/get-by-channel-id",
        "iretail/channel/get",
        "iretail/channel/get-available-services-in",
        "catalog/check-exists",
        "iretail/channel/get-time-update"
    )

    fun run(extraIds: String): JSONObject {
        val report = JSONObject()
            .put("schema", "iretail.binding-research.v1")
            .put("generated_at_ms", System.currentTimeMillis())
            .put("mutating_requests_sent", false)
            .put("registration_requested", false)
            .put("ping_requested", false)
            .put("payment_requested", false)
            .put("raw_api_bodies_saved", false)

        val record = try { DeviceBindingStore.get(context).read() } catch (_: Exception) { null }
        if (record == null) return report.put("result", "NO_SAVED_BINDING_RECORD")

        report.put("local", summarizeLocal(record))
        val credentials = try { BindingCredentials.from(record.getJSONObject("credentials")) }
        catch (_: Exception) { return report.put("result", "NO_SAVED_CREDENTIALS") }

        val token = try { authenticate(credentials) }
        catch (e: Exception) {
            return report.put("result", safeReason(e)).put("auth", JSONObject().put("success", false))
        }
        report.put("auth", JSONObject().put("success", true))

        val common = mapOf(
            "client_id" to credentials.clientId,
            "client_secret" to credentials.clientSecret,
            "access_token" to token
        )

        val ids = LinkedHashSet<String>()
        fun addId(v: Any?) {
            val s = when (v) { is Number -> v.toLong().toString(); is String -> v.trim(); else -> "" }
            if (s.matches(Regex("[1-9][0-9]{0,9}"))) ids.add(s)
        }
        addId(record.opt("expected_device_id"))
        addId(record.opt("expected_channel_id"))
        extraIds.split(',',';',' ').forEach { addId(it) }

        val devices = JSONArray()
        val channels = JSONArray()
        val discoveredChannels = LinkedHashSet<String>()
        val profileByChannel = LinkedHashMap<String,String>()

        for (id in ids) {
            val d = probeJson("iretail/device/get-device-info", common + ("device_id" to id), "device", id)
            devices.put(d)
            d.optJSONObject("summary")?.optString("channel_id")?.takeIf { it.matches(Regex("[1-9][0-9]{0,9}")) }?.let { discoveredChannels.add(it) }

            val c = probeJson("iretail/channel/get", common + ("channel_id" to id), "channel", id)
            channels.put(c)
            val s = c.optJSONObject("summary")
            if (s != null && c.optBoolean("api_success", false)) {
                discoveredChannels.add(id)
                val p = s.optString("profile_id")
                if (p.matches(Regex("[1-9][0-9]{0,9}"))) profileByChannel[id] = p
            }
        }
        report.put("device_probes", devices)
        report.put("channel_probes", channels)

        val channelDetails = JSONArray()
        for (channelId in discoveredChannels) {
            val obj = JSONObject().put("channel_id", channelId)
            obj.put("devices", probeJson("iretail/device/get-by-channel-id", common + ("channel_id" to channelId), "device_list", channelId))
            obj.put("services", probeJson("iretail/channel/get-available-services-in", common + ("channel_id" to channelId), "services", channelId))
            obj.put("time_update", probeJson("iretail/channel/get-time-update", common + ("channel_id" to channelId), "scalar", channelId))
            val profileId = profileByChannel[channelId]
            if (profileId != null) {
                obj.put("catalog_exists", probeJson("catalog/check-exists",
                    common + mapOf("channel_id" to channelId, "profile_id" to profileId), "scalar", channelId))
            }
            obj.put("catalog", probeCatalog(common, channelId))
            channelDetails.put(obj)
        }
        report.put("discovered_channels", channelDetails)
        return report.put("result", "READ_ONLY_RESEARCH_COMPLETE")
    }

    private fun summarizeLocal(record: JSONObject): JSONObject {
        val out = JSONObject()
            .put("stage", record.optString("stage", ""))
            .put("expected_device_id", safeId(record.opt("expected_device_id")))
            .put("expected_channel_id", safeId(record.opt("expected_channel_id")))
            .put("has_registration", record.optJSONObject("registration") != null)
            .put("has_channel", record.optJSONObject("channel") != null)
            .put("catalog_ready", record.optBoolean("catalog_ready", false))
            .put("services_ready", record.optBoolean("services_ready", false))
        try {
            val id = BindingRecordPolicy.identity(record)
            out.put("identity", JSONObject()
                .put("device_id", id.deviceId)
                .put("device_inner_id", id.deviceInnerId)
                .put("channel_id", id.channelId)
                .put("type_slug", id.typeSlug))
        } catch (_: Exception) {}
        return out
    }

    private fun authenticate(c: BindingCredentials): String {
        val json = postJson("user/authentication", mapOf(
            "username" to c.username, "password" to c.password,
            "client_id" to c.clientId, "client_secret" to c.clientSecret))
        val result = DeviceBindingProtocol.result(json)
        return result.optString("access_token").takeIf { it.isNotBlank() && it != "null" }
            ?: throw BindingFailure("TOKEN_MISSING")
    }

    private fun probeJson(path: String, fields: Map<String,String>, kind: String, inputId: String): JSONObject {
        val out = JSONObject().put("path", path).put("input_id", inputId)
        return try {
            val response = postJson(path, fields)
            out.put("http_success", true)
                .put("api_success", response.opt("status") == true)
                .put("summary", summarizeResult(response.opt("result"), kind))
        } catch (e: Exception) {
            out.put("http_success", false).put("api_success", false).put("reason", safeReason(e))
        }
    }

    private fun summarizeResult(value: Any?, kind: String): Any {
        if (value == null || value === JSONObject.NULL) return JSONObject().put("kind", "null")
        if (value is JSONArray) {
            val ids = JSONArray()
            for (i in 0 until minOf(value.length(), 50)) {
                val o = value.optJSONObject(i) ?: continue
                safeId(o.opt("id")).takeIf { it.isNotBlank() }?.let { ids.put(it) }
            }
            return JSONObject().put("kind", "array").put("count", value.length()).put("ids", ids)
        }
        if (value !is JSONObject) return JSONObject().put("kind", "scalar").put("value_type", value.javaClass.simpleName)
        return when (kind) {
            "device" -> JSONObject()
                .put("kind", "device")
                .put("id", safeId(value.opt("id")))
                .put("channel_id", safeId(value.opt("channel_id")))
                .put("device_inner_id", safeId(value.opt("device_inner_id")))
                .put("type_slug", value.optJSONObject("type")?.optString("slug").orEmpty())
                .put("status_slug", value.optJSONObject("status")?.optString("slug").orEmpty())
            "channel" -> JSONObject()
                .put("kind", "channel")
                .put("id", safeId(value.opt("id")))
                .put("profile_id", safeId(value.opt("profile_id")))
                .put("enable", value.optBooleanNullable("enable"))
                .put("related_enabled", value.optJSONObject("related")?.optBooleanNullable("enabled"))
                .put("currency_id", safeId(value.optJSONObject("currency")?.opt("id")))
                .put("currency_code", value.optJSONObject("currency")?.optString("code").orEmpty())
            "services" -> {
                val arr = value.optJSONArray("services") ?: JSONArray()
                val services = JSONArray()
                for (i in 0 until minOf(arr.length(), 100)) {
                    val s = arr.optJSONObject(i) ?: continue
                    services.put(JSONObject()
                        .put("id", safeId(s.opt("id")))
                        .put("slug", s.optString("slug"))
                        .put("enabled", s.optJSONObject("settings")?.optBooleanNullable("enable")))
                }
                JSONObject().put("kind", "services")
                    .put("count", arr.length())
                    .put("user_verified", value.optBooleanNullable("user_verified"))
                    .put("shop_verified", value.optBooleanNullable("shop_verified"))
                    .put("services", services)
            }
            "device_list" -> {
                val arr = value.optJSONArray("devices") ?: value.optJSONArray("items") ?: JSONArray()
                val items = JSONArray()
                for (i in 0 until minOf(arr.length(), 100)) {
                    val d = arr.optJSONObject(i) ?: continue
                    items.put(JSONObject().put("id", safeId(d.opt("id")))
                        .put("channel_id", safeId(d.opt("channel_id")))
                        .put("type_slug", d.optJSONObject("type")?.optString("slug").orEmpty()))
                }
                JSONObject().put("kind", "device_list").put("count", arr.length()).put("items", items)
            }
            else -> JSONObject().put("kind", kind).put("object_keys", value.keys().asSequence().filter {
                it in setOf("id","profile_id","channel_id","enable","enabled","count","timestamp","time")
            }.toList().sorted().joinToString(","))
        }
    }

    private fun probeCatalog(common: Map<String,String>, channelId: String): JSONObject {
        val out = JSONObject().put("path", "iretail/catalog/download-actual-zip").put("channel_id", channelId)
        return try {
            val bytes = postBytes("iretail/catalog/download-actual-zip", common + ("channel_id" to channelId), 25_000_000)
            out.put("http_success", true).put("bytes", bytes.size).put("zip", summarizeZip(bytes))
        } catch (e: Exception) {
            out.put("http_success", false).put("reason", safeReason(e))
        }
    }

    private fun summarizeZip(bytes: ByteArray): JSONObject {
        var categoriesPresent = false
        var offerFiles = 0
        var offers = 0
        var available = 0
        val offerIds = JSONArray()
        ZipInputStream(bytes.inputStream()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = entry.name.substringAfterLast('/')
                if (name == "categories.json") categoriesPresent = true
                if (name.startsWith("offers_") && name.endsWith(".json")) {
                    offerFiles++
                    val text = readEntry(zip, 10_000_000)
                    val root = JSONObject(text)
                    val arr = root.optJSONArray("offers") ?: JSONArray()
                    offers += arr.length()
                    for (i in 0 until arr.length()) {
                        val o = arr.optJSONObject(i) ?: continue
                        if (o.optBoolean("available", false)) available++
                        if (offerIds.length() < 50) safeId(o.opt("id")).takeIf { it.isNotBlank() }?.let { offerIds.put(it) }
                    }
                }
                zip.closeEntry()
            }
        }
        return JSONObject().put("categories_json", categoriesPresent)
            .put("offer_files", offerFiles).put("offers", offers)
            .put("available_offers", available).put("offer_ids", offerIds)
    }

    private fun readEntry(input: java.io.InputStream, limit: Int): String {
        val out = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        while (true) {
            val n = input.read(chunk)
            if (n < 0) break
            if (out.size() + n > limit) throw BindingFailure("ZIP_ENTRY_TOO_LARGE")
            out.write(chunk, 0, n)
        }
        return out.toString("UTF-8")
    }

    private fun postJson(path: String, fields: Map<String,String>): JSONObject {
        require(path in allowedJson) { "ENDPOINT_NOT_ALLOWED" }
        return JSONObject(String(postBytes(path, fields, 1_000_000), Charsets.UTF_8))
    }

    private fun postBytes(path: String, fields: Map<String,String>, limit: Int): ByteArray {
        require(path in allowedJson || path == "iretail/catalog/download-actual-zip") { "ENDPOINT_NOT_ALLOWED" }
        val url = URL(DeviceBindingProtocol.BASE_URL + path)
        val connection = url.openConnection() as HttpsURLConnection
        IretailTlsCompat.applyIfNeeded(context, url, connection)
        val payload = fields.entries.joinToString("&") {
            URLEncoder.encode(it.key, "UTF-8") + "=" + URLEncoder.encode(it.value, "UTF-8")
        }.toByteArray(Charsets.UTF_8)
        try {
            connection.instanceFollowRedirects = false
            connection.requestMethod = "POST"
            connection.connectTimeout = 15000
            connection.readTimeout = 30000
            connection.doOutput = true
            connection.setFixedLengthStreamingMode(payload.size)
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
            connection.setRequestProperty("Accept", "*/*")
            connection.outputStream.use { it.write(payload) }
            val status = connection.responseCode
            if (status !in 200..299) throw BindingFailure("HTTP_" + status)
            return connection.inputStream.use { input ->
                val out = ByteArrayOutputStream()
                val chunk = ByteArray(8192)
                while (true) {
                    val n = input.read(chunk)
                    if (n < 0) break
                    if (out.size() + n > limit) throw BindingFailure("API_RESPONSE_TOO_LARGE")
                    out.write(chunk, 0, n)
                }
                out.toByteArray()
            }
        } finally {
            payload.fill(0)
            connection.disconnect()
        }
    }

    private fun safeReason(e: Exception): String = when (e) {
        is BindingFailure -> e.reason.takeIf { it.matches(Regex("[A-Z0-9_]{2,80}|HTTP_[0-9]{3}")) } ?: "BINDING_FAILURE"
        is java.net.UnknownHostException -> "DNS"
        is java.net.SocketTimeoutException -> "TIMEOUT"
        is javax.net.ssl.SSLException -> "TLS"
        is org.json.JSONException -> "JSON"
        else -> "REQUEST_FAILED"
    }

    private fun safeId(v: Any?): String {
        val s = when (v) { is Number -> v.toLong().toString(); is String -> v.trim(); else -> "" }
        return if (s.matches(Regex("[0-9]{1,10}"))) s else ""
    }

    private fun JSONObject.optBooleanNullable(key: String): Any {
        if (!has(key) || isNull(key)) return JSONObject.NULL
        return when (val v = opt(key)) {
            is Boolean -> v
            is Number -> v.toInt() != 0
            is String -> when (v.trim().lowercase()) {
                "true","1","yes","on" -> true
                "false","0","no","off" -> false
                else -> JSONObject.NULL
            }
            else -> JSONObject.NULL
        }
    }
}
