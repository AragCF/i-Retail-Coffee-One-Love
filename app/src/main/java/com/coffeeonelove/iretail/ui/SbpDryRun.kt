package com.coffeeonelove.iretail.ui

import java.util.concurrent.atomic.AtomicInteger

enum class SbpPaymentState {
    IDLE,
    QR_READY,
    WAITING_CONFIRMATION,
    CONFIRMED,
    DECLINED,
    UNCERTAIN,
    EXPIRED,
    CANCELLED,
    ERROR
}

data class SbpPaymentSnapshot(
    val sessionId: String,
    val state: SbpPaymentState,
    val amountMinor: Long,
    val qrId: String?,
    val qrPayload: String?,
    val generation: Int,
    val adapterId: String,
    val liveFinancialEnabled: Boolean,
    val realPaymentSent: Boolean = false
)

interface SbpPaymentAdapter {
    val adapterId: String
    val liveFinancialEnabled: Boolean

    fun current(): SbpPaymentSnapshot?
    fun recover(): SbpPaymentSnapshot?
    fun start(amountMinor: Long, externalNumber: String): SbpPaymentSnapshot
    fun markWaiting(): SbpPaymentSnapshot?
    fun confirmSynthetic(): SbpPaymentSnapshot?
    fun expire(): SbpPaymentSnapshot?
    fun cancel(): SbpPaymentSnapshot?
    fun reset()
}

/**
 * Единственная активная реализация S4 на этом этапе.
 *
 * Не знает о SmartSkyPOS Binder, не вызывает qrPayment и никогда не переводит
 * realPaymentSent в true. Production-реализация будет отдельным классом и
 * отдельным финансовым контрактом.
 */
class DryRunSbpPaymentAdapter(
    private val store: SbpSessionStore? = null
) : SbpPaymentAdapter {
    override val adapterId: String = "dry-run"
    override val liveFinancialEnabled: Boolean = false

    private val generationCounter = AtomicInteger(0)
    private var current: SbpPaymentSnapshot? = null

    override fun current(): SbpPaymentSnapshot? = current

    override fun recover(): SbpPaymentSnapshot? {
        current?.let { return it }
        val stored = store?.load() ?: return null
        generationCounter.set(maxOf(generationCounter.get(), stored.generation))

        val recoveredState = if (stored.unresolved) SbpPaymentState.UNCERTAIN else stored.state
        return SbpPaymentSnapshot(
            sessionId = stored.sessionId,
            state = recoveredState,
            amountMinor = stored.amountMinor,
            qrId = null,
            qrPayload = null,
            generation = stored.generation,
            adapterId = adapterId,
            liveFinancialEnabled = false,
            realPaymentSent = stored.realPaymentSent
        ).also {
            current = it
            store?.save(it)
        }
    }

    override fun start(amountMinor: Long, externalNumber: String): SbpPaymentSnapshot {
        require(amountMinor > 0L)

        val recovered = recover()
        if (recovered != null && recovered.state == SbpPaymentState.UNCERTAIN) {
            return recovered
        }

        val existing = current
        if (existing != null &&
            existing.state in setOf(SbpPaymentState.QR_READY, SbpPaymentState.WAITING_CONFIRMATION)
        ) {
            return existing
        }

        val generation = generationCounter.incrementAndGet()
        val safeExternal = externalNumber.filter { it.isLetterOrDigit() || it == '-' }.take(32)
        val sessionId = "sbp-dryrun-$generation-$safeExternal"
        val qrId = "dry-$generation"
        val payload = "SBP-DRY-RUN|session=$sessionId|amountMinor=$amountMinor|generation=$generation"

        return SbpPaymentSnapshot(
            sessionId = sessionId,
            state = SbpPaymentState.QR_READY,
            amountMinor = amountMinor,
            qrId = qrId,
            qrPayload = payload,
            generation = generation,
            adapterId = adapterId,
            liveFinancialEnabled = liveFinancialEnabled,
            realPaymentSent = false
        ).also { current = it }
    }

    override fun markWaiting(): SbpPaymentSnapshot? =
        updateState(SbpPaymentState.WAITING_CONFIRMATION)

    override fun confirmSynthetic(): SbpPaymentSnapshot? =
        updateState(SbpPaymentState.CONFIRMED)

    override fun expire(): SbpPaymentSnapshot? =
        updateState(SbpPaymentState.EXPIRED)

    override fun cancel(): SbpPaymentSnapshot? =
        updateState(SbpPaymentState.CANCELLED)

    override fun reset() {
        current = null
        store?.clear()
    }

    private fun updateState(state: SbpPaymentState): SbpPaymentSnapshot? {
        val value = current ?: return null
        val updated = value.copy(
            state = state,
            adapterId = adapterId,
            liveFinancialEnabled = false,
            realPaymentSent = false
        )
        current = updated
        store?.save(updated)
        return updated
    }
}

// Совместимость с уже добавленным v0.5.110 UI без дублирования логики.
typealias SbpDryRunState = SbpPaymentState
typealias SbpDryRunSnapshot = SbpPaymentSnapshot
typealias SbpDryRunSession = DryRunSbpPaymentAdapter
