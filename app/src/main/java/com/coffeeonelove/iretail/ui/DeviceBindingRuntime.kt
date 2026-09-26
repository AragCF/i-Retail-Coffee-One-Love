package com.coffeeonelove.iretail.ui

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** This client has no payment, order, shift, telemetry or brewing endpoint. */
class DeviceBindingHttp(context: Context) : BindingTransport {
    private val app = context.applicationContext
    override fun post(path: String, fields: Map<String, String>): JSONObject {
        require(path in setOf("user/authentication", "iretail/device/get-device-info",
            "iretail/device/register", "iretail/channel/get")) { "ENDPOINT_NOT_ALLOWED" }
        val url = URL(DeviceBindingProtocol.BASE_URL + path)
        val connection = url.openConnection() as javax.net.ssl.HttpsURLConnection
        IretailTlsCompat.applyIfNeeded(app, url, connection)
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
            connection.setRequestProperty("Accept", "application/json")
            connection.outputStream.use { it.write(payload) }
            val status = connection.responseCode
            if (status !in 200..299) throw BindingFailure("HTTP_$status")
            val bytes = connection.inputStream.use { input ->
                val result = java.io.ByteArrayOutputStream()
                val chunk = ByteArray(8192)
                while (true) {
                    val n = input.read(chunk)
                    if (n < 0) break
                    if (result.size() + n > 1_000_000) throw BindingFailure("API_RESPONSE_TOO_LARGE")
                    result.write(chunk, 0, n)
                }
                result.toByteArray()
            }
            return JSONObject(String(bytes, Charsets.UTF_8))
        } finally {
            payload.fill(0)
            connection.disconnect()
        }
    }
}

/** Process-wide owner: Activity recreation never submits a second registration. */
object DeviceBindingCoordinator {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArraySet<() -> Unit>()
    private val busy = AtomicBoolean(false)
    @Volatile var message = "Для начала работы привяжите устройство к личному кабинету."
        private set
    fun isBusy(): Boolean = busy.get()
    fun listen(listener: () -> Unit) { listeners.add(listener) }
    fun unlisten(listener: () -> Unit) { listeners.remove(listener) }
    private fun update(text: String) {
        message = text
        main.post { listeners.forEach { it() } }
    }
    fun begin(context: Context, credentials: BindingCredentials, pin: String, deviceId: String) {
        val app = context.applicationContext
        launch(app) { engine ->
            update("Проверяем доступ и выбранное устройство. Затем выполняется одна попытка активации…")
            engine.activate(credentials, pin, deviceId)
            update("Регистрация подтверждена. Получаем настройки этой точки…")
            engine.configure()
        }
    }
    fun resumeConfiguration(context: Context) {
        launch(context.applicationContext) { engine ->
            update("Повторяем только чтение настроек. Код активации повторно не отправляется.")
            engine.configure()
        }
    }
    private fun launch(app: Context, work: (DeviceBindingEngine) -> Unit) {
        if (!busy.compareAndSet(false, true)) return
        update("Подготовка…")
        executor.execute {
            val storage = DeviceBindingStore.get(app)
            val engine = DeviceBindingEngine(storage, DeviceBindingHttp(app))
            try {
                if (DeviceBindingStore.hasUnresolvedLegacyOperation(app)) throw BindingFailure("UNRESOLVED_PREVIOUS_OPERATION")
                work(engine)
                val repository = IretailContentRepository(app)
                update("Привязка сохранена. Загружаем каталог и службы канала…")
                repository.refreshProductsAsync { catalog ->
                    if (!catalog.success) finish("Привязка сохранена, но каталог ещё не получен. Проверьте ассортимент точки и повторите загрузку.")
                    else repository.refreshChannelConfigAsync { services ->
                        try {
                            if (!services.success) throw BindingFailure("CHANNEL_CONFIGURATION_UNAVAILABLE")
                            engine.markReady(true, true)
                            finish("Устройство привязано. Каталог и настройки получены. Финансовые операции в этом выпуске отключены.")
                        } catch (e: Exception) { finish(safeMessage(e, storage.stage())) }
                    }
                }
            } catch (e: Exception) { finish(safeMessage(e, storage.stage())) }
        }
    }
    private fun finish(text: String) {
        busy.set(false)
        update(text)
    }
    private fun safeMessage(e: Exception, stage: String): String {
        if (stage == "REGISTERING" || stage == "RESPONSE_RECEIVED") return "Результат активации требует проверки. Автоматический повтор запрещён. Не очищайте данные приложения; сверьте состояние устройства в ЛК."
        if (stage == "STORAGE_LOCKED") return "Хранилище привязки недоступно. Продажи заблокированы; данные не удалены."
        val reason = (e as? BindingFailure)?.reason ?: when (e) {
            is java.net.UnknownHostException -> "DNS"
            is java.net.SocketTimeoutException -> "TIMEOUT"
            is javax.net.ssl.SSLException -> "TLS"
            is IllegalArgumentException -> "INVALID_CONFIGURATION"
            else -> "REQUEST_FAILED"
        }
        return when (reason) {
            "UNRESOLVED_PREVIOUS_OPERATION" -> "Сохранена незавершённая операция прежней установки. Привязка заблокирована до её проверки. Журналы и маркеры сохранены."
            "ACTIVATION_REJECTED" -> "Сервер отклонил активацию. Проверьте новый PIN и выбранное устройство. Автоповтора нет."
            "API_REJECTED" -> "Сервер отклонил запрос. Проверьте реквизиты и права на точку."
            else -> "Не удалось завершить настройку ($reason). Сохранённая привязка не удаляется."
        }
    }
}
