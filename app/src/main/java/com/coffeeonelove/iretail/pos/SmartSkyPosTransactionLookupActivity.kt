package com.coffeeonelove.iretail.pos

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.skytech.smartskyposclient.SmartSkyPosConnector
import com.skytech.smartskyposlib.ISmartSkyPos
import com.skytech.smartskyposlib.TransactionParams
import com.skytech.smartskyposlib.TransactionResult
import java.util.concurrent.Executors

/**
 * Read-only transaction recovery diagnostic.
 *
 * It calls only getState(), getTerminalData() and getTransaction().
 * It NEVER calls payment(), cancel(), cancelLast(), refund(), qrPayment(),
 * qrRefund(), reconciliation() or any other financial/mutating operation.
 */
class SmartSkyPosTransactionLookupActivity : Activity() {
    private lateinit var output: TextView
    private lateinit var refresh: Button
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile private var service: ISmartSkyPos? = null
    private var requestedTerminalId: String = ""
    private var requestedReceiptNumber: String = ""

    private val connector by lazy {
        SmartSkyPosConnector(
            context = applicationContext,
            onConnected = { remote ->
                service = remote
                log("BIND_OK")
                queryTransaction()
            },
            onDisconnected = {
                service = null
                log("BIND_DISCONNECTED")
                runOnUiThread {
                    output.text = "SmartSkyPOS отключён"
                    refresh.isEnabled = false
                }
            }
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedTerminalId = intent.getStringExtra(EXTRA_TERMINAL_ID)?.trim().orEmpty()
        requestedReceiptNumber = intent.getStringExtra(EXTRA_RECEIPT_NUMBER)?.trim().orEmpty()
        buildUi()

        if (requestedReceiptNumber.isBlank()) {
            output.text = "Не указан receipt_number. Чтение не выполнялось."
            refresh.isEnabled = false
            log("LOOKUP_BLOCKED receipt_number is empty")
            return
        }

        val ok = try { connector.bind() } catch (e: Exception) { false }
        if (!ok) {
            output.text = "Не удалось привязаться к SmartSkyPOS"
            refresh.isEnabled = false
        }
    }

    override fun onDestroy() {
        try { connector.unbind() } catch (_: Exception) {}
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(14), dp(14), dp(14))
            setBackgroundColor(Color.WHITE)
        }

        root.addView(TextView(this).apply {
            text = "SmartSkyPOS — транзакция по чеку"
            textSize = 21f
            setTextColor(Color.BLACK)
        }, matchWrap())

        root.addView(TextView(this).apply {
            text = "ТОЛЬКО ЧТЕНИЕ: getTransaction(); финансовые операции не вызываются."
            textSize = 13f
            setTextColor(0xFF256029.toInt())
            setPadding(0, dp(6), 0, dp(8))
        }, matchWrap())

        output = TextView(this).apply {
            text = "Подключение…"
            textSize = 16f
            setTextColor(Color.BLACK)
            setTextIsSelectable(true)
        }
        root.addView(output, matchWrap())

        refresh = Button(this).apply {
            text = "ПРОЧИТАТЬ ЕЩЁ РАЗ"
            setOnClickListener { queryTransaction() }
        }
        root.addView(refresh, matchWrap())
        setContentView(root)
    }

    private fun queryTransaction() {
        val remote = service ?: return
        if (requestedReceiptNumber.isBlank()) return

        refresh.isEnabled = false
        output.text = "Чтение транзакции receipt=${requestedReceiptNumber}…"

        executor.execute {
            try {
                val state = remote.state
                val terminalData = remote.terminalData
                val advertisedTerminalIds = buildList {
                    terminalData.terminalId?.trim()?.takeIf { it.isNotEmpty() }?.let { add(it) }
                    terminalData.terminals.orEmpty().forEach { terminal ->
                        terminal.terminalId?.trim()?.takeIf { it.isNotEmpty() }?.let { add(it) }
                    }
                }.distinct()

                if (terminalData.code != 0) {
                    val text = "State: $state\nTerminalData code: ${terminalData.code}\nЧтение транзакции не выполнено"
                    log(text.replace('\n', ' '))
                    show(text)
                    return@execute
                }

                val tid = requestedTerminalId.takeIf { it.isNotBlank() }
                    ?: advertisedTerminalIds.firstOrNull()
                    ?: ""

                if (tid.isBlank()) {
                    val text = "State: $state\nTerminalData code: ${terminalData.code}\nTID не определён"
                    log(text.replace('\n', ' '))
                    show(text)
                    return@execute
                }

                if (advertisedTerminalIds.isNotEmpty() && tid !in advertisedTerminalIds) {
                    val text = buildString {
                        appendLine("State: $state")
                        appendLine("Requested TID: $tid")
                        appendLine("Requested receipt: $requestedReceiptNumber")
                        append("TID отсутствует в актуальном TerminalData")
                    }
                    log("LOOKUP_BLOCKED requested TID is not advertised: $tid")
                    show(text)
                    return@execute
                }

                val params = TransactionParams(tid, requestedReceiptNumber)
                val result = remote.getTransaction(params)
                val text = safeSummary(state, tid, requestedReceiptNumber, result)
                log("TRANSACTION_LOOKUP " + text.replace('\n', ' '))
                show(text)
            } catch (e: Exception) {
                val text = "Ошибка чтения: ${e.javaClass.simpleName}: ${safe(e.message)}"
                log(text)
                show(text)
            }
        }
    }

    private fun safeSummary(
        state: Int,
        requestedTid: String,
        requestedReceipt: String,
        r: TransactionResult
    ): String {
        return buildString {
            appendLine("State: $state")
            appendLine("Requested TID: $requestedTid")
            appendLine("Requested receipt: $requestedReceipt")
            appendLine("code: ${r.code}")
            appendLine("rc: ${safe(r.rc)}")
            appendLine("alternativeRc: ${safe(r.alternativeRc)}")
            appendLine("approved: ${r.isApproved}")
            appendLine("message: ${safe(r.message)}")
            appendLine("amount: ${r.amount?.toPlainString() ?: "—"}")
            appendLine("currency: ${safe(r.currencyCode)}")
            appendLine("terminalId: ${safe(r.terminalId)}")
            appendLine("receipt: ${safe(r.receiptNumberAsString)}")
            appendLine("RRN: ${safe(r.rrn)}")
            appendLine("authCode: ${safe(r.authCode)}")
            appendLine("type: ${safe(r.type)}")
            append("transactionId: ${safe(r.id)}")
        }
    }

    private fun show(text: String) {
        runOnUiThread {
            output.text = text
            refresh.isEnabled = true
            Toast.makeText(this, "Транзакция прочитана", Toast.LENGTH_SHORT).show()
        }
    }

    private fun log(message: String) {
        Log.i(TAG, message)
    }

    private fun safe(value: String?): String {
        if (value.isNullOrBlank()) return "—"
        return value.replace('\n', ' ').replace('\r', ' ').take(240)
    }

    private fun matchWrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT
    )

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val TAG = "SmartSkyPOSTxLookup"
        const val EXTRA_TERMINAL_ID = "terminal_id"
        const val EXTRA_RECEIPT_NUMBER = "receipt_number"
    }
}
