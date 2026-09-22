package com.coffeeonelove.iretail.ui

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Локальный DRY_RUN будущего Fiscal adapter.
 *
 * Источник wire-формы: переданный проекту документ
 * "Протокол обмена данными с внешними сервисами — потребителями фискализации заказов" (2019).
 *
 * ВАЖНО:
 * - документ исторический, актуальность endpoint не подтверждена;
 * - этот класс НЕ делает сетевых запросов;
 * - api_key/login в приложении отсутствуют;
 * - результат предназначен только для проверки маппинга заказа.
 */
class FiscalizationDraftBuilder(private val context: Context) {
    companion object {
        private const val FILE_NAME = "fiscalization_dry_run.json"
        private const val PROVIDER_CANDIDATE = "iretail_cloud_fiscal_2019_UNCONFIRMED"
        private const val CREATE_ENDPOINT_CANDIDATE = "https://kassa.i-bonus.me/api/cloud-fiscal/order/create"
        private const val STATUS_ENDPOINT_CANDIDATE = "https://kassa.i-bonus.me/api/cloud-fiscal/order/getStatus"
        private const val SEND_ALLOWED = false
    }

    fun write(order: RuntimeOrder): FiscalizationDraftResult {
        val unresolved = JSONArray()
        val form = JSONObject()
        val evidence = JSONObject()

        val paid = order.status == OrderStatus.PAID
        if (!paid) {
            unresolved.put("payment_state: fiscal draft is intended only after confirmed payment")
        }

        if (order.paymentMethod != PaymentMethod.CARD) {
            unresolved.put("payment_method: only confirmed external card payment is currently mapped")
        }

        val hasOrderLevelDiscount = order.ibonusDiscountMinor > 0L
        if (hasOrderLevelDiscount) {
            unresolved.put("discount_allocation: iBonus order-level discount is not yet allocated across fiscal product prices")
        }

        var grossLinesMinor = 0L
        var productsWithModifiers = 0

        order.items.forEachIndexed { index, line ->
            val lineMinor = line.product.priceMinor * line.quantity.toLong()
            grossLinesMinor += lineMinor

            if (line.ownCup || line.syrupAdded) productsWithModifiers++

            form.put("purchase[products][$index][name]", line.product.name)
            form.put(
                "purchase[products][$index][price]",
                if (hasOrderLevelDiscount) JSONObject.NULL else money(line.product.priceMinor)
            )
            form.put("purchase[products][$index][quantity]", line.quantity)

            evidence.put(
                "product_$index",
                JSONObject()
                    .put("catalog_id", line.product.id)
                    .put("price_minor", line.product.priceMinor)
                    .put("quantity", line.quantity)
                    .put("tax_id", line.product.taxId ?: JSONObject.NULL)
                    .put("own_cup", line.ownCup)
                    .put("syrup_added", line.syrupAdded)
            )
        }

        if (productsWithModifiers > 0) {
            unresolved.put("modifiers: own-cup/syrup fiscal line representation is not confirmed")
        }

        form.put("date_time", utcNow())
        form.put("external_order_id", order.externalNumber)
        form.put("card_amount", money(order.amountMinor))

        val grossMatchesRuntime = grossLinesMinor == order.grossAmountMinor
        if (!grossMatchesRuntime) {
            unresolved.put("gross_sum: cart line sum does not equal RuntimeOrder.grossAmountMinor")
        }

        val payableEquationMatches =
            (order.grossAmountMinor - order.ibonusDiscountMinor).coerceAtLeast(0L) == order.amountMinor
        if (!payableEquationMatches) {
            unresolved.put("payable_sum: gross-discount does not equal RuntimeOrder.amountMinor")
        }

        unresolved
            .put("provider: 2019 cloud-fiscal endpoint must be confirmed as current or replaced by the current Fiscal provider")
            .put("credentials: fiscal api_key/login are intentionally not stored in the Android application")
            .put("mode: email/noprint semantics must be confirmed for the current provider")
            .put("ffd_payment: full_payment versus other payment attribute must be confirmed")
            .put("ffd_subject: commodity/service mapping must be confirmed")
            .put("vat: catalog tax_id to fiscal VAT mapping must be confirmed")
            .put("retail_link: whether cloud-fiscal replaces or complements iretail/order/synchronize is not confirmed")

        val report = JSONObject()
            .put("mode", "DRY_RUN_ONLY")
            .put("send_allowed", SEND_ALLOWED)
            .put("provider_candidate", PROVIDER_CANDIDATE)
            .put("source_document", "API web-фискальник / external fiscalization protocol, 2019")
            .put("create_endpoint_candidate", CREATE_ENDPOINT_CANDIDATE)
            .put("status_endpoint_candidate", STATUS_ENDPOINT_CANDIDATE)
            .put("network_actions", "NONE")
            .put("credentials_present", false)
            .put("order_state", order.status.name)
            .put("payment_method", order.paymentMethod?.name ?: JSONObject.NULL)
            .put("external_order_id", order.externalNumber)
            .put("gross_amount_minor", order.grossAmountMinor)
            .put("discount_minor", order.ibonusDiscountMinor)
            .put("payable_amount_minor", order.amountMinor)
            .put("gross_lines_minor", grossLinesMinor)
            .put("gross_matches_runtime", grossMatchesRuntime)
            .put("payable_equation_matches", payableEquationMatches)
            .put("products_count", order.items.size)
            .put("products_with_modifiers", productsWithModifiers)
            .put("form_fields_candidate", form)
            .put("product_evidence", evidence)
            .put("unresolved", unresolved)

        val file = File(context.filesDir, FILE_NAME)
        file.writeText(report.toString(2), Charsets.UTF_8)

        return FiscalizationDraftResult(
            file = file,
            sendAllowed = SEND_ALLOWED,
            unresolvedCount = unresolved.length(),
            grossMatchesRuntime = grossMatchesRuntime,
            payableEquationMatches = payableEquationMatches
        )
    }

    private fun money(valueMinor: Long): String {
        val safe = valueMinor.coerceAtLeast(0L)
        return String.format(Locale.US, "%d.%02d", safe / 100L, safe % 100L)
    }

    private fun utcNow(): String {
        val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }
}

data class FiscalizationDraftResult(
    val file: File,
    val sendAllowed: Boolean,
    val unresolvedCount: Int,
    val grossMatchesRuntime: Boolean,
    val payableEquationMatches: Boolean
)
