package com.coffeeonelove.iretail.ui

import android.content.Context

data class StoredSbpSession(
    val sessionId: String,
    val state: SbpPaymentState,
    val amountMinor: Long,
    val generation: Int,
    val createdAtMs: Long,
    val expiresAtMs: Long,
    val adapterId: String,
    val realPaymentSent: Boolean,
    val updatedAtMs: Long
) {
    val unresolved: Boolean
        get() = realPaymentSent || state in setOf(
            SbpPaymentState.QR_READY,
            SbpPaymentState.WAITING_CONFIRMATION,
            SbpPaymentState.UNCERTAIN
        )
}

class SbpSessionStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(snapshot: SbpPaymentSnapshot) {
        prefs.edit()
            .putString(KEY_SESSION_ID, snapshot.sessionId)
            .putString(KEY_STATE, snapshot.state.name)
            .putLong(KEY_AMOUNT_MINOR, snapshot.amountMinor)
            .putInt(KEY_GENERATION, snapshot.generation)
            .putLong(KEY_CREATED_AT, snapshot.createdAtMs)
            .putLong(KEY_EXPIRES_AT, snapshot.expiresAtMs)
            .putString(KEY_ADAPTER_ID, snapshot.adapterId)
            .putBoolean(KEY_REAL_PAYMENT_SENT, snapshot.realPaymentSent)
            .putLong(KEY_UPDATED_AT, System.currentTimeMillis())
            .apply()
    }

    fun load(): StoredSbpSession? {
        val sessionId = prefs.getString(KEY_SESSION_ID, null)?.takeIf { it.isNotBlank() } ?: return null
        val stateName = prefs.getString(KEY_STATE, null) ?: return null
        val state = runCatching { SbpPaymentState.valueOf(stateName) }.getOrNull() ?: return null
        val amountMinor = prefs.getLong(KEY_AMOUNT_MINOR, -1L)
        val generation = prefs.getInt(KEY_GENERATION, 0)
        val adapterId = prefs.getString(KEY_ADAPTER_ID, "unknown").orEmpty()
        if (amountMinor <= 0L || generation <= 0) return null
        return StoredSbpSession(
            sessionId = sessionId,
            state = state,
            amountMinor = amountMinor,
            generation = generation,
            createdAtMs = prefs.getLong(KEY_CREATED_AT, 0L),
            expiresAtMs = prefs.getLong(KEY_EXPIRES_AT, 0L),
            adapterId = adapterId,
            realPaymentSent = prefs.getBoolean(KEY_REAL_PAYMENT_SENT, false),
            updatedAtMs = prefs.getLong(KEY_UPDATED_AT, 0L)
        )
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val PREFS = "iretail_sbp_session_v1"
        private const val KEY_SESSION_ID = "session_id"
        private const val KEY_STATE = "state"
        private const val KEY_AMOUNT_MINOR = "amount_minor"
        private const val KEY_GENERATION = "generation"
        private const val KEY_CREATED_AT = "created_at_ms"
        private const val KEY_EXPIRES_AT = "expires_at_ms"
        private const val KEY_ADAPTER_ID = "adapter_id"
        private const val KEY_REAL_PAYMENT_SENT = "real_payment_sent"
        private const val KEY_UPDATED_AT = "updated_at_ms"

        // QR payload / qrId намеренно отсутствуют: платёжный токен не хранится долговечно.
    }
}
