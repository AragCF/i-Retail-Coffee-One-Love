package com.coffeeonelove.iretail.ui

import android.content.Context
import java.io.File

/**
 * Стабильная граница фискального контура.
 *
 * POS подтверждает оплату, после чего приложение передаёт RuntimeOrder сюда.
 * Реализация провайдера может быть заменена без изменения POS / Retail / Device адаптеров.
 */
interface FiscalGateway {
    fun afterPaymentConfirmed(order: RuntimeOrder): FiscalGatewayResult
}

enum class FiscalGatewayState {
    NOT_CONFIGURED,
    DRAFT_READY,
    SUBMITTED,
    FISCALIZED,
    FAILED,
    UNCERTAIN
}

data class FiscalGatewayResult(
    val state: FiscalGatewayState,
    val message: String,
    val receiptUrl: String? = null,
    val draftFile: File? = null,
    val sendAllowed: Boolean = false
)

/**
 * Текущая единственная реализация.
 *
 * Она строит локальный DRY_RUN и принципиально не выполняет сетевых запросов.
 */
class DryRunFiscalGateway(context: Context) : FiscalGateway {
    private val builder = FiscalizationDraftBuilder(context)

    override fun afterPaymentConfirmed(order: RuntimeOrder): FiscalGatewayResult {
        if (order.status != OrderStatus.PAID) {
            return FiscalGatewayResult(
                state = FiscalGatewayState.FAILED,
                message = "Fiscal DRY_RUN не создан: оплата не подтверждена",
                sendAllowed = false
            )
        }

        val draft = builder.write(order)
        return FiscalGatewayResult(
            state = FiscalGatewayState.DRAFT_READY,
            message = "Fiscal DRY_RUN подготовлен; сетевой вызов запрещён",
            receiptUrl = null,
            draftFile = draft.file,
            sendAllowed = draft.sendAllowed
        )
    }
}
