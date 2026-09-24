package com.coffeeonelove.iretail.ui

import android.content.Context
import java.security.MessageDigest

class SbpSessionStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(record: SbpSessionRecord) {
        prefs.edit()
            .putString(KEY_SESSION_ID, record.sessionId)
            .putString(KEY_STATE, record.state.name)
            .putLong(KEY_AMOUNT_MINOR, record.amountMinor)
            .putString(KEY_QR_ID, record.qrId)
            .putString(KEY_QR_PAYLOAD, record.qrPayload)
            .putInt(KEY_GENERATION, record.generation)
            .putLong(KEY_CREATED_AT, record.createdAtMs)
            .putLong(KEY_UPDATED_AT, record.updatedAtMs)
            .putBoolean(KEY_REAL_PAYMENT_SENT, record.realPaymentSent)
            .apply()
    }

    fun load(): SbpSessionRecord? {
        val sessionId = prefs.getString(KEY_SESSION_ID, null)?.takeIf { it.isNotBlank() } ?: return null
        val state = runCatching {
            SbpPaymentState.valueOf(prefs.getString(KEY_STATE, SbpPaymentState.ERROR.name) ?: SbpPaymentState.ERROR.name)
        }.getOrDefault(SbpPaymentState.ERROR)

        return SbpSessionRecord(
            sessionId = sessionId,
            state = state,
            amountMinor = prefs.getLong(KEY_AMOUNT_MINOR, 0L),
            qrId = prefs.getString(KEY_QR_ID, null),
            qrPayload = prefs.getString(KEY_QR_PAYLOAD, null),
            generation = prefs.getInt(KEY_GENERATION, 0),
            createdAtMs = prefs.getLong(KEY_CREATED_AT, 0L),
            updatedAtMs = prefs.getLong(KEY_UPDATED_AT, 0L),
            realPaymentSent = prefs.getBoolean(KEY_REAL_PAYMENT_SENT, false)
        )
    }

    fun loadActive(): SbpSessionRecord? = load()?.takeIf { it.isActive }

    fun clear() {
        prefs.edit().clear().apply()
    }

    fun safeSummary(record: SbpSessionRecord): SbpSafeSummary =
        SbpSafeSummary(
            sessionId = record.sessionId,
            state = record.state,
            amountMinor = record.amountMinor,
            generation = record.generation,
            qrIdHash = digest(record.qrId),
            qrPayloadHash = digest(record.qrPayload),
            qrPayloadLength = record.qrPayload?.length ?: 0,
            realPaymentSent = record.realPaymentSent
        )

    private fun digest(value: String?): String {
        if (value.isNullOrBlank()) return "-"
        val bytes = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        return bytes.take(8).joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val PREFS = "iretail_sbp_session_v1"
        private const val KEY_SESSION_ID = "session_id"
        private const val KEY_STATE = "state"
        private const val KEY_AMOUNT_MINOR = "amount_minor"
        private const val KEY_QR_ID = "qr_id"
        private const val KEY_QR_PAYLOAD = "qr_payload"
        private const val KEY_GENERATION = "generation"
        private const val KEY_CREATED_AT = "created_at_ms"
        private const val KEY_UPDATED_AT = "updated_at_ms"
        private const val KEY_REAL_PAYMENT_SENT = "real_payment_sent"
    }
}
