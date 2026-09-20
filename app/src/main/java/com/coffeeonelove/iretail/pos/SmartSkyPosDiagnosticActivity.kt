package com.coffeeonelove.iretail.pos

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/**
 * ADB-only diagnostic surface. It is intentionally not in the launcher.
 *
 * Safe probe:
 *   adb shell am start -n com.coffeeonelove.iretail/.pos.SmartSkyPosDiagnosticActivity
 *
 * Controlled payment mode:
 *   adb shell am start -n com.coffeeonelove.iretail/.pos.SmartSkyPosDiagnosticActivity \
 *      --ez allow_payment true
 *
 * Even in payment mode the call is NOT automatic: READY + fresh TerminalData are required,
 * the amount must be selected with one of the fixed test buttons, and the operator must
 * press the payment button and confirm the dialog.
 *
 * v0.5.9 deliberately has no EditText at all. Kozen P12's small 480x432 display and IME
 * made the old editable controls unreliable and could hide the actual payment button.
 */
class SmartSkyPosDiagnosticActivity : Activity(), SmartSkyPosGateway.Listener {
    private lateinit var gateway: SmartSkyPosGateway

    private lateinit var status: TextView
    private lateinit var amountValue: TextView
    private lateinit var routeValue: TextView
    private lateinit var resultValue: TextView
    private lateinit var logView: TextView
    private lateinit var paymentButton: Button

    private val diagnosticLines = ArrayDeque<String>()
    private var latestSnapshot = SmartSkyPosGateway.Snapshot()
    private var paymentModeEnabled = false
    private var selectedAmount = DEFAULT_TEST_AMOUNT

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        paymentModeEnabled = intent.getBooleanExtra(EXTRA_ALLOW_PAYMENT, false)
        selectedAmount = normalizeFixedAmount(intent.getStringExtra(EXTRA_AMOUNT))
        buildUi()
        gateway = SmartSkyPosGateway(this, this)
        gateway.bindAndProbe()
    }

    override fun onDestroy() {
        gateway.close()
        super.onDestroy()
    }

    override fun onDiagnosticLine(line: String) {
        if (diagnosticLines.size >= 250) diagnosticLines.removeFirst()
        diagnosticLines.addLast(line)
        logView.text = diagnosticLines.joinToString("\n")
    }

    override fun onSnapshot(snapshot: SmartSkyPosGateway.Snapshot) {
        latestSnapshot = snapshot

        val stateText = snapshot.state?.let {
            if (it == SmartSkyPosGateway.Snapshot.STATE_READY) "READY(0)"
            else if (it == SmartSkyPosGateway.Snapshot.STATE_UNFINISHED_OPERATION) "UNFINISHED_OPERATION(2)"
            else it.toString()
        } ?: "—"

        val gate = if (snapshot.paymentGateOpen) "OPEN" else "CLOSED"
        status.text =
            "Bind: ${yesNo(snapshot.bound)} | Callback: ${yesNo(snapshot.callbackRegistered)} | State: $stateText\n" +
                "TerminalData: ${snapshot.terminalDataCode ?: "—"} | Terminals: ${snapshot.terminals.size} | Gate: $gate"

        val route = selectCardPaymentRoute(snapshot)
        routeValue.text = if (route != null) {
            "Terminal: ${route.first}   Currency: ${route.second}"
        } else {
            "Terminal / currency: —"
        }

        updateAmountValue(route?.second)
        updatePaymentButton()
    }

    override fun onPaymentFinished(result: SmartSkyPosGateway.SafeTransactionResult) {
        val text = if (result.approvedSuccessfully) {
            "ОДОБРЕНО: code=${result.code}, RRN=${result.rrn ?: "—"}, receipt=${result.receiptNumber ?: "—"}"
        } else {
            "НЕ ПОДТВЕРЖДЕНО: code=${result.code}, approved=${result.approved}, ${result.message ?: ""}"
        }
        resultValue.text = text
        Toast.makeText(this, text, Toast.LENGTH_LONG).show()
        updatePaymentButton()
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            setBackgroundColor(Color.WHITE)
        }

        root.addView(TextView(this).apply {
            text = "SmartSkyPOS / Kozen P12 — payment test v0.5.9"
            textSize = 19f
            setTextColor(Color.BLACK)
        }, matchWrap())

        root.addView(TextView(this).apply {
            text = if (paymentModeEnabled) {
                "Контролируемая реальная оплата. Автозапуска и автоповтора нет."
            } else {
                "Безопасный probe: payment() полностью отключён."
            }
            textSize = 13f
            setTextColor(if (paymentModeEnabled) 0xFF9A5B00.toInt() else 0xFF256029.toInt())
            setPadding(0, dp(4), 0, dp(6))
        }, matchWrap())

        status = TextView(this).apply {
            text = "Bind: — | Callback: — | State: —\nTerminalData: — | Terminals: 0 | Gate: CLOSED"
            textSize = 14f
            setTextColor(Color.BLACK)
            setPadding(dp(8), dp(7), dp(8), dp(7))
            setBackgroundColor(0xFFF1F3F5.toInt())
        }
        root.addView(status, matchWrap())

        amountValue = TextView(this).apply {
            textSize = 18f
            setTextColor(Color.BLACK)
            setPadding(0, dp(7), 0, dp(3))
        }
        root.addView(amountValue, matchWrap())
        updateAmountValue(null)

        val amountRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        amountRow.addView(amountButton("1 ₽", "1.00"), weightedButton())
        amountRow.addView(amountButton("10 ₽", "10.00"), weightedButton())
        amountRow.addView(amountButton("100 ₽", "100.00"), weightedButton())
        root.addView(amountRow, matchWrap())

        routeValue = TextView(this).apply {
            text = "Terminal / currency: —"
            textSize = 13f
            setTextColor(Color.DKGRAY)
            setPadding(0, dp(5), 0, dp(4))
        }
        root.addView(routeValue, matchWrap())

        paymentButton = Button(this).apply {
            text = if (paymentModeEnabled) {
                "ВЫПОЛНИТЬ ТЕСТОВУЮ ОПЛАТУ"
            } else {
                "payment() отключён безопасным режимом"
            }
            isEnabled = false
            setOnClickListener { confirmPayment() }
        }
        root.addView(paymentButton, matchWrap())

        resultValue = TextView(this).apply {
            text = "Результат: операция ещё не запускалась"
            textSize = 13f
            setTextColor(Color.BLACK)
            setPadding(0, dp(5), 0, dp(3))
        }
        root.addView(resultValue, matchWrap())

        val probeButton = Button(this).apply {
            text = "Обновить состояние"
            setOnClickListener { gateway.probeAgain() }
        }
        root.addView(probeButton, matchWrap())

        root.addView(TextView(this).apply {
            text = "Журнал без PAN/CVV/EMV:"
            textSize = 12f
            setTextColor(Color.DKGRAY)
            setPadding(0, dp(4), 0, dp(2))
        }, matchWrap())

        logView = TextView(this).apply {
            textSize = 11f
            setTextColor(Color.BLACK)
            setTextIsSelectable(true)
        }

        val scroll = ScrollView(this).apply {
            addView(logView, matchWrap())
        }
        root.addView(
            scroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        )

        setContentView(root)
    }

    private fun amountButton(caption: String, amount: String): Button {
        return Button(this).apply {
            text = caption
            isEnabled = paymentModeEnabled
            setOnClickListener {
                selectedAmount = amount
                resultValue.text = "Результат: операция ещё не запускалась"
                updateAmountValue(selectCardPaymentRoute(latestSnapshot)?.second)
            }
        }
    }

    private fun updateAmountValue(currencyCode: String?) {
        val currencyLabel = if (currencyCode == RUB_CURRENCY_CODE) "RUB" else currencyCode ?: "—"
        amountValue.text = "Тестовая сумма: $selectedAmount $currencyLabel"
    }

    private fun updatePaymentButton() {
        val route = selectCardPaymentRoute(latestSnapshot)
        paymentButton.isEnabled =
            paymentModeEnabled &&
                latestSnapshot.paymentGateOpen &&
                !latestSnapshot.paymentInFlight &&
                route != null

        if (latestSnapshot.paymentInFlight) {
            paymentButton.text = "ОПЕРАЦИЯ ВЫПОЛНЯЕТСЯ…"
        } else {
            paymentButton.text = if (paymentModeEnabled) {
                "ВЫПОЛНИТЬ ТЕСТОВУЮ ОПЛАТУ"
            } else {
                "payment() отключён безопасным режимом"
            }
        }
    }

    private fun confirmPayment() {
        if (!paymentModeEnabled || !latestSnapshot.paymentGateOpen) {
            Toast.makeText(this, "Payment gate закрыт", Toast.LENGTH_SHORT).show()
            return
        }

        val route = selectCardPaymentRoute(latestSnapshot)
        if (route == null) {
            Toast.makeText(this, "В TerminalData нет карточной операции payment", Toast.LENGTH_LONG).show()
            return
        }

        val terminalId = route.first
        val currency = route.second

        AlertDialog.Builder(this)
            .setTitle("Подтвердить реальную TEST payment()")
            .setMessage(
                "Это реальный вызов SmartSkyPOS.payment().\n\n" +
                    "Сумма: $selectedAmount\nTerminal ID: $terminalId\nCurrency: $currency\n\n" +
                    "Перед вызовом gateway повторно проверит READY и свежий TerminalData. " +
                    "Автоматического повтора при ошибке не будет."
            )
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Вызвать payment()") { _, _ ->
                resultValue.text = "Результат: запрос payment() передан в шлюз…"
                paymentButton.isEnabled = false
                gateway.paymentTest(selectedAmount, terminalId, currency)
            }
            .show()
    }

    /**
     * Select only a route explicitly advertised by a SmartSkyPOS operation whose
     * transactionType is "payment". No free-form TID/currency values are accepted in v0.5.9.
     */
    private fun selectCardPaymentRoute(snapshot: SmartSkyPosGateway.Snapshot): Pair<String, String>? {
        if (!snapshot.terminalDataOk) return null

        val terminal = snapshot.defaultTerminalId
            ?.let { defaultId -> snapshot.terminals.firstOrNull { it.id == defaultId } }
            ?: snapshot.terminals.firstOrNull()
            ?: return null

        val paymentOperation = terminal.operations.firstOrNull {
            it.transactionType.equals("payment", ignoreCase = true)
        } ?: return null

        val currency = paymentOperation.currencies.firstOrNull { it.code.isNotBlank() }
            ?: return null

        if (terminal.id.isBlank()) return null
        return terminal.id to currency.code
    }

    private fun normalizeFixedAmount(requested: String?): String {
        return when (requested?.trim()?.replace(',', '.')) {
            "10", "10.0", "10.00" -> "10.00"
            "100", "100.0", "100.00" -> "100.00"
            else -> DEFAULT_TEST_AMOUNT
        }
    }

    private fun matchWrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT
    )

    private fun weightedButton() = LinearLayout.LayoutParams(
        0,
        LinearLayout.LayoutParams.WRAP_CONTENT,
        1f
    )

    private fun yesNo(value: Boolean) = if (value) "OK" else "—"
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val EXTRA_ALLOW_PAYMENT = "allow_payment"
        const val EXTRA_AMOUNT = "amount"
        private const val DEFAULT_TEST_AMOUNT = "1.00"
        private const val RUB_CURRENCY_CODE = "643"
    }
}
