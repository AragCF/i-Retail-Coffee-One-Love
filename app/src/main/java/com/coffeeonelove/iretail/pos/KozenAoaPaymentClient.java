package com.coffeeonelove.iretail.pos;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.io.IOException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.Date;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Production-side JL22 client for the Kozen AOA payment bridge.
 *
 * Safety invariants:
 *  - PAYMENT is emitted only after PING/INFO, READY(0), and fresh TerminalData checks;
 *  - one local attempt gets one requestId and one PAYMENT write only;
 *  - after PAYMENT has been attempted, transport uncertainty is never retried as a new payment;
 *  - an unresolved request is persisted on JL22 and recovered with GET_PAYMENT_STATUS first;
 *  - APPROVED is accepted only when the bridge itself reports status=APPROVED;
 *  - this client never sends cancel/refund/reconciliation commands.
 */
public final class KozenAoaPaymentClient {
    private static final String TAG = "IretailKozenClient";
    private static final String ACTION_USB_PERMISSION = "com.coffeeonelove.iretail.KOZEN_USB_PERMISSION";

    private static final int KOZEN_VID = 0x0e8d;
    private static final int KOZEN_PID = 0x201c;
    private static final int GOOGLE_VID = 0x18d1;

    private static final int AOA_GET_PROTOCOL = 51;
    private static final int AOA_SEND_STRING = 52;
    private static final int AOA_START = 53;

    private static final String ACCESSORY_MANUFACTURER = "Coffee One Love";
    private static final String ACCESSORY_MODEL = "iRetail Kozen Payment Bridge";
    private static final String ACCESSORY_DESCRIPTION = "i-Retail USB payment bridge";
    private static final String ACCESSORY_VERSION = "0.6";
    private static final String ACCESSORY_URI = "https://thesystem.pro/";
    private static final String ACCESSORY_SERIAL = "iretail-kozen-production";

    private static final String CURRENCY = "643";
    private static final String PREFS = "iretail_jl22_kozen_payment_v1";
    private static final String PREF_UNRESOLVED_ID = "unresolved_request_id";
    private static final String PREF_UNRESOLVED_AMOUNT = "unresolved_amount";
    private static final String PREF_UNRESOLVED_TID = "unresolved_tid";
    private static final String PREF_UNRESOLVED_SINCE = "unresolved_since";

    private final Context context;
    private final UsbManager usbManager;
    private final PendingIntent permissionIntent;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicBoolean busy = new AtomicBoolean(false);
    private final AtomicInteger wireSequence = new AtomicInteger(4100);
    private final Object permissionLock = new Object();
    private final Object linkLock = new Object();

    private volatile boolean shutdown;
    private volatile boolean receiverRegistered;
    private volatile String permissionDeviceName;
    private volatile boolean permissionAnswered;
    private volatile boolean permissionGranted;

    private UsbDeviceConnection linkConnection;
    private UsbInterface linkInterface;
    private UsbEndpoint linkIn;
    private UsbEndpoint linkOut;
    private final StringBuilder rxBuffer = new StringBuilder();
    private final ArrayDeque<String> rxLines = new ArrayDeque<>();

    public interface Listener {
        void onStatus(String message);
        void onResult(PaymentResult result);
    }

    public interface PreflightListener {
        void onResult(boolean ready, String code, String message);
    }

    public interface ReadOnlyRecoveryListener {
        void onResult(ReadOnlyRecoveryResult result);
    }

    public static final class ReadOnlyRecoveryResult {
        public final boolean ok;
        public final String code;
        public final String approved;
        public final String message;
        public final String rc;
        public final String amount;
        public final boolean receiptPresent;
        public final boolean transactionIdPresent;
        public final boolean targeted;

        private ReadOnlyRecoveryResult(boolean ok, String code, String approved, String message,
                                       String rc, String amount, boolean receiptPresent,
                                       boolean transactionIdPresent, boolean targeted) {
            this.ok = ok;
            this.code = tokenOrDash(code);
            this.approved = tokenOrDash(approved);
            this.message = tokenOrDash(message).replace('_', ' ');
            this.rc = tokenOrDash(rc);
            this.amount = tokenOrDash(amount);
            this.receiptPresent = receiptPresent;
            this.transactionIdPresent = transactionIdPresent;
            this.targeted = targeted;
        }

        static ReadOnlyRecoveryResult failed(String code, String message) {
            return new ReadOnlyRecoveryResult(false, code, "null", message, "-", "-", false, false, false);
        }

        static ReadOnlyRecoveryResult fromLine(String line, boolean targeted) {
            String receipt = value(line, "receipt");
            String transactionId = value(line, "transactionId");
            return new ReadOnlyRecoveryResult(
                    true,
                    value(line, "code"),
                    value(line, "approved"),
                    value(line, "message"),
                    value(line, "rc"),
                    value(line, "amount"),
                    receipt != null && !receipt.isEmpty() && !"-".equals(receipt),
                    transactionId != null && !transactionId.isEmpty() && !"-".equals(transactionId),
                    targeted
            );
        }
    }

    public static final class PaymentResult {
        public final String requestId;
        public final String status;
        public final String code;
        public final String approved;
        public final String message;
        public final String rc;
        public final String rrn;
        public final String receipt;
        public final String terminalId;
        public final String amount;
        public final String rawLine;

        PaymentResult(String requestId, String status, String code, String approved,
                      String message, String rc, String rrn, String receipt,
                      String terminalId, String amount, String rawLine) {
            this.requestId = tokenOrDash(requestId);
            this.status = tokenOrDash(status);
            this.code = tokenOrDash(code);
            this.approved = tokenOrDash(approved);
            this.message = tokenOrDash(message).replace('_', ' ');
            this.rc = tokenOrDash(rc);
            this.rrn = tokenOrDash(rrn);
            this.receipt = tokenOrDash(receipt);
            this.terminalId = tokenOrDash(terminalId);
            this.amount = tokenOrDash(amount);
            this.rawLine = rawLine == null ? "" : rawLine;
        }

        public boolean isApproved() { return "APPROVED".equals(status); }
        public boolean isDeclined() { return "DECLINED".equals(status); }
        public boolean isUncertain() {
            return status.startsWith("UNCERTAIN") || "UNKNOWN".equals(status) || "STARTED".equals(status);
        }
        public boolean isFinal() {
            return "APPROVED".equals(status) || "DECLINED".equals(status) ||
                    "FAILED".equals(status) || "BLOCKED".equals(status);
        }

        public String userMessage() {
            if (isApproved()) return "Оплата одобрена";
            if (isDeclined()) return message.equals("-") ? "Оплата отклонена" : message;
            if (isUncertain()) return "Результат оплаты не определён. Повторять платёж нельзя.";
            if (!message.equals("-")) return message;
            if (!code.equals("-")) return "Ошибка оплаты: " + code;
            return "Операция оплаты завершена без подтверждения";
        }

        static PaymentResult local(String requestId, String status, String code, String message) {
            return new PaymentResult(requestId, status, code, "null", message,
                    "-", "-", "-", "-", "-", "");
        }

        static PaymentResult fromLine(String requestId, String line) {
            if (line == null || line.trim().isEmpty()) {
                return local(requestId, "UNCERTAIN", "NO_RESPONSE", "Нет ответа от Kozen");
            }
            return new PaymentResult(
                    requestId,
                    value(line, "status"),
                    value(line, "code"),
                    value(line, "approved"),
                    value(line, "message"),
                    value(line, "rc"),
                    value(line, "rrn"),
                    value(line, "receipt"),
                    value(line, "terminalId"),
                    value(line, "amount"),
                    line
            );
        }
    }

    public KozenAoaPaymentClient(Context context) {
        this.context = context.getApplicationContext();
        this.usbManager = (UsbManager) this.context.getSystemService(Context.USB_SERVICE);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags |= PendingIntent.FLAG_IMMUTABLE;
        permissionIntent = PendingIntent.getBroadcast(
                this.context, 0,
                new Intent(ACTION_USB_PERMISSION).setPackage(this.context.getPackageName()),
                flags
        );
        registerPermissionReceiver();
    }

    /**
     * Read-only readiness check for the controlled payment test.
     *
     * It opens and keeps the same AOA link that the following payment can reuse.
     * Only PING, INFO, GET_STATE and GET_TERMINAL_DATA are sent.
     * PAYMENT is never sent from this method.
     */
    public void preflight(PreflightListener listener) {
        if (listener == null) return;
        if (shutdown) {
            main.post(() -> listener.onResult(false, "CLIENT_SHUTDOWN", "Платёжный клиент остановлен"));
            return;
        }
        if (hasUnresolvedPayment()) {
            main.post(() -> listener.onResult(false, "PREVIOUS_UNRESOLVED", "Есть незавершённая предыдущая оплата"));
            return;
        }
        if (!busy.compareAndSet(false, true)) {
            main.post(() -> listener.onResult(false, "LOCAL_BUSY", "Платёжный клиент занят"));
            return;
        }

        executor.execute(() -> {
            boolean ready = false;
            String code = "UNKNOWN";
            String message = "Платёжный маршрут не готов";
            Exception lastError = null;

            for (int attempt = 1; attempt <= 6 && !shutdown; attempt++) {
                try {
                    ensureLink();
                    verifyBridge();

                    String state = requestResponse("GET_STATE " + nextWireId(), "STATE ", 12000L);
                    if (!"0".equals(value(state, "code")) || !"0".equals(value(state, "state"))) {
                        throw new IOException("STATE_NOT_READY");
                    }

                    String terminalData = requestResponse("GET_TERMINAL_DATA " + nextWireId(), "TERMINAL_DATA ", 15000L);
                    String tid = value(terminalData, "paymentTid");
                    boolean routeOk = "0".equals(value(terminalData, "code")) &&
                            "true".equalsIgnoreCase(value(terminalData, "payment")) &&
                            "00".equals(value(terminalData, "paymentType")) &&
                            "payment".equalsIgnoreCase(value(terminalData, "transactionType")) &&
                            containsCsvValue(value(terminalData, "currencies"), CURRENCY) &&
                            tid != null && !tid.isEmpty() && !"-".equals(tid);
                    if (!routeOk) throw new IOException("FRESH_ROUTE_NOT_FOUND");

                    ready = true;
                    code = "READY";
                    message = "Kozen / SmartSkyPOS готов к одной оплате";
                    Log.i(TAG,
                            "PREFLIGHT_OK attempt=" + attempt +
                            " bridge=0.5.2 protocol=4 state=0 payment=true currency643=true " +
                            "tidPresent=true noPaymentSent=true linkKeptOpen=true");
                    break;
                } catch (Exception e) {
                    lastError = e;
                    code = safe(e.getMessage());
                    Log.w(TAG,
                            "PREFLIGHT_WARMUP_RETRY attempt=" + attempt +
                            " code=" + code + " noPaymentSent=true");
                    if (attempt >= 6 || !isPreflightWarmupRetryable(code)) break;
                    try {
                        Thread.sleep(1200L);
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                        lastError = interrupted;
                        code = "INTERRUPTED";
                        break;
                    }
                }
            }

            if (!ready) {
                if (lastError != null) code = safe(lastError.getMessage());
                message = "Платёжный маршрут Kozen не готов";
                Log.e(TAG, "PREFLIGHT_FAILED code=" + code + " noPaymentSent=true");
                closeLink();
            }

            busy.set(false);
            final boolean resultReady = ready;
            final String resultCode = code;
            final String resultMessage = message;
            main.post(() -> listener.onResult(resultReady, resultCode, resultMessage));
        });
    }

    private static boolean isPreflightWarmupRetryable(String code) {
        if (code == null) return false;
        return code.startsWith("WRITE_INCOMPLETE_PING_") ||
                code.startsWith("TIMEOUT_PING") ||
                code.startsWith("BAD_PONG") ||
                code.startsWith("LINK_NOT_OPEN") ||
                code.startsWith("AOA_") ||
                code.startsWith("USB_PERMISSION_") ||
                code.startsWith("KOZEN_NOT_FOUND");
    }

    /**
     * Read the latest SmartSkyPOS transaction through the already installed production bridge.
     * This path is read-only: GET_STATE, GET_TERMINAL_DATA, GET_LAST_TRANSACTION and,
     * when a receipt exists, GET_TRANSACTION. It never emits a financial command.
     */
    public void readLastTransaction(ReadOnlyRecoveryListener listener) {
        if (listener == null) return;
        if (shutdown) {
            main.post(() -> listener.onResult(ReadOnlyRecoveryResult.failed(
                    "CLIENT_SHUTDOWN", "Платёжный клиент остановлен")));
            return;
        }
        if (!busy.compareAndSet(false, true)) {
            main.post(() -> listener.onResult(ReadOnlyRecoveryResult.failed(
                    "LOCAL_BUSY", "Платёжный клиент занят")));
            return;
        }

        executor.execute(() -> {
            ReadOnlyRecoveryResult result = null;
            Exception lastError = null;

            for (int attempt = 1; attempt <= 6 && !shutdown; attempt++) {
                try {
                    ensureLink();
                    verifyBridge();

                    String state = requestResponse("GET_STATE " + nextWireId(), "STATE ", 12000L);
                    if (!"0".equals(value(state, "code")) || !"0".equals(value(state, "state"))) {
                        throw new IOException("STATE_NOT_READY");
                    }

                    String terminalData = requestResponse(
                            "GET_TERMINAL_DATA " + nextWireId(), "TERMINAL_DATA ", 15000L);
                    String tid = value(terminalData, "paymentTid");
                    boolean routeOk = "0".equals(value(terminalData, "code")) &&
                            "true".equalsIgnoreCase(value(terminalData, "payment")) &&
                            tid != null && !tid.isEmpty() && !"-".equals(tid);
                    if (!routeOk) throw new IOException("FRESH_ROUTE_NOT_FOUND");

                    String lastId = nextWireId();
                    String last = requestResponse(
                            "GET_LAST_TRANSACTION " + lastId + " terminalId=" + tid,
                            "LAST_TRANSACTION " + lastId, 15000L);
                    String lastCode = value(last, "code");
                    if ("EXCEPTION".equals(lastCode) || (lastCode != null && lastCode.startsWith("BAD_"))) {
                        throw new IOException("LAST_TRANSACTION_" + lastCode);
                    }

                    String selected = last;
                    boolean targeted = false;
                    String receipt = value(last, "receipt");
                    if (receipt != null && !receipt.isEmpty() && !"-".equals(receipt)) {
                        String targetId = nextWireId();
                        String target = requestResponse(
                                "GET_TRANSACTION " + targetId + " terminalId=" + tid +
                                        " receiptNumber=" + receipt,
                                "TRANSACTION " + targetId, 15000L);
                        String targetCode = value(target, "code");
                        if (!"EXCEPTION".equals(targetCode) &&
                                (targetCode == null || !targetCode.startsWith("BAD_"))) {
                            selected = target;
                            targeted = true;
                        }
                    }

                    result = ReadOnlyRecoveryResult.fromLine(selected, targeted);
                    Log.i(TAG,
                            "READ_ONLY_RECOVERY_OK attempt=" + attempt +
                            " code=" + result.code +
                            " approved=" + result.approved +
                            " rc=" + result.rc +
                            " amount=" + result.amount +
                            " receiptPresent=" + result.receiptPresent +
                            " transactionIdPresent=" + result.transactionIdPresent +
                            " targeted=" + result.targeted +
                            " noFinancialCommands=true");
                    break;
                } catch (Exception e) {
                    lastError = e;
                    String code = safe(e.getMessage());
                    Log.w(TAG,
                            "READ_ONLY_RECOVERY_RETRY attempt=" + attempt +
                            " code=" + code + " noFinancialCommands=true");
                    if (attempt >= 6 || !isPreflightWarmupRetryable(code)) break;
                    closeLink();
                    try {
                        Thread.sleep(1200L);
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                        lastError = interrupted;
                        break;
                    }
                }
            }

            if (result == null) {
                String code = lastError == null ? "UNKNOWN" : safe(lastError.getMessage());
                result = ReadOnlyRecoveryResult.failed(code, "Не удалось прочитать последнюю транзакцию");
                Log.e(TAG, "READ_ONLY_RECOVERY_FAILED code=" + code + " noFinancialCommands=true");
                closeLink();
            }

            busy.set(false);
            final ReadOnlyRecoveryResult finalResult = result;
            main.post(() -> listener.onResult(finalResult));
        });
    }

    /**
     * Start one real card payment for the supplied ruble amount.
     * The amount is normalized to two decimals. This method never retries PAYMENT.
     */
    public void startPayment(String amountRub, Listener listener) {
        if (listener == null) return;
        if (shutdown) {
            deliverResult(listener, PaymentResult.local("-", "FAILED", "CLIENT_SHUTDOWN", "Платёжный клиент остановлен"));
            return;
        }
        final String amount;
        try {
            amount = normalizeAmount(amountRub);
        } catch (Exception e) {
            deliverResult(listener, PaymentResult.local("-", "BLOCKED", "BAD_AMOUNT", "Некорректная сумма оплаты"));
            return;
        }
        if (!busy.compareAndSet(false, true)) {
            deliverResult(listener, PaymentResult.local("-", "BLOCKED", "LOCAL_BUSY", "Предыдущая операция ещё не завершена"));
            return;
        }
        executor.execute(() -> {
            try {
                performPaymentOrRecovery(amount, listener);
            } finally {
                busy.set(false);
            }
        });
    }

    public boolean hasUnresolvedPayment() {
        return !prefs().getString(PREF_UNRESOLVED_ID, "").isEmpty();
    }

    public String unresolvedRequestId() {
        return prefs().getString(PREF_UNRESOLVED_ID, "");
    }

    public void shutdown() {
        shutdown = true;
        executor.shutdownNow();
        closeLink();
        if (receiverRegistered) {
            try { context.unregisterReceiver(permissionReceiver); } catch (Exception ignored) {}
            receiverRegistered = false;
        }
    }

    private void performPaymentOrRecovery(String requestedAmount, Listener listener) {
        String unresolved = prefs().getString(PREF_UNRESOLVED_ID, "");
        if (!unresolved.isEmpty()) {
            notifyStatus(listener, "Проверяем незавершённую оплату " + unresolved + "…");
            try {
                ensureLink();
                verifyBridge();
                PaymentResult recovered = queryPaymentStatus(unresolved);
                Log.w(TAG, "UNRESOLVED_STATUS_RECOVERY requestId=" + unresolved + " status=" + recovered.status +
                        " code=" + recovered.code + " noPaymentSent=true");

                // A recovered payment belongs to the PREVIOUS UI attempt. It must never be
                // treated as approval for the order that happens to be on screen now.
                if (recovered.isApproved()) {
                    // Keep the recovery lock. The financial result is known, but the matching
                    // application order must be recovered explicitly before a new charge is allowed.
                    deliverResult(listener, PaymentResult.local(
                            unresolved, "UNCERTAIN_RECOVERY_REQUIRED", "PREVIOUS_APPROVED_ORDER_RECOVERY",
                            "Предыдущая оплата одобрена. Новый платёж заблокирован до восстановления предыдущего заказа."));
                    return;
                }

                if (recovered.isDeclined() || "FAILED".equals(recovered.status) || "BLOCKED".equals(recovered.status)) {
                    // Definite no-charge outcome: unlock future payments, but do not continue the
                    // current click automatically. A second deliberate tap gets a new requestId.
                    clearUnresolved();
                    deliverResult(listener, PaymentResult.local(
                            unresolved, "BLOCKED", "PREVIOUS_RESOLVED_NO_CHARGE",
                            "Предыдущая операция завершена без списания. Текущий платёж не отправлялся; нажмите оплатить ещё раз."));
                    return;
                }

                deliverResult(listener, PaymentResult.local(
                        unresolved, "UNCERTAIN_RECOVERY_REQUIRED", "PREVIOUS_UNRESOLVED",
                        "Предыдущая оплата остаётся неопределённой. Новый платёж заблокирован."));
            } catch (Exception e) {
                closeLink();
                deliverResult(listener, PaymentResult.local(
                        unresolved, "UNCERTAIN_RECOVERY_REQUIRED", "RECOVERY_FAILED",
                        "Не удалось проверить предыдущую оплату: " + safe(e.getMessage())));
            }
            return;
        }

        String requestId = newRequestId();
        boolean paymentWriteAttempted = false;
        try {
            notifyStatus(listener, "Подключаемся к Kozen…");
            ensureLink();
            verifyBridge();

            notifyStatus(listener, "Проверяем готовность SmartSkyPOS…");
            String state = requestResponse("GET_STATE " + nextWireId(), "STATE ", 12000L);
            if (!"0".equals(value(state, "code")) || !"0".equals(value(state, "state"))) {
                deliverResult(listener, PaymentResult.local(requestId, "BLOCKED", "STATE_NOT_READY", "POS-терминал не готов"));
                return;
            }

            String terminalData = requestResponse("GET_TERMINAL_DATA " + nextWireId(), "TERMINAL_DATA ", 15000L);
            String tid = value(terminalData, "paymentTid");
            boolean routeOk = "0".equals(value(terminalData, "code")) &&
                    "true".equalsIgnoreCase(value(terminalData, "payment")) &&
                    "00".equals(value(terminalData, "paymentType")) &&
                    "payment".equalsIgnoreCase(value(terminalData, "transactionType")) &&
                    containsCsvValue(value(terminalData, "currencies"), CURRENCY) &&
                    tid != null && !tid.isEmpty() && !"-".equals(tid);
            if (!routeOk) {
                Log.e(TAG, "FRESH_ROUTE_REJECTED data=" + safe(terminalData));
                deliverResult(listener, PaymentResult.local(requestId, "BLOCKED", "FRESH_ROUTE_NOT_FOUND", "Платёжный маршрут Kozen недоступен"));
                return;
            }

            persistUnresolved(requestId, requestedAmount, tid);
            notifyStatus(listener, "Терминал готов. Приложите карту к Kozen.");

            String command = "PAYMENT " + requestId + " amount=" + requestedAmount +
                    " terminalId=" + tid + " currency=" + CURRENCY;
            paymentWriteAttempted = true;
            int sent = bulkWrite(command + "\n", 3000);
            Log.w(TAG, "PAYMENT_TX_ONCE requestId=" + requestId + " amount=" + requestedAmount +
                    " terminalId=" + tid + " bytes=" + sent + " noAutoRetry=true");
            if (sent != command.getBytes(StandardCharsets.UTF_8).length + 1) {
                throw new IOException("PAYMENT_WRITE_INCOMPLETE_" + sent);
            }

            String resultLine = readMatching("PAYMENT_RESULT " + requestId, 125000L);
            if (resultLine == null) {
                Log.w(TAG, "PAYMENT_RESPONSE_TIMEOUT requestId=" + requestId + " queryingStatusOnly=true noAutoRetry=true");
                PaymentResult statusOnly = queryPaymentStatus(requestId);
                if (statusOnly.isFinal()) {
                    clearUnresolved();
                    deliverResult(listener, statusOnly);
                } else {
                    deliverResult(listener, PaymentResult.local(requestId, "UNCERTAIN", "PAYMENT_TIMEOUT",
                            "Терминал не вернул окончательный результат. Повторять платёж нельзя."));
                }
                return;
            }

            PaymentResult result = PaymentResult.fromLine(requestId, resultLine);
            Log.w(TAG, "PAYMENT_RX requestId=" + requestId + " status=" + result.status +
                    " approved=" + result.approved + " rc=" + result.rc + " rrn=" + result.rrn);
            if (result.isFinal()) clearUnresolved();
            deliverResult(listener, result);
        } catch (Exception e) {
            Log.e(TAG, "PAYMENT_CLIENT_ERROR requestId=" + requestId + " paymentWriteAttempted=" + paymentWriteAttempted +
                    " " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            closeLink();
            if (paymentWriteAttempted) {
                deliverResult(listener, PaymentResult.local(requestId, "UNCERTAIN", "TRANSPORT_AFTER_PAYMENT",
                        "Связь потеряна после отправки платежа. Повторять платёж нельзя."));
            } else {
                clearUnresolvedIfRequest(requestId);
                deliverResult(listener, PaymentResult.local(requestId, "FAILED", "TRANSPORT_BEFORE_PAYMENT",
                        "Не удалось связаться с Kozen: " + safe(e.getMessage())));
            }
        }
    }

    private void verifyBridge() throws Exception {
        String pingId = nextWireId();
        String pong = requestResponse("PING " + pingId, "PONG " + pingId, 12000L);
        if (pong == null || !pong.contains("role=kozen-payment-bridge")) throw new IOException("BAD_PONG");

        String infoId = nextWireId();
        String info = requestResponse("INFO " + infoId, "INFO " + infoId, 12000L);
        if (!"4".equals(value(info, "protocol")) ||
                !"0.5.2".equals(value(info, "bridge")) ||
                !"EXPLICIT_SINGLE_NO_AUTO_RETRY".equals(value(info, "paymentPolicy")) ||
                !info.contains("PAYMENT")) {
            throw new IOException("INCOMPATIBLE_BRIDGE");
        }
    }

    private PaymentResult queryPaymentStatus(String requestId) throws Exception {
        int sent = bulkWrite("GET_PAYMENT_STATUS " + requestId + "\n", 3000);
        if (sent <= 0) throw new IOException("STATUS_WRITE_FAILED");
        String line = readMatching("PAYMENT_RESULT " + requestId, 15000L);
        if (line == null) return PaymentResult.local(requestId, "UNCERTAIN_RECOVERY_REQUIRED", "STATUS_TIMEOUT", "Нет ответа на проверку статуса");
        return PaymentResult.fromLine(requestId, line);
    }

    private String requestResponse(String command, String expectedPrefix, long timeoutMs) throws Exception {
        int sent = bulkWrite(command + "\n", 3000);
        if (sent != command.getBytes(StandardCharsets.UTF_8).length + 1) {
            throw new IOException("WRITE_INCOMPLETE_" + command.split("\\s+")[0] + "_" + sent);
        }
        String line = readMatching(expectedPrefix, timeoutMs);
        if (line == null) throw new IOException("TIMEOUT_" + command.split("\\s+")[0]);
        return line;
    }

    private void ensureLink() throws Exception {
        synchronized (linkLock) {
            if (linkConnection != null && linkIn != null && linkOut != null && linkInterface != null) return;
        }

        UsbDevice aoa = findAoaDevice();
        if (aoa == null) {
            UsbDevice raw = waitForRawKozen(12000L);
            if (raw == null) throw new IOException("KOZEN_NOT_FOUND");
            ensurePermission(raw, 30000L);
            performAoaHandshake(raw);
            aoa = waitForAoaDevice(60000L);
            if (aoa == null) throw new IOException("AOA_REENUMERATION_TIMEOUT");
        }

        ensurePermission(aoa, 30000L);
        openAoaLink(aoa);
    }

    private UsbDevice waitForRawKozen(long timeoutMs) throws InterruptedException {
        long deadline = System.currentTimeMillis() + timeoutMs;
        while (!shutdown && System.currentTimeMillis() < deadline) {
            UsbDevice d = findRawKozen();
            if (d != null) return d;
            Thread.sleep(250L);
        }
        return null;
    }

    private UsbDevice waitForAoaDevice(long timeoutMs) throws InterruptedException {
        long deadline = System.currentTimeMillis() + timeoutMs;
        while (!shutdown && System.currentTimeMillis() < deadline) {
            UsbDevice d = findAoaDevice();
            if (d != null) return d;
            Thread.sleep(250L);
        }
        return null;
    }

    private void performAoaHandshake(UsbDevice raw) throws Exception {
        UsbDeviceConnection connection = usbManager.openDevice(raw);
        if (connection == null) throw new IOException("RAW_OPEN_FAILED");
        try {
            byte[] protocol = new byte[2];
            int n = connection.controlTransfer(0xC0, AOA_GET_PROTOCOL, 0, 0, protocol, protocol.length, 2000);
            if (n != 2) throw new IOException("AOA_GET_PROTOCOL_" + n);
            int version = (protocol[0] & 0xff) | ((protocol[1] & 0xff) << 8);
            if (version < 1) throw new IOException("AOA_PROTOCOL_" + version);
            sendAccessoryString(connection, 0, ACCESSORY_MANUFACTURER);
            sendAccessoryString(connection, 1, ACCESSORY_MODEL);
            sendAccessoryString(connection, 2, ACCESSORY_DESCRIPTION);
            sendAccessoryString(connection, 3, ACCESSORY_VERSION);
            sendAccessoryString(connection, 4, ACCESSORY_URI);
            sendAccessoryString(connection, 5, ACCESSORY_SERIAL);
            int rc = connection.controlTransfer(0x40, AOA_START, 0, 0, null, 0, 2000);
            if (rc < 0) throw new IOException("AOA_START_" + rc);
            Log.i(TAG, "AOA_START_OK protocol=" + version);
        } finally {
            connection.close();
        }
    }

    private void sendAccessoryString(UsbDeviceConnection connection, int index, String value) throws IOException {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        byte[] zero = new byte[bytes.length + 1];
        System.arraycopy(bytes, 0, zero, 0, bytes.length);
        int rc = connection.controlTransfer(0x40, AOA_SEND_STRING, 0, index, zero, zero.length, 2000);
        if (rc < 0) throw new IOException("AOA_STRING_" + index + "_" + rc);
    }

    private void openAoaLink(UsbDevice device) throws Exception {
        UsbInterface selected = null;
        UsbEndpoint in = null;
        UsbEndpoint out = null;
        for (int i = 0; i < device.getInterfaceCount(); i++) {
            UsbInterface candidate = device.getInterface(i);
            UsbEndpoint candidateIn = null;
            UsbEndpoint candidateOut = null;
            for (int e = 0; e < candidate.getEndpointCount(); e++) {
                UsbEndpoint ep = candidate.getEndpoint(e);
                if (ep.getType() != UsbConstants.USB_ENDPOINT_XFER_BULK) continue;
                if (ep.getDirection() == UsbConstants.USB_DIR_IN) candidateIn = ep;
                else if (ep.getDirection() == UsbConstants.USB_DIR_OUT) candidateOut = ep;
            }
            if (candidateIn != null && candidateOut != null) {
                selected = candidate;
                in = candidateIn;
                out = candidateOut;
                break;
            }
        }
        if (selected == null || in == null || out == null) throw new IOException("AOA_ENDPOINTS_MISSING");

        UsbDeviceConnection connection = usbManager.openDevice(device);
        if (connection == null) throw new IOException("AOA_OPEN_FAILED");
        if (!connection.claimInterface(selected, true)) {
            connection.close();
            throw new IOException("AOA_CLAIM_FAILED");
        }
        synchronized (linkLock) {
            closeLinkLocked();
            linkConnection = connection;
            linkInterface = selected;
            linkIn = in;
            linkOut = out;
            rxBuffer.setLength(0);
            rxLines.clear();
        }
        Log.i(TAG, "AOA_LINK_READY device=" + device.getVendorId() + ":" + device.getProductId() +
                " interface=" + selected.getId());
    }

    private int bulkWrite(String text, int timeoutMs) throws IOException {
        synchronized (linkLock) {
            if (linkConnection == null || linkOut == null) throw new IOException("LINK_NOT_OPEN");
            byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
            return linkConnection.bulkTransfer(linkOut, bytes, bytes.length, timeoutMs);
        }
    }

    private String readMatching(String prefix, long timeoutMs) throws IOException, InterruptedException {
        long deadline = System.currentTimeMillis() + timeoutMs;
        while (!shutdown && System.currentTimeMillis() < deadline) {
            synchronized (linkLock) {
                while (!rxLines.isEmpty()) {
                    String line = rxLines.removeFirst();
                    if (line.startsWith(prefix)) return line;
                    Log.i(TAG, "RX_STALE " + safe(line));
                }
                int newline;
                while ((newline = rxBuffer.indexOf("\n")) >= 0) {
                    String line = rxBuffer.substring(0, newline).replace("\r", "").trim();
                    rxBuffer.delete(0, newline + 1);
                    if (line.isEmpty()) continue;
                    if (line.startsWith(prefix)) return line;
                    rxLines.addLast(line);
                }
                if (linkConnection == null || linkIn == null) throw new IOException("LINK_NOT_OPEN");
                byte[] buffer = new byte[4096];
                int wait = (int) Math.min(1200L, Math.max(1L, deadline - System.currentTimeMillis()));
                int count = linkConnection.bulkTransfer(linkIn, buffer, buffer.length, wait);
                if (count > 0) {
                    rxBuffer.append(new String(buffer, 0, count, StandardCharsets.UTF_8));
                    continue;
                }
            }
            Thread.sleep(15L);
        }
        return null;
    }

    private void ensurePermission(UsbDevice device, long timeoutMs) throws Exception {
        if (usbManager.hasPermission(device)) return;
        synchronized (permissionLock) {
            if (usbManager.hasPermission(device)) return;
            permissionDeviceName = device.getDeviceName();
            permissionAnswered = false;
            permissionGranted = false;
            usbManager.requestPermission(device, permissionIntent);
            long deadline = System.currentTimeMillis() + timeoutMs;
            while (!shutdown && !permissionAnswered && System.currentTimeMillis() < deadline) {
                permissionLock.wait(Math.min(1000L, Math.max(1L, deadline - System.currentTimeMillis())));
            }
            if (!permissionAnswered) throw new IOException("USB_PERMISSION_TIMEOUT");
            if (!permissionGranted) throw new IOException("USB_PERMISSION_DENIED");
        }
    }

    private final BroadcastReceiver permissionReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context ctx, Intent intent) {
            if (!ACTION_USB_PERMISSION.equals(intent.getAction())) return;
            UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
            synchronized (permissionLock) {
                String name = device == null ? null : device.getDeviceName();
                if (permissionDeviceName == null || permissionDeviceName.equals(name)) {
                    permissionGranted = granted;
                    permissionAnswered = true;
                    permissionLock.notifyAll();
                }
            }
            Log.i(TAG, "USB_PERMISSION granted=" + granted + " device=" + deviceSummary(device));
        }
    };

    private void registerPermissionReceiver() {
        IntentFilter filter = new IntentFilter(ACTION_USB_PERMISSION);
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        else context.registerReceiver(permissionReceiver, filter);
        receiverRegistered = true;
    }

    private UsbDevice findRawKozen() {
        for (Map.Entry<String, UsbDevice> entry : usbManager.getDeviceList().entrySet()) {
            UsbDevice d = entry.getValue();
            if (d != null && d.getVendorId() == KOZEN_VID && d.getProductId() == KOZEN_PID) return d;
        }
        return null;
    }

    private UsbDevice findAoaDevice() {
        for (Map.Entry<String, UsbDevice> entry : usbManager.getDeviceList().entrySet()) {
            UsbDevice d = entry.getValue();
            if (d == null || d.getVendorId() != GOOGLE_VID) continue;
            int pid = d.getProductId();
            if (pid >= 0x2d00 && pid <= 0x2d05) return d;
        }
        return null;
    }

    private void persistUnresolved(String requestId, String amount, String tid) {
        prefs().edit()
                .putString(PREF_UNRESOLVED_ID, requestId)
                .putString(PREF_UNRESOLVED_AMOUNT, amount)
                .putString(PREF_UNRESOLVED_TID, tid)
                .putLong(PREF_UNRESOLVED_SINCE, System.currentTimeMillis())
                .apply();
    }

    private void clearUnresolved() {
        prefs().edit()
                .remove(PREF_UNRESOLVED_ID)
                .remove(PREF_UNRESOLVED_AMOUNT)
                .remove(PREF_UNRESOLVED_TID)
                .remove(PREF_UNRESOLVED_SINCE)
                .apply();
    }

    private void clearUnresolvedIfRequest(String requestId) {
        if (requestId.equals(prefs().getString(PREF_UNRESOLVED_ID, ""))) clearUnresolved();
    }

    private android.content.SharedPreferences prefs() {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private void closeLink() {
        synchronized (linkLock) { closeLinkLocked(); }
    }

    private void closeLinkLocked() {
        if (linkConnection != null && linkInterface != null) {
            try { linkConnection.releaseInterface(linkInterface); } catch (Exception ignored) {}
        }
        if (linkConnection != null) {
            try { linkConnection.close(); } catch (Exception ignored) {}
        }
        linkConnection = null;
        linkInterface = null;
        linkIn = null;
        linkOut = null;
        rxBuffer.setLength(0);
        rxLines.clear();
    }

    private void notifyStatus(Listener listener, String message) {
        Log.i(TAG, "STATUS " + safe(message));
        main.post(() -> listener.onStatus(message));
    }

    private void deliverResult(Listener listener, PaymentResult result) {
        main.post(() -> listener.onResult(result));
    }

    private String nextWireId() {
        int value = wireSequence.incrementAndGet();
        if (value > 999999) {
            wireSequence.set(4100);
            value = wireSequence.incrementAndGet();
        }
        return Integer.toString(value);
    }

    private static String newRequestId() {
        String stamp = new SimpleDateFormat("yyyyMMddHHmmss", Locale.US).format(new Date());
        int suffix = (int) (System.nanoTime() & 0xffff);
        return "ui-" + stamp + "-" + String.format(Locale.US, "%04x", suffix);
    }

    private static String normalizeAmount(String raw) {
        BigDecimal value = new BigDecimal(raw == null ? "" : raw.trim().replace(',', '.'));
        value = value.setScale(2, RoundingMode.UNNECESSARY);
        if (value.signum() <= 0 || value.compareTo(new BigDecimal("999999.99")) > 0) {
            throw new IllegalArgumentException("amount range");
        }
        return value.toPlainString();
    }

    private static boolean containsCsvValue(String csv, String expected) {
        if (csv == null) return false;
        for (String part : csv.split(",")) if (expected.equals(part.trim())) return true;
        return false;
    }

    private static String value(String line, String key) {
        if (line == null || key == null) return null;
        String prefix = key + "=";
        for (String part : line.trim().split("\\s+")) {
            if (part.startsWith(prefix)) return part.substring(prefix.length());
        }
        return null;
    }

    private static String tokenOrDash(String value) {
        return value == null || value.trim().isEmpty() ? "-" : value.trim();
    }

    private static String safe(String value) {
        if (value == null) return "-";
        return value.replace('\n', '_').replace('\r', '_').trim();
    }

    private static String deviceSummary(UsbDevice d) {
        if (d == null) return "null";
        return String.format(Locale.US, "%04x:%04x name=%s", d.getVendorId(), d.getProductId(), d.getDeviceName());
    }
}
