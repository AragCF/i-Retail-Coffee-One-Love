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
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val realPaymentSent: Boolean = false
) {
    fun toSessionRecord(): SbpSessionRecord =
        SbpSessionRecord(
            sessionId = sessionId,
            state = when (state) {
                SbpDryRunState.IDLE -> SbpPaymentState.IDLE
                SbpDryRunState.QR_READY -> SbpPaymentState.QR_READY
                SbpDryRunState.WAITING_CONFIRMATION -> SbpPaymentState.WAITING
                SbpDryRunState.CONFIRMED -> SbpPaymentState.PAID
                SbpDryRunState.EXPIRED -> SbpPaymentState.EXPIRED
                SbpDryRunState.CANCELLED -> SbpPaymentState.CANCELLED
                SbpDryRunState.ERROR -> SbpPaymentState.ERROR
            },
            amountMinor = amountMinor,
            qrId = qrId,
            qrPayload = qrPayload,
            generation = generation,
            createdAtMs = createdAtMs,
            updatedAtMs = updatedAtMs,
            realPaymentSent = false
        )
}

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
        val now = System.currentTimeMillis()
        return SbpDryRunSnapshot(
            sessionId = sessionId,
            state = SbpDryRunState.QR_READY,
            amountMinor = amountMinor,
            qrId = qrId,
            qrPayload = payload,
            generation = generation,
            createdAtMs = now,
            updatedAtMs = now,
            realPaymentSent = false
        ).also { current = it }
    }

    fun markWaiting(): SbpDryRunSnapshot? = updateState(SbpDryRunState.WAITING_CONFIRMATION)

    fun confirmSynthetic(): SbpDryRunSnapshot? = updateState(SbpDryRunState.CONFIRMED)

    fun expire(): SbpDryRunSnapshot? = updateState(SbpDryRunState.EXPIRED)

    fun cancel(): SbpDryRunSnapshot? = updateState(SbpDryRunState.CANCELLED)

    fun restore(record: SbpSessionRecord): SbpDryRunSnapshot {
        // Android 6 / API 23: avoid AtomicInteger.updateAndGet(lambda).
        // The Java 8 functional-interface path produced a synthetic lambda class that was
        // not loadable on the real JL22. CAS keeps the same monotonic invariant without
        // java.util.function or an external synthetic lambda class.
        var observed = generationCounter.get()
        while (observed < record.generation) {
            if (generationCounter.compareAndSet(observed, record.generation)) break
            observed = generationCounter.get()
        }
        val restored = SbpDryRunSnapshot(
            sessionId = record.sessionId,
            state = when (record.state) {
                SbpPaymentState.IDLE -> SbpDryRunState.IDLE
                SbpPaymentState.QR_READY -> SbpDryRunState.QR_READY
                SbpPaymentState.WAITING -> SbpDryRunState.WAITING_CONFIRMATION
                SbpPaymentState.PAID -> SbpDryRunState.CONFIRMED
                SbpPaymentState.EXPIRED -> SbpDryRunState.EXPIRED
                SbpPaymentState.CANCELLED -> SbpDryRunState.CANCELLED
                SbpPaymentState.DECLINED, SbpPaymentState.UNCERTAIN, SbpPaymentState.ERROR -> SbpDryRunState.ERROR
            },
            amountMinor = record.amountMinor,
            qrId = record.qrId,
            qrPayload = record.qrPayload,
            generation = record.generation,
            createdAtMs = record.createdAtMs,
            updatedAtMs = record.updatedAtMs,
            realPaymentSent = false
        )
        current = restored
        return restored
    }

    fun reset() {
        current = null
    }

    private fun updateState(state: SbpDryRunState): SbpDryRunSnapshot? {
        val value = current ?: return null
        val updated = value.copy(
            state = state,
            updatedAtMs = System.currentTimeMillis(),
            realPaymentSent = false
        )
        current = updated
        return updated
    }
}
