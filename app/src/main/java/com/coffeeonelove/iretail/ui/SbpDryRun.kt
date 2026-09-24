package com.coffeeonelove.iretail.ui

import java.util.concurrent.atomic.AtomicInteger

enum class SbpDryRunState {
    IDLE,
    QR_READY,
    WAITING_CONFIRMATION,
    CONFIRMED,
    EXPIRED,
    CANCELLED,
    ERROR
}

data class SbpDryRunSnapshot(
    val sessionId: String,
    val state: SbpDryRunState,
    val amountMinor: Long,
    val qrId: String?,
    val qrPayload: String?,
    val generation: Int,
    val realPaymentSent: Boolean = false
)

class SbpDryRunSession {
    private val generationCounter = AtomicInteger(0)
    private var current: SbpDryRunSnapshot? = null

    fun current(): SbpDryRunSnapshot? = current

    fun start(amountMinor: Long, externalNumber: String): SbpDryRunSnapshot {
        require(amountMinor > 0L)
        val existing = current
        if (existing != null && existing.state in setOf(SbpDryRunState.QR_READY, SbpDryRunState.WAITING_CONFIRMATION)) {
            return existing
        }
        val generation = generationCounter.incrementAndGet()
        val safeExternal = externalNumber.filter { it.isLetterOrDigit() || it == '-' }.take(32)
        val sessionId = "sbp-dryrun-$generation-$safeExternal"
        val qrId = "dry-$generation"
        val payload = "SBP-DRY-RUN|session=$sessionId|amountMinor=$amountMinor|generation=$generation"
        return SbpDryRunSnapshot(
            sessionId = sessionId,
            state = SbpDryRunState.QR_READY,
            amountMinor = amountMinor,
            qrId = qrId,
            qrPayload = payload,
            generation = generation,
            realPaymentSent = false
        ).also { current = it }
    }

    fun markWaiting(): SbpDryRunSnapshot? = updateState(SbpDryRunState.WAITING_CONFIRMATION)

    fun confirmSynthetic(): SbpDryRunSnapshot? = updateState(SbpDryRunState.CONFIRMED)

    fun expire(): SbpDryRunSnapshot? = updateState(SbpDryRunState.EXPIRED)

    fun cancel(): SbpDryRunSnapshot? = updateState(SbpDryRunState.CANCELLED)

    fun reset() {
        current = null
    }

    private fun updateState(state: SbpDryRunState): SbpDryRunSnapshot? {
        val value = current ?: return null
        val updated = value.copy(state = state, realPaymentSent = false)
        current = updated
        return updated
    }
}
