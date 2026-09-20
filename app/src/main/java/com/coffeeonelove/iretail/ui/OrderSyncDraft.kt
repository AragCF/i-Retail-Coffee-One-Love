package com.coffeeonelove.iretail.ui

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * S3 safe order draft.
 *
 * This class does NOT send anything to I-Retail. It only materializes the fields
 * documented in the recovered TSO notes, marks unresolved fields explicitly,
 * validates arithmetic, and stores a local JSON report for review.
 */
class OrderSyncDraftBuilder(private val context: Context) {
    companion object {
        private const val TAG = "IretailOrderDraft"
        private const val FILE_NAME = "order_sync_draft.json"
        private const val ENDPOINT_CANDIDATE = "iretail/order/synchronize"
    }

    fun write(order: RuntimeOrder): OrderSyncDraftResult {
        val config = readNonSecretConfig()
        val products = JSONArray()
        var linesMinor = 0L

        order.items.forEach { line ->
            val lineMinor = line.product.priceMinor * line.quantity.toLong()
            linesMinor += lineMinor
            products.put(
                JSONObject()
                    .put("offer_id", line.product.offerId)
                    .put("quantity", line.quantity)
                    .put("price", money(line.product.priceMinor))
            )
        }

        val candidate = JSONObject()
            .put("id", JSONObject.NULL)
            .put("channel_id", config.channelId)
            .put("sum", money(order.grossAmountMinor))
            .put("device_id", config.deviceId)
            .put("device_code", config.deviceCode)
            .put("employee_id", JSONObject.NULL)
            .put("pin", JSONObject.NULL)
            .put("currency_id", config.currencyId)
            .put("time_create", utcNow())
            .put("products", products)

        val unresolved = JSONArray()
            .put("id: сначала нужно доказать семантику reserve-order-id и связь с order/synchronize")
            .put("employee_id: значение и обязательность не подтверждены текущими источниками")
            .put("pin: значение, назначение и обязательность не подтверждены текущими источниками")
            .put("wire: точный формат сериализации iretail/order/synchronize ещё не подтверждён")
            .put("response: формат ответа, task/idempotency и повторное чтение результата ещё не подтверждены")

        val sumsMatch = linesMinor == order.grossAmountMinor
        val report = JSONObject()
            .put("mode", "DRY_RUN_ONLY")
            .put("endpoint_candidate", ENDPOINT_CANDIDATE)
            .put("send_allowed", false)
            .put("external_number", order.externalNumber)
            .put("candidate_request", candidate)
            .put("unresolved", unresolved)
            .put(
                "validation",
                JSONObject()
                    .put("products_count", order.items.size)
                    .put("lines_sum", money(linesMinor))
                    .put("order_gross_sum", money(order.grossAmountMinor))
                    .put("payable_sum", money(order.amountMinor))
                    .put("discount_sum", money(order.ibonusDiscountMinor))
                    .put("lines_equal_gross", sumsMatch)
                    .put("has_channel_id", config.channelId.isNotBlank())
                    .put("has_device_id", config.deviceId.isNotBlank())
                    .put("has_currency_id", config.currencyId.isNotBlank())
            )

        val file = File(context.filesDir, FILE_NAME)
        file.writeText(report.toString(2), Charsets.UTF_8)
        Log.i(
            TAG,
            "DRAFT_WRITTEN file=$FILE_NAME products=\${order.items.size} gross=\${money(order.grossAmountMinor)} " +
                "linesEqualGross=$sumsMatch sendAllowed=false"
        )
        return OrderSyncDraftResult(file, sumsMatch, unresolved.length())
    }

    private fun readNonSecretConfig(): DraftConfig {
        return try {
            val text = context.assets.open("content/iretail-api.json")
                .bufferedReader(Charsets.UTF_8)
                .use { it.readText() }
            val json = JSONObject(text)
            DraftConfig(
                channelId = json.optString("channel_id", ""),
                deviceId = json.optString("device_id", ""),
                deviceCode = json.optString("device_code", ""),
                currencyId = json.optString("currency_id", "643")
            )
        } catch (_: Exception) {
            DraftConfig()
        }
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

    private data class DraftConfig(
        val channelId: String = "",
        val deviceId: String = "",
        val deviceCode: String = "",
        val currencyId: String = "643"
    )
}

data class OrderSyncDraftResult(
    val file: File,
    val sumsMatch: Boolean,
    val unresolvedCount: Int
)
