package com.coffeeonelove.iretail.pos

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
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
 *      --ez allow_payment true --es amount 1.00
 *
 * Even in payment mode the call is NOT automatic: READY + TerminalData are required
 * and the operator must press the button and confirm the dialog.
 */
class SmartSkyPosDiagnosticActivity : Activity(), SmartSkyPosGateway.Listener {
    private lateinit var gateway: SmartSkyPosGateway

    private lateinit var status: TextView
    private lateinit var logView: TextView
    private lateinit var amountInput: EditText
    private lateinit var terminalInput: EditText
    private lateinit var currencyInput: EditText
    private lateinit var paymentButton: Button

    private val diagnosticLines = ArrayDeque<String>()
    private var latestSnapshot = SmartSkyPosGateway.Snapshot()
    private var paymentModeEnabled = false
    private var autoFilledTerminal = false
    private var autoFilledCurrency = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        paymentModeEnabled = intent.getBooleanExtra(EXTRA_ALLOW_PAYMENT, false)
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
        status.text = buildString {
            appendLine("Bind: ${yesNo(snapshot.bound)}")
            appendLine("StateCallback: ${yesNo(snapshot.callbackRegistered)}")
            appendLine("State: $stateText")
            appendLine("TerminalData code: ${snapshot.terminalDataCode ?: "—"}")
            appendLine("Terminal count: ${snapshot.terminals.size}")
            append("Payment gate: $gate")
        }

        if (!autoFilledTerminal && snapshot.terminals.isNotEmpty()) {
            val preferred = snapshot.defaultTerminalId?.takeIf { id -> snapshot.terminals.any { it.id == id } }
                ?: snapshot.terminals.first().id
            if (preferred.isNotBlank()) {
                terminalInput.setText(preferred)
                autoFilledTerminal = true
            }
        }

        val selected = snapshot.terminals.firstOrNull { it.id == terminalInput.text.toString().trim() }
            ?: snapshot.terminals.firstOrNull()
        if (!autoFilledCurrency) {
            selected?.currencies?.firstOrNull { it.code.isNotBlank() }?.let {
                currencyInput.setText(it.code)
                autoFilledCurrency = true
            }
        }

        updatePaymentButton()
    }

    override fun onPaymentFinished(result: SmartSkyPosGateway.SafeTransactionResult) {
        val text = if (result.approvedSuccessfully) {
            "Операция одобрена. code=${result.code}, RRN=${result.rrn ?: "—"}"
        } else {
            "Операция НЕ подтверждена как успешная. code=${result.code}, approved=${result.approved}, ${result.message ?: ""}"
        }
        Toast.makeText(this, text, Toast.LENGTH_LONG).show()
        updatePaymentButton()
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            setBackgroundColor(Color.WHITE)
        }

        root.addView(TextView(this).apply {
            text = "SmartSkyPOS / Kozen P12 — диагностика"
            textSize = 24f
            setTextColor(Color.BLACK)
        }, matchWrap())

        root.addView(TextView(this).apply {
            text = if (paymentModeEnabled) {
                "Режим контролируемой оплаты ВКЛЮЧЁН. Автоматических финансовых операций нет."
            } else {
                "Безопасный режим: payment() полностью отключён. Проверяются bind → callback → getState() → getTerminalData()."
            }
            textSize = 15f
            setTextColor(if (paymentModeEnabled) 0xFF9A5B00.toInt() else 0xFF256029.toInt())
            setPadding(0, dp(8), 0, dp(12))
        }, matchWrap())

        status = TextView(this).apply {
            textSize = 17f
            setTextColor(Color.BLACK)
            setPadding(dp(12), dp(12), dp(12), dp(12))
            setBackgroundColor(0xFFF1F3F5.toInt())
        }
        root.addView(status, matchWrap())

        val probeButton = Button(this).apply {
            text = "Повторить безопасную проверку"
            setOnClickListener { gateway.probeAgain() }
        }
        root.addView(probeButton, matchWrap())

        root.addView(label("Сумма:"))
        amountInput = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
            setText(intent.getStringExtra(EXTRA_AMOUNT) ?: "1.00")
            isEnabled = paymentModeEnabled
        }
        root.addView(amountInput, matchWrap())

        root.addView(label("Terminal ID (только из TerminalData):"))
        terminalInput = EditText(this).apply {
            isEnabled = paymentModeEnabled
            setSingleLine(true)
        }
        root.addView(terminalInput, matchWrap())

        root.addView(label("Currency code (только из TerminalData):"))
        currencyInput = EditText(this).apply {
            isEnabled = paymentModeEnabled
            setSingleLine(true)
        }
        root.addView(currencyInput, matchWrap())

        paymentButton = Button(this).apply {
            text = if (paymentModeEnabled) "КОНТРОЛИРУЕМАЯ TEST payment()" else "payment() отключён безопасным режимом"
            isEnabled = false
            setOnClickListener { confirmPayment() }
        }
        root.addView(paymentButton, matchWrap())

        root.addView(TextView(this).apply {
            text = "Журнал (PAN/CVV/EMV-данные намеренно не выводятся):"
            textSize = 14f
            setTextColor(Color.DKGRAY)
            setPadding(0, dp(14), 0, dp(6))
        }, matchWrap())

        logView = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.BLACK)
            setTextIsSelectable(true)
        }

        val scroll = ScrollView(this).apply {
            addView(logView, matchWrap())
        }
        root.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            0,
            1f
        ))

        setContentView(root)
    }

    private fun updatePaymentButton() {
        paymentButton.isEnabled =
            paymentModeEnabled &&
                latestSnapshot.paymentGateOpen &&
                terminalInput.text.toString().isNotBlank() &&
                currencyInput.text.toString().isNotBlank()
    }

    private fun confirmPayment() {
        if (!paymentModeEnabled || !latestSnapshot.paymentGateOpen) {
            Toast.makeText(this, "Payment gate закрыт", Toast.LENGTH_SHORT).show()
            return
        }

        val amount = amountInput.text.toString().trim()
        val terminalId = terminalInput.text.toString().trim()
        val currency = currencyInput.text.toString().trim()

        AlertDialog.Builder(this)
            .setTitle("Подтвердить TEST payment()")
            .setMessage(
                "Это реальный вызов SmartSkyPOS.payment().\n\n" +
                    "Сумма: $amount\nTerminal ID: $terminalId\nCurrency: $currency\n\n" +
                    "Автоматического повтора при ошибке не будет."
            )
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Вызвать payment()") { _, _ ->
                gateway.paymentTest(amount, terminalId, currency)
            }
            .show()
    }

    private fun label(text: String) = TextView(this).apply {
        this.text = text
        textSize = 13f
        setTextColor(Color.DKGRAY)
        setPadding(0, dp(8), 0, 0)
    }

    private fun matchWrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT
    )

    private fun yesNo(value: Boolean) = if (value) "OK" else "—"
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val EXTRA_ALLOW_PAYMENT = "allow_payment"
        const val EXTRA_AMOUNT = "amount"
    }
}
