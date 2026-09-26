package com.coffeeonelove.iretail.ui

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.provider.Settings
import android.text.InputFilter
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject

/** Native Android 6 onboarding. No demo bypass, hard-coded target, or PIN in Intent. */
class DeviceBindingActivity : Activity() {
    private lateinit var body: LinearLayout
    private lateinit var form: LinearLayout
    private lateinit var status: TextView
    private lateinit var identity: TextView
    private lateinit var login: EditText
    private lateinit var password: EditText
    private lateinit var clientId: EditText
    private lateinit var clientSecret: EditText
    private lateinit var deviceId: EditText
    private lateinit var pin: EditText
    private lateinit var activate: Button
    private lateinit var retry: Button
    private lateinit var enter: Button
    private val listener: () -> Unit = { refresh() }
    private val green = 0xFF5CBC4D.toInt()
    private val ink = 0xFF332E2D.toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        val frame = FrameLayout(this).apply { setBackgroundColor(0xFFF1F5FF.toInt()) }
        val scroll = ScrollView(this).apply { isFillViewport = true }
        body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(26), dp(22), dp(26), dp(24))
            setBackgroundColor(Color.WHITE)
        }
        scroll.addView(body, FrameLayout.LayoutParams(-1, -2))
        val width = minOf(resources.displayMetrics.widthPixels, dp(700))
        frame.addView(scroll, FrameLayout.LayoutParams(width, -1, Gravity.CENTER_HORIZONTAL))
        setContentView(frame)
        text("i-Retail · Coffee One Love", 16f, green)
        text("Привязка устройства", 28f, ink, true)
        text("1. Доступ   →   2. Активация   →   3. Настройки", 14f, 0xFF6D8297.toInt())
        status = text("Проверяем локальное состояние…", 17f, ink)
        status.contentDescription = "binding_status"
        identity = text("", 15f, ink)
        form = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        body.addView(form)
        login = field("Логин личного кабинета", false)
        password = field("Пароль личного кабинета", true)
        deviceId = field("ID устройства в ЛК (не код активации)", false, true, 10)
        pin = field("Новый PIN активации — 4 цифры", true, true, 4)
        clientId = field("client_id приложения API", false, false, 128).apply { setText("IRETAIL_TERMINAL") }
        clientSecret = field("client_secret приложения API", true)
        text("Реквизиты берутся из отдельного личного файла доступов. Они не входят в APK. Код активации не является ID устройства.", 14f, 0xFF6D8297.toInt())
        activate = button("Привязать устройство") { confirmActivation() }
        retry = button("Повторить загрузку настроек") { DeviceBindingCoordinator.resumeConfiguration(this) }
        enter = button("Открыть витрину") {
            if (DeviceBindingStore.get(this).isReady()) {
                startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP))
                finish()
            }
        }
        button("Обновить локальный статус") { refresh() }
        button("Настройки сети", secondary = true) {
            ForegroundKeeperService.stop(this)
            try { startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS)) }
            catch (_: Exception) { status.text = "Откройте настройки сети Android через системное меню." }
        }
        text("До подтверждённой привязки витрина и операции закрыты. В версии 0.5.128 платежи, списание бонусов и приготовление не запускаются.", 14f, 0xFF6D8297.toInt())
        refresh()
    }

    override fun onStart() {
        super.onStart()
        MainUiVisibility.bindingStarted = true
        DeviceBindingCoordinator.listen(listener)
        refresh()
    }
    override fun onResume() {
        super.onResume()
        MainUiVisibility.bindingStarted = true
        if (MachineModeStore.load(this).standalone) ForegroundKeeperService.ensureRunning(this)
        refresh()
    }
    override fun onStop() {
        DeviceBindingCoordinator.unlisten(listener)
        MainUiVisibility.bindingStarted = false
        super.onStop()
    }
    @Deprecated("Onboarding cannot navigate back into an unbound customer session")
    override fun onBackPressed() { status.text = "Сначала завершите привязку. Для восстановления связи доступны настройки сети." }

    private fun confirmActivation() {
        if (DeviceBindingCoordinator.isBusy()) return
        val credentials = BindingCredentials(login.text.toString().trim(), password.text.toString(),
            clientId.text.toString().trim(), clientSecret.text.toString().trim())
        val target = deviceId.text.toString().trim()
        val code = pin.text.toString()
        try {
            credentials.validate()
            DeviceBindingProtocol.id(target)
            DeviceBindingProtocol.encodeActivationPin(code)
        } catch (_: Exception) {
            status.text = "Заполните все реквизиты API, положительный ID устройства и четырёхзначный PIN. Начальный ноль кода сохраняется."
            return
        }
        AlertDialog.Builder(this).setTitle("Подтвердить привязку")
            .setMessage("Устройство в ЛК: $target.\nБудут проверены доступ и принадлежность точки, затем отправлен один запрос активации. При потере ответа повтор запрещён. Платежей и приготовления не будет.")
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Привязать") { _, _ ->
                pin.text.clear()
                password.text.clear()
                clientSecret.text.clear()
                DeviceBindingCoordinator.begin(this, credentials, code, target)
                refresh()
            }.show()
    }

    private fun refresh() {
        if (isDestroyed || isFinishing || !::status.isInitialized) return
        val storage = DeviceBindingStore.get(this)
        val stage = storage.stage()
        val busy = DeviceBindingCoordinator.isBusy()
        val ready = storage.isReady()
        val blockedOld = DeviceBindingStore.hasUnresolvedLegacyOperation(this)
        form.visibility = if (stage in setOf("UNBOUND", "REJECTED") && !busy) View.VISIBLE else View.GONE
        activate.visibility = form.visibility
        activate.isEnabled = !busy && !blockedOld
        retry.visibility = if (stage in setOf("BOUND", "CONFIGURED")) View.VISIBLE else View.GONE
        retry.isEnabled = !busy && !blockedOld
        enter.visibility = if (ready) View.VISIBLE else View.GONE
        identity.text = safeIdentity(runCatching { storage.read() }.getOrNull())
        val stateText = when (stage) {
            "UNBOUND" -> "Устройство ещё не привязано."
            "REJECTED" -> "Активация отклонена сервером."
            "REGISTERING", "RESPONSE_RECEIVED" -> if (busy) "Активация выполняется…" else
                "Результат активации требует проверки в ЛК. Повтор не отправляется. Не удаляйте данные приложения."
            "BOUND", "CONFIGURED" -> "Привязка сохранена. Настройки ещё не загружены полностью."
            "READY" -> "Привязка подтверждена. Витрина готова к проверке."
            else -> "Хранилище привязки недоступно. Операции заблокированы; исходные данные сохранены."
        }
        status.text = "$stateText\n${DeviceBindingCoordinator.message}" +
            if (blockedOld) "\nОбнаружена незавершённая прежняя операция. Сначала необходима её проверка." else ""
        android.util.Log.i("IretailBinding", "STATE stage=$stage busy=$busy ready=$ready legacyUnresolved=$blockedOld")
    }

    private fun safeIdentity(record: JSONObject?): String = try {
        if (record == null) "" else {
            val item = BindingRecordPolicy.identity(record)
            val channel = if (BindingRecordPolicy.configured(record)) BindingRecordPolicy.configuration(record) else null
            "Устройство: ${item.deviceId} · канал: ${item.channelId} · тип: ${item.typeSlug}" +
                (channel?.let { "\nПрофиль: ${it.get("profile_id")} · валюта: ${it.getJSONObject("currency").getString("code")}" } ?: "")
        }
    } catch (_: Exception) { "" }

    private fun text(value: String, size: Float, color: Int, bold: Boolean = false): TextView {
        val v = TextView(this).apply {
            text = value; textSize = size; setTextColor(color)
            if (bold) setTypeface(Typeface.DEFAULT, Typeface.BOLD)
            setPadding(0, dp(5), 0, dp(9))
        }
        body.addView(v, LinearLayout.LayoutParams(-1, -2))
        return v
    }
    private fun field(hintText: String, secret: Boolean, numeric: Boolean = false, limit: Int = 256): EditText {
        val label = TextView(this).apply { text = hintText; textSize = 14f; setTextColor(ink); setPadding(0,dp(5),0,0) }
        form.addView(label)
        val v = EditText(this).apply {
            hint = hintText; textSize = 17f; setSingleLine(true)
            inputType = if (numeric) InputType.TYPE_CLASS_NUMBER or (if (secret) InputType.TYPE_NUMBER_VARIATION_PASSWORD else 0)
                else InputType.TYPE_CLASS_TEXT or (if (secret) InputType.TYPE_TEXT_VARIATION_PASSWORD else InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS)
            filters = arrayOf(InputFilter.LengthFilter(limit))
            isSaveEnabled = false
            if (android.os.Build.VERSION.SDK_INT >= 26) importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            setTextColor(ink)
        }
        form.addView(v, LinearLayout.LayoutParams(-1, dp(52)))
        return v
    }
    private fun button(title: String, secondary: Boolean = false, action: () -> Unit): Button {
        val v = Button(this).apply {
            text = title; textSize = 16f; isAllCaps = false
            setTextColor(if (secondary) ink else Color.WHITE)
            background = GradientDrawable().apply { setColor(if (secondary) 0xFFEFF3F6.toInt() else green); cornerRadius = dp(9).toFloat() }
            setOnClickListener { action() }
        }
        body.addView(v, LinearLayout.LayoutParams(-1, dp(52)).apply { topMargin = dp(10) })
        return v
    }
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}

object DeviceBindingAccess {
    @Volatile private var verifiedReady = false
    internal fun publish(record: JSONObject?) { verifiedReady = BindingRecordPolicy.ready(record) }
    @JvmStatic fun isReady(): Boolean = verifiedReady
    @JvmStatic fun financialAllowed(): Boolean = verifiedReady && DeviceBindingProtocol.FINANCIAL_OPERATIONS_ENABLED
}
