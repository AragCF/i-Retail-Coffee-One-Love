package com.coffeeonelove.iretail.ui

object SbpProductionContract {
    const val OPERATION_TYPE = "42"
    const val TRANSACTION_TYPE = "qrPayment"
    const val CURRENCY = "643"
    const val BINDER_TRANSACTION = 19
    const val MIN_ROUTE_BRIDGE_VERSION = "0.5.3"
    const val CALLBACK_BRIDGE_VERSION = "0.5.4"
    const val CALLBACK_CONTRACT = "CAPTURE_HASHED_V1"
    const val WIRE_BRIDGE_VERSION = "0.5.5"
    const val WIRE_CONTRACT = "BASE64URL_REDACTED_V1"
    const val LIVE_CALL_ENABLED = false
}

enum class SbpPaymentState {
    IDLE,
    QR_READY,
    WAITING,
    PAID,
    DECLINED,
    EXPIRED,
    CANCELLED,
    UNCERTAIN,
    ERROR
}

data class SbpSessionRecord(
    val sessionId: String,
    val state: SbpPaymentState,
    val amountMinor: Long,
    val qrId: String?,
    val qrPayload: String?,
    val generation: Int,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val realPaymentSent: Boolean
) {
    val isActive: Boolean
        get() = state == SbpPaymentState.QR_READY ||
            state == SbpPaymentState.WAITING ||
            state == SbpPaymentState.UNCERTAIN
}

data class SbpSafeSummary(
    val sessionId: String,
    val state: SbpPaymentState,
    val amountMinor: Long,
    val generation: Int,
    val qrIdHash: String,
    val qrPayloadHash: String,
    val qrPayloadLength: Int,
    val realPaymentSent: Boolean
)
