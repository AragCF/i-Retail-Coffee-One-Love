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
 * Read-only recovery diagnostic. It NEVER starts, repeats, cancels or refunds a transaction.
 * It only calls getState(), getTerminalData() and getLastTransaction().
 */
class SmartSkyPosLastTransactionActivity : Activity() {
    private lateinit var output: TextView
    private lateinit var refresh: Button
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var service: ISmartSkyPos? = null

    private val connector by lazy {
        SmartSkyPosConnector(
            context = applicationContext,
            onConnected = { remote ->
                service = remote
                log("BIND_OK")
                queryLastTransaction()
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
        buildUi()
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
            text = "SmartSkyPOS — последняя транзакция"
            textSize = 21f
            setTextColor(Color.BLACK)
        }, matchWrap())
        root.addView(TextView(this).apply {
            text = "ТОЛЬКО ЧТЕНИЕ: payment/cancel/refund не вызываются."
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
            setOnClickListener { queryLastTransaction() }
        }
        root.addView(refresh, matchWrap())
        setContentView(root)
    }

    private fun queryLastTransaction() {
        val remote = service ?: return
        refresh.isEnabled = false
        output.text = "Чтение состояния и последней транзакции…"
        executor.execute {
            try {
                val state = remote.state
                val terminalData = remote.terminalData
                val tid = terminalData.terminalId
                    ?.takeIf { it.isNotBlank() }
                    ?: terminalData.terminals?.firstOrNull()?.terminalId
                    ?: ""

                if (terminalData.code != 0 || tid.isBlank()) {
                    val text = "State=$state\nTerminalData code=${terminalData.code}\nTID не определён"
                    log(text.replace('\n', ' '))
                    show(text)
                    return@execute
                }

                val result = remote.getLastTransaction(TransactionParams(tid))
                val text = safeSummary(state, tid, result)
                log("LAST_TRANSACTION " + text.replace('\n', ' '))
                show(text)
            } catch (e: Exception) {
                val text = "Ошибка чтения: ${e.javaClass.simpleName}: ${safe(e.message)}"
                log(text)
                show(text)
            }
        }
    }

    private fun safeSummary(state: Int, requestedTid: String, r: TransactionResult): String {
        return buildString {
            appendLine("State: $state")
            appendLine("Requested TID: $requestedTid")
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
            Toast.makeText(this, "Последняя транзакция прочитана", Toast.LENGTH_SHORT).show()
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
        const val TAG = "SmartSkyPOSLastTx"
    }
}
