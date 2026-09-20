package com.coffeeonelove.iretail.pos

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.RemoteException
import android.util.Log
import com.skytech.smartskyposclient.SmartSkyPosConnector
import com.skytech.smartskyposlib.Currency
import com.skytech.smartskyposlib.ISmartSkyPos
import com.skytech.smartskyposlib.Operation
import com.skytech.smartskyposlib.StateCallback
import com.skytech.smartskyposlib.Terminal
import com.skytech.smartskyposlib.TerminalData
import com.skytech.smartskyposlib.TransactionCallback
import com.skytech.smartskyposlib.TransactionParams
import com.skytech.smartskyposlib.TransactionResult
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Fail-closed SmartSkyPOS integration for Kozen P12.
 *
 * Contract source:
 * SmartSkyPOS 1.9.19-RC.1.11057 recovered client Binder ABI.
 *
 * The gateway never starts a financial operation automatically.
 * paymentTest() is available only after:
 *  - service bind succeeded;
 *  - StateCallback was registered;
 *  - getState() returned READY (0);
 *  - getTerminalData() returned code == 0;
 *  - selected terminal and currency were confirmed from TerminalData.
 */
class SmartSkyPosGateway(
    context: Context,
    private val listener: Listener
) {
    interface Listener {
        fun onDiagnosticLine(line: String)
        fun onSnapshot(snapshot: Snapshot)
        fun onPaymentFinished(result: SafeTransactionResult)
    }

    data class CurrencyInfo(
        val code: String,
        val caption: String,
        val exponent: Int
    )

    data class OperationInfo(
        val name: String,
        val type: String,
        val transactionType: String,
        val currencies: List<CurrencyInfo>
    )

    data class TerminalInfo(
        val id: String,
        val name: String,
        val operations: List<OperationInfo>
    ) {
        val currencies: List<CurrencyInfo>
            get() = operations.flatMap { it.currencies }.distinctBy { it.code }
    }

    data class Snapshot(
        val bound: Boolean = false,
        val callbackRegistered: Boolean = false,
        val state: Int? = null,
        val stateMessage: String? = null,
        val terminalDataCode: Int? = null,
        val terminalDataMessage: String? = null,
        val merchantId: String? = null,
        val serialNumber: String? = null,
        val defaultTerminalId: String? = null,
        val terminals: List<TerminalInfo> = emptyList(),
        val paymentInFlight: Boolean = false
    ) {
        val ready: Boolean get() = state == STATE_READY
        val unfinishedOperation: Boolean get() = state == STATE_UNFINISHED_OPERATION
        val terminalDataOk: Boolean get() = terminalDataCode == 0 && terminals.isNotEmpty()
        val paymentGateOpen: Boolean
            get() = bound && callbackRegistered && ready && terminalDataOk && !unfinishedOperation && !paymentInFlight

        companion object {
            const val STATE_READY = 0
            const val STATE_UNFINISHED_OPERATION = 2
        }
    }

    data class SafeTransactionResult(
        val code: Int,
        val message: String?,
        val approved: Boolean?,
        val rrn: String?,
        val authCode: String?,
        val amount: String?,
        val currencyCode: String?,
        val terminalId: String?,
        val receiptNumber: String?,
        val transactionId: String?
    ) {
        val approvedSuccessfully: Boolean get() = code == 0 && approved == true
    }

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val paymentInFlight = AtomicBoolean(false)

    @Volatile private var service: ISmartSkyPos? = null
    @Volatile private var registered = false
    @Volatile private var lastTerminalData: TerminalData? = null
    @Volatile private var snapshot = Snapshot()

    private val stateCallback = object : StateCallback.Stub() {
        override fun onStateChanged(state: Int, message: String?) {
            log("StateCallback: state=$state (${stateName(state)}), message=${safeText(message)}")
            lastTerminalData = null
            updateSnapshot {
                copy(
                    state = state,
                    stateMessage = message,
                    terminalDataCode = null,
                    terminalDataMessage = null,
                    merchantId = null,
                    serialNumber = null,
                    defaultTerminalId = null,
                    terminals = emptyList()
                )
            }
            if (state == Snapshot.STATE_READY) {
                requestTerminalData()
            } else if (state == Snapshot.STATE_UNFINISHED_OPERATION) {
                log("PAYMENT_GATE=CLOSED: SmartSkyPOS reports unfinished operation")
            }
        }
    }

    private val transactionCallback = object : TransactionCallback.Stub() {
        override fun onStateChanged(state: Int, message: String?) {
            log("TransactionCallback.state=$state, message=${safeText(message)}")
        }

        override fun onQrReading(qrId: String?, qrPayload: String?) {
            log("TransactionCallback.qr: id=${safeText(qrId)}, payload=<redacted>")
        }

        override fun reserved3() {
            log("TransactionCallback.reserved3 invoked by service; ignored")
        }

        override fun onOperationNameChanged(operationName: String?) {
            log("TransactionCallback.operation=${safeText(operationName)}")
        }

        override fun onRequestPassword(prompt: String?): String {
            // Diagnostic build intentionally never stores or provides a merchant/service password.
            log("TransactionCallback.password requested (${safeText(prompt)}); returning empty value")
            return ""
        }
    }

    private val connector = SmartSkyPosConnector(
        context = appContext,
        onConnected = { remote ->
            service = remote
            updateSnapshot { copy(bound = true) }
            log("BIND_OK descriptor=${SmartSkyPosConnector.BINDER_DESCRIPTOR}")
            executor.execute { registerCallbackAndProbe(remote) }
        },
        onDisconnected = {
            service = null
            registered = false
            lastTerminalData = null
            paymentInFlight.set(false)
            updateSnapshot {
                Snapshot(
                    bound = false,
                    callbackRegistered = false,
                    state = null,
                    stateMessage = "Service disconnected"
                )
            }
            log("BIND_DISCONNECTED")
        }
    )

    fun bindAndProbe(): Boolean {
        log("BIND_REQUEST action=${SmartSkyPosConnector.ACTION}, package=${SmartSkyPosConnector.PACKAGE}")
        val ok = try {
            connector.bind()
        } catch (e: Exception) {
            log("BIND_EXCEPTION ${e.javaClass.simpleName}: ${safeText(e.message)}")
            false
        }
        if (!ok) {
            updateSnapshot { Snapshot() }
            log("BIND_FAILED")
        }
        return ok
    }

    fun probeAgain() {
        val remote = service
        if (remote == null) {
            log("PROBE_SKIPPED: service is not bound")
            bindAndProbe()
            return
        }
        executor.execute { probe(remote) }
    }

    /**
     * Controlled diagnostic payment.
     * There is deliberately no auto-retry: an uncertain financial result must be investigated,
     * not repeated.
     */
    fun paymentTest(amountText: String, terminalId: String, currencyCode: String) {
        val gateSnapshot = snapshot
        if (!gateSnapshot.paymentGateOpen) {
            log("PAYMENT_BLOCKED: gate is closed")
            return
        }

        val tid = terminalId.trim()
        val currency = currencyCode.trim()
        val terminal = gateSnapshot.terminals.firstOrNull { it.id == tid }
        if (terminal == null) {
            log("PAYMENT_BLOCKED: terminalId is not present in current TerminalData")
            return
        }
        val currencyInfo = terminal.currencies.firstOrNull { it.code.equals(currency, ignoreCase = true) }
        if (currency.isBlank() || currencyInfo == null) {
            log("PAYMENT_BLOCKED: currencyCode is not advertised for selected terminal")
            return
        }

        val amount = try {
            val raw = BigDecimal(amountText.trim().replace(',', '.'))
            raw.setScale(currencyInfo.exponent.coerceAtLeast(0), RoundingMode.UNNECESSARY)
        } catch (_: Exception) {
            log(
                "PAYMENT_BLOCKED: amount has invalid precision for currency " +
                    "${currencyInfo.code} (exponent=${currencyInfo.exponent})"
            )
            return
        }
        if (amount <= BigDecimal.ZERO) {
            log("PAYMENT_BLOCKED: amount must be > 0")
            return
        }
        if (!paymentInFlight.compareAndSet(false, true)) {
            log("PAYMENT_BLOCKED: another payment call is already in flight")
            return
        }

        updateSnapshot { copy(paymentInFlight = true) }
        log("PAYMENT_REQUEST amount=$amount, terminalId=$tid, currency=$currency")
        executor.execute {
            val remote = service
            if (remote == null) {
                finishPaymentInflight()
                log("PAYMENT_FAILED_BEFORE_CALL: service disconnected")
                return@execute
            }

            try {
                val stateNow = remote.state
                if (stateNow != Snapshot.STATE_READY) {
                    log("PAYMENT_ABORTED_BEFORE_CALL: current state=$stateNow (${stateName(stateNow)})")
                    return@execute
                }

                val freshData = remote.terminalData
                if (freshData.code != 0) {
                    log("PAYMENT_ABORTED_BEFORE_CALL: fresh TerminalData code=${freshData.code}")
                    return@execute
                }
                val freshTerminal = freshData.terminals.orEmpty().map { it.toInfo() }.firstOrNull { it.id == tid }
                val freshCurrency = freshTerminal?.currencies?.firstOrNull { it.code.equals(currency, ignoreCase = true) }
                if (freshTerminal == null || freshCurrency == null) {
                    log("PAYMENT_ABORTED_BEFORE_CALL: selected terminal/currency disappeared from fresh TerminalData")
                    return@execute
                }

                val freshAmount = try {
                    amount.setScale(freshCurrency.exponent.coerceAtLeast(0), RoundingMode.UNNECESSARY)
                } catch (_: Exception) {
                    log(
                        "PAYMENT_ABORTED_BEFORE_CALL: amount precision no longer matches fresh currency exponent=" +
                            freshCurrency.exponent
                    )
                    return@execute
                }

                val params = TransactionParams(freshAmount).apply {
                    setTerminalId(tid)
                    setCurrencyCode(freshCurrency.code)
                }
                val result = remote.payment(params, transactionCallback)
                val safe = result.toSafeResult()
                log(
                    "PAYMENT_RESULT code=${safe.code}, approved=${safe.approved}, " +
                        "message=${safeText(safe.message)}, rrn=${safeText(safe.rrn)}, " +
                        "authCode=${safeText(safe.authCode)}, amount=${safe.amount}, currency=${safe.currencyCode}, " +
                        "terminalId=${safe.terminalId}, receipt=${safe.receiptNumber}, id=${safe.transactionId}"
                )
                post { listener.onPaymentFinished(safe) }
            } catch (e: RemoteException) {
                log("PAYMENT_REMOTE_EXCEPTION ${safeText(e.message)}")
            } catch (e: Exception) {
                log("PAYMENT_EXCEPTION ${e.javaClass.simpleName}: ${safeText(e.message)}")
            } finally {
                finishPaymentInflight()
            }
        }
    }

    fun close() {
        val remote = service
        if (remote != null && registered) {
            try {
                remote.unregisterStateCallback(stateCallback)
                log("CALLBACK_UNREGISTERED")
            } catch (e: Exception) {
                log("CALLBACK_UNREGISTER_FAILED ${e.javaClass.simpleName}: ${safeText(e.message)}")
            }
        }
        registered = false
        service = null
        lastTerminalData = null
        paymentInFlight.set(false)
        try {
            connector.unbind()
        } catch (_: Exception) {
        }
        executor.shutdownNow()
        updateSnapshot { Snapshot() }
        log("BIND_CLOSED")
    }

    private fun registerCallbackAndProbe(remote: ISmartSkyPos) {
        try {
            remote.registerStateCallback(stateCallback)
            registered = true
            updateSnapshot { copy(callbackRegistered = true) }
            log("CALLBACK_REGISTERED")
        } catch (e: Exception) {
            registered = false
            updateSnapshot { copy(callbackRegistered = false) }
            log("CALLBACK_REGISTER_FAILED ${e.javaClass.simpleName}: ${safeText(e.message)}")
            return
        }
        probe(remote)
    }

    private fun probe(remote: ISmartSkyPos) {
        try {
            val state = remote.state
            log("GET_STATE=$state (${stateName(state)})")
            lastTerminalData = null
            updateSnapshot {
                copy(
                    state = state,
                    stateMessage = null,
                    terminalDataCode = null,
                    terminalDataMessage = null,
                    merchantId = null,
                    serialNumber = null,
                    defaultTerminalId = null,
                    terminals = emptyList()
                )
            }

            when (state) {
                Snapshot.STATE_READY -> requestTerminalData(remote)
                Snapshot.STATE_UNFINISHED_OPERATION ->
                    log("PAYMENT_GATE=CLOSED: unfinished operation must be resolved before a new payment")
                else ->
                    log("PAYMENT_GATE=CLOSED: waiting for READY(0); current state=$state")
            }
        } catch (e: RemoteException) {
            log("GET_STATE_REMOTE_EXCEPTION ${safeText(e.message)}")
        } catch (e: Exception) {
            log("GET_STATE_EXCEPTION ${e.javaClass.simpleName}: ${safeText(e.message)}")
        }
    }

    private fun requestTerminalData(remoteOverride: ISmartSkyPos? = null) {
        executor.execute {
            val remote = remoteOverride ?: service
            if (remote == null) {
                log("GET_TERMINAL_DATA_SKIPPED: service disconnected")
                return@execute
            }
            val currentState = snapshot.state
            if (currentState != Snapshot.STATE_READY) {
                log("GET_TERMINAL_DATA_SKIPPED: state is ${currentState ?: "unknown"}, not READY(0)")
                return@execute
            }
            try {
                val data = remote.terminalData
                lastTerminalData = data
                val terminals = data.terminals.orEmpty().map { it.toInfo() }
                updateSnapshot {
                    copy(
                        terminalDataCode = data.code,
                        terminalDataMessage = data.message,
                        merchantId = data.merchantId,
                        serialNumber = data.serialNumber,
                        defaultTerminalId = data.terminalId,
                        terminals = terminals
                    )
                }
                log(
                    "TERMINAL_DATA code=${data.code}, message=${safeText(data.message)}, " +
                        "merchantId=${safeText(data.merchantId)}, serial=${safeText(data.serialNumber)}, " +
                        "defaultTid=${safeText(data.terminalId)}, terminals=${terminals.size}"
                )
                terminals.forEach { terminal ->
                    val currencyList = terminal.currencies.joinToString(",") { it.code }
                    val operationList = terminal.operations.joinToString(",") {
                        listOf(it.name, it.type, it.transactionType).filter { value -> value.isNotBlank() }.joinToString("/")
                    }
                    log(
                        "TERMINAL id=${safeText(terminal.id)}, name=${safeText(terminal.name)}, " +
                            "operations=[$operationList], currencies=[$currencyList]"
                    )
                }
                if (data.code == 0 && terminals.isNotEmpty()) {
                    log("TERMINAL_DATA_OK")
                    log("PAYMENT_GATE=OPEN_FOR_EXPLICIT_DIAGNOSTIC_CALL")
                } else {
                    log("PAYMENT_GATE=CLOSED: TerminalData is not usable")
                }
            } catch (e: RemoteException) {
                log("GET_TERMINAL_DATA_REMOTE_EXCEPTION ${safeText(e.message)}")
            } catch (e: Exception) {
                log("GET_TERMINAL_DATA_EXCEPTION ${e.javaClass.simpleName}: ${safeText(e.message)}")
            }
        }
    }

    private fun finishPaymentInflight() {
        paymentInFlight.set(false)
        updateSnapshot { copy(paymentInFlight = false) }
    }

    private fun updateSnapshot(block: Snapshot.() -> Snapshot) {
        snapshot = snapshot.block()
        val copy = snapshot
        post { listener.onSnapshot(copy) }
    }

    private fun log(message: String) {
        Log.i(TAG, message)
        post { listener.onDiagnosticLine(message) }
    }

    private fun post(block: () -> Unit) {
        mainHandler.post(block)
    }

    private fun Terminal.toInfo(): TerminalInfo {
        return TerminalInfo(
            id = terminalId.orEmpty(),
            name = terminalName.orEmpty(),
            operations = operations.orEmpty().map { it.toInfo() }
        )
    }

    private fun Operation.toInfo(): OperationInfo {
        return OperationInfo(
            name = name.orEmpty(),
            type = type.orEmpty(),
            transactionType = transactionType.orEmpty(),
            currencies = currencies.orEmpty().map { it.toInfo() }
        )
    }

    private fun Currency.toInfo(): CurrencyInfo {
        return CurrencyInfo(
            code = currencyCode.orEmpty(),
            caption = currencyCaption.orEmpty(),
            exponent = currencyExponent
        )
    }

    private fun TransactionResult.toSafeResult(): SafeTransactionResult {
        // Deliberately do NOT expose PAN, cardholder, expiry, CVM/EMV blobs or receipt bodies to logs.
        return SafeTransactionResult(
            code = code,
            message = message,
            approved = isApproved,
            rrn = rrn,
            authCode = authCode,
            amount = amount?.toPlainString(),
            currencyCode = currencyCode,
            terminalId = terminalId,
            receiptNumber = receiptNumberAsString,
            transactionId = id
        )
    }

    private fun stateName(state: Int): String = when (state) {
        Snapshot.STATE_READY -> "READY"
        Snapshot.STATE_UNFINISHED_OPERATION -> "UNFINISHED_OPERATION"
        else -> "STATE_$state"
    }

    private fun safeText(value: String?): String {
        if (value.isNullOrBlank()) return "-"
        return value.replace('\n', ' ').replace('\r', ' ').take(240)
    }

    companion object {
        const val TAG = "SmartSkyPOSDiag"
    }
}
