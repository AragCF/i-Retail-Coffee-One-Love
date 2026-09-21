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
 * S3 DRY_RUN v2.
 *
 * This builder mirrors the documented order/synchronize envelope, but it never
 * performs a network request. Values that are not proven for the current live
 * cashbox session remain null and are listed as blockers.
 */
class OrderSyncDraftBuilder(private val context: Context) {
    companion object {
        private const val TAG = "IretailOrderDraft"
        private const val FILE_NAME = "order_sync_draft.json"
        private const val ENDPOINT_CANDIDATE = "iretail/order/synchronize"
        private const val SCHEMA_VERSION = "S3_DRY_RUN_V2"
        private const val CONTRACT_STATE = "BLOCKED_PENDING_DEVICE_REGISTER_DECISION"
    }

    fun write(order: RuntimeOrder): OrderSyncDraftResult {
        val config = readNonSecretConfig()
        val evidence = readEvidence()
        val wireProducts = JSONArray()
        val productEvidence = JSONArray()

        var linesMinor = 0L
        var catalogMetadataComplete = 0

        order.items.forEach { line ->
            val lineMinor = line.product.priceMinor * line.quantity.toLong()
            linesMinor += lineMinor

            val taxProven = line.product.taxId != null &&
                line.product.taxId == evidence.taxId &&
                evidence.taxId > 0

            if (
                !line.product.idYml.isNullOrBlank() &&
                line.product.typeId != null &&
                line.product.unitId != null &&
                line.product.basePriceMinor != null &&
                taxProven
            ) {
                catalogMetadataComplete++
            }

            wireProducts.put(
                JSONObject()
                    .put("uuid", JSONObject.NULL)
                    .put("offer_id", JSONObject.NULL)
                    .put("id_yml", jsonString(line.product.idYml))
                    .put("name", line.product.name)
                    .put("type_id", jsonInt(line.product.typeId))
                    .put("unit_id", jsonInt(line.product.unitId))
                    .put("quantity", line.quantity)
                    .put("commit_time", JSONObject.NULL)
                    .put("base_price", jsonMoney(line.product.basePriceMinor))
                    .put("price", money(line.product.priceMinor))
                    .put("tax_rate", if (taxProven) evidence.taxRate else JSONObject.NULL)
                    .put("tax_included_in_price", if (taxProven) evidence.taxIncludedInPrice else JSONObject.NULL)
                    .put("tax_number_in_printer", if (taxProven) evidence.taxNumberInPrinter else JSONObject.NULL)
                    .put("currency_id", jsonInt(evidence.currencyId.toIntOrNull()))
                    .put("discount_sum", JSONObject.NULL)
            )

            productEvidence.put(
                JSONObject()
                    .put("catalog_internal_id", line.product.id)
                    .put("current_model_offer_id", line.product.offerId)
                    .put("id_yml", jsonString(line.product.idYml))
                    .put("catalog_currency", jsonString(line.product.catalogCurrency))
                    .put("tax_id", jsonInt(line.product.taxId))
                    .put("gcode_present", !line.product.gcode.isNullOrBlank())
            )
        }

        val wireOrder = JSONObject()
            .put("employee_id", JSONObject.NULL)
            .put("channel_id", jsonInt(evidence.channelId.toIntOrNull()))
            .put("sum", JSONObject.NULL)
            .put("shift_id", JSONObject.NULL)
            .put("device_id", JSONObject.NULL)
            .put("order_status_id", JSONObject.NULL)
            .put("payment_status_id", JSONObject.NULL)
            .put("order_number", JSONObject.NULL)
            .put("short_number", JSONObject.NULL)
            .put("number_to_day", JSONObject.NULL)
            .put("time_create", utcNow())
            .put("service_in_slug", JSONObject.NULL)
            .put("ibonus_discount_sum", money(order.ibonusDiscountMinor))
            .put("products", wireProducts)

        val candidate = JSONObject()
            .put("device_id", JSONObject.NULL)
            .put(
                "counters",
                JSONObject()
                    .put("order_counter", JSONObject.NULL)
                    .put("operation_counter", JSONObject.NULL)
                    .put("refund_counter", JSONObject.NULL)
                    .put("date", JSONObject.NULL)
            )
            .put(
                "shift",
                JSONObject()
                    .put("id", JSONObject.NULL)
                    .put("check_counter", JSONObject.NULL)
            )
            .put("orders", JSONArray().put(wireOrder))
            .put("operations", JSONArray())

        val unresolved = JSONArray()
            .put("device_id: configured 6287 is not a proven cashbox; audited device 3476 is stale/offline")
            .put("counters: current order_counter/operation_counter/refund_counter require an approved source")
            .put("shift: audited shift 164570 is stale and must not be reused for a new order")
            .put("employee_id: 3405 is a proven channel/old-shift candidate, but the autonomous-machine selection rule is not approved")
            .put("service_in_slug: external_plastic_cards is a proven external-card candidate, but payment lifecycle mapping is not approved")
            .put("order_status_id/payment_status_id: live reference values are known, but lifecycle transitions are not approved")
            .put("order_number/short_number/number_to_day: generation algorithm is not proven")
            .put("sum: gross versus payable semantics with loyalty discount are not proven for synchronize")
            .put("offer_id: mapping between catalog internal id/current model offer id/id_yml is not proven")
            .put("uuid/commit_time: generation semantics are not proven")
            .put("discount_sum per product: allocation semantics are not proven")
            .put("device/register(device_code): documented source of device/counters/shift, but it is a state-changing contract gate and is NOT called")

        val sumsMatch = linesMinor == order.grossAmountMinor
        val report = JSONObject()
            .put("mode", "DRY_RUN_ONLY")
            .put("schema_version", SCHEMA_VERSION)
            .put("contract_state", CONTRACT_STATE)
            .put("endpoint_candidate", ENDPOINT_CANDIDATE)
            .put("network_actions", "NONE")
            .put("send_allowed", false)
            .put("external_number_local_only", order.externalNumber)
            .put("candidate_request", candidate)
            .put(
                "known_server_evidence",
                JSONObject()
                    .put("snapshot_date", evidence.snapshotDate)
                    .put("channel_id", jsonInt(evidence.channelId.toIntOrNull()))
                    .put("profile_id", jsonInt(evidence.profileId.toIntOrNull()))
                    .put("currency_id", jsonInt(evidence.currencyId.toIntOrNull()))
                    .put("employee_id_candidate", evidence.employeeIdCandidate)
                    .put("employee_wire_selected", false)
                    .put("card_service_in_slug_candidate", evidence.cardServiceSlugCandidate)
                    .put("card_service_wire_selected", false)
                    .put("configured_device_id", jsonInt(config.deviceId.toIntOrNull()))
                    .put("configured_device_cashbox_proven", false)
                    .put("server_device_snapshot", evidence.serverDeviceSnapshot)
                    .put("shift_snapshot", evidence.shiftSnapshot)
                    .put("product_evidence", productEvidence)
            )
            .put("unresolved", unresolved)
            .put(
                "validation",
                JSONObject()
                    .put("products_count", order.items.size)
                    .put("catalog_metadata_complete_items", catalogMetadataComplete)
                    .put("lines_sum", money(linesMinor))
                    .put("order_gross_sum", money(order.grossAmountMinor))
                    .put("payable_sum", money(order.amountMinor))
                    .put("ibonus_discount_sum", money(order.ibonusDiscountMinor))
                    .put("lines_equal_gross", sumsMatch)
                    .put("config_channel_matches_evidence", config.channelId == evidence.channelId)
                    .put("config_currency_matches_evidence", config.currencyId == evidence.currencyId)
                    .put("wire_device_resolved", false)
                    .put("wire_shift_resolved", false)
                    .put("wire_counters_resolved", false)
                    .put("send_allowed", false)
            )

        val file = File(context.filesDir, FILE_NAME)
        file.writeText(report.toString(2), Charsets.UTF_8)

        Log.i(
            TAG,
            "DRAFT_V2_WRITTEN file=" + FILE_NAME +
                " products=" + order.items.size +
                " gross=" + money(order.grossAmountMinor) +
                " linesEqualGross=" + sumsMatch +
                " metadataComplete=" + catalogMetadataComplete +
                " sendAllowed=false"
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
                currencyId = json.optString("currency_id", "643"),
                deviceId = json.optString("device_id", "")
            )
        } catch (_: Exception) {
            DraftConfig()
        }
    }

    private fun readEvidence(): AuditEvidence {
        return try {
            val text = context.assets.open("content/s3-order-evidence.json")
                .bufferedReader(Charsets.UTF_8)
                .use { it.readText() }
            val json = JSONObject(text)
            val tax = json.optJSONObject("tax") ?: JSONObject()
            AuditEvidence(
                snapshotDate = json.optString("snapshot_date", ""),
                channelId = json.optString("channel_id", ""),
                profileId = json.optString("profile_id", ""),
                currencyId = json.optString("currency_id", ""),
                employeeIdCandidate = json.optInt("employee_id_candidate", 0),
                cardServiceSlugCandidate = json.optString("card_service_in_slug_candidate", ""),
                taxId = tax.optInt("id", 0),
                taxRate = tax.optInt("rate", 0),
                taxIncludedInPrice = tax.optBoolean("tax_included_in_price", false),
                taxNumberInPrinter = tax.optInt("number_in_printer", 0),
                serverDeviceSnapshot = json.optJSONObject("server_device_snapshot") ?: JSONObject(),
                shiftSnapshot = json.optJSONObject("shift_snapshot") ?: JSONObject()
            )
        } catch (_: Exception) {
            AuditEvidence()
        }
    }

    private fun jsonString(value: String?): Any =
        if (value.isNullOrBlank()) JSONObject.NULL else value

    private fun jsonInt(value: Int?): Any =
        value ?: JSONObject.NULL

    private fun jsonMoney(value: Long?): Any =
        if (value == null) JSONObject.NULL else money(value)

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
        val currencyId: String = "643",
        val deviceId: String = ""
    )

    private data class AuditEvidence(
        val snapshotDate: String = "",
        val channelId: String = "",
        val profileId: String = "",
        val currencyId: String = "",
        val employeeIdCandidate: Int = 0,
        val cardServiceSlugCandidate: String = "",
        val taxId: Int = 0,
        val taxRate: Int = 0,
        val taxIncludedInPrice: Boolean = false,
        val taxNumberInPrinter: Int = 0,
        val serverDeviceSnapshot: JSONObject = JSONObject(),
        val shiftSnapshot: JSONObject = JSONObject()
    )
}

data class OrderSyncDraftResult(
    val file: File,
    val sumsMatch: Boolean,
    val unresolvedCount: Int
)
