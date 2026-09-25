package com.coffeeonelove.iretail.kozenbridge;

import android.app.Service;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.SharedPreferences;
import android.hardware.usb.UsbAccessory;
import android.hardware.usb.UsbManager;
import android.os.Binder;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.Parcel;
import android.os.ParcelFileDescriptor;
import android.os.RemoteException;
import android.util.Log;

import com.skytech.smartskyposlib.Currency;
import com.skytech.smartskyposlib.Operation;
import com.skytech.smartskyposlib.Terminal;
import com.skytech.smartskyposlib.TerminalData;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Hardened Kozen payment bridge for JL22 over Android Open Accessory.
 *
 * Invariants:
 *  - one requestId can invoke payment() at most once;
 *  - PAYMENT is never retried automatically;
 *  - a fresh READY state and fresh TerminalData route are required before payment();
 *  - APPROVED requires both approved=true and an approval bank rc;
 *  - missing/contradictory approval evidence becomes UNCERTAIN, never success;
 *  - transaction-history commands are read-only and omit cardholder/PAN/EMV/slip data.
 */
public class ProductionBridgeService extends Service {
    private static final String TAG = "IretailKozenBridge";
    private static final String BRIDGE_VERSION = "0.5.7";

    private static final String SMARTSKY_ACTION = "com.skytech.smartskypos.ISmartSkyPos";
    private static final String SMARTSKY_PACKAGE = "com.skytech.smartskypos";
    private static final String SMARTSKY_SERVICE = "com.crestwavetech.smartskyposservice.SmartSkyPosService";
    private static final String SMARTSKY_DESCRIPTOR = "com.skytech.smartskyposlib.ISmartSkyPos";
    private static final String TRANSACTION_CALLBACK_DESCRIPTOR = "com.skytech.smartskyposlib.TransactionCallback";

    private static final int TX_GET_STATE = 1;
    private static final int TX_GET_TERMINAL_DATA = 4;
    private static final int TX_PAYMENT = 5;
    private static final int TX_QR_PAYMENT = 19;
    private static final int TX_GET_LAST_TRANSACTION = 20;
    private static final int TX_GET_TRANSACTION = 21;

    private static final String SUPPORTED_CURRENCY = "643";
    private static final boolean LIVE_QR_PAYMENT_ENABLED = false;
    private static final boolean LIVE_QR_GENERATION_PROBE_ENABLED = false;
    private static final String LIVE_QR_PROBE_TOKEN = "LIVE_SBP_QR_1RUB";
    private static final BigDecimal MAX_AMOUNT = new BigDecimal("999999.99");

    private static final String PREFS = "iretail_payment_bridge_v1";
    private static final String PREF_ACTIVE_REQUEST = "active_request";
    private static final String PREF_ACTIVE_SBP_REQUEST = "active_sbp_request";

    private final Object accessoryLock = new Object();
    private final Object paymentLock = new Object();
    private final SbpQrCapture sbpQrCapture = new SbpQrCapture();
    private Thread ioThread;
    private ParcelFileDescriptor parcelFd;

    private volatile IBinder smartSkyBinder;
    private volatile boolean smartSkyBound;
    private volatile boolean smartSkyBindingRequested;

    private final ServiceConnection smartSkyConnection = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder service) {
            smartSkyBinder = service;
            smartSkyBound = true;
            smartSkyBindingRequested = false;
            String descriptor = "-";
            try { descriptor = service == null ? "-" : service.getInterfaceDescriptor(); } catch (Exception ignored) {}
            Log.i(TAG, "SMARTSKY_BOUND component=" + name + " descriptor=" + descriptor);
        }

        @Override public void onServiceDisconnected(ComponentName name) {
            smartSkyBinder = null;
            smartSkyBound = false;
            smartSkyBindingRequested = false;
            Log.w(TAG, "SMARTSKY_DISCONNECTED component=" + name);
        }

        @Override public void onBindingDied(ComponentName name) {
            smartSkyBinder = null;
            smartSkyBound = false;
            smartSkyBindingRequested = false;
            Log.w(TAG, "SMARTSKY_BINDING_DIED component=" + name);
            bindSmartSky();
        }

        @Override public void onNullBinding(ComponentName name) {
            smartSkyBinder = null;
            smartSkyBound = false;
            smartSkyBindingRequested = false;
            Log.e(TAG, "SMARTSKY_NULL_BINDING component=" + name);
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        bindSmartSky();
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        bindSmartSky();
        UsbAccessory accessory = intent == null ? null : intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY);
        if (accessory == null) {
            UsbManager manager = (UsbManager) getSystemService(USB_SERVICE);
            UsbAccessory[] list = manager.getAccessoryList();
            if (list != null && list.length > 0) accessory = list[0];
        }
        if (accessory == null) {
            Log.w(TAG, "SERVICE_NO_ACCESSORY");
            stopSelf(startId);
            return START_NOT_STICKY;
        }

        final UsbAccessory selected = accessory;
        synchronized (accessoryLock) {
            if (ioThread != null && ioThread.isAlive()) {
                Log.i(TAG, "SERVICE_START_DUPLICATE_IGNORED activeThread=true bridge=" + BRIDGE_VERSION);
                return START_NOT_STICKY;
            }
            closeAccessoryLocked();
            ioThread = new Thread(() -> runBridge(selected), "iretail-kozen-production-bridge");
            ioThread.start();
        }
        return START_NOT_STICKY;
    }

    @Override public void onDestroy() {
        synchronized (accessoryLock) { closeAccessoryLocked(); }
        if (smartSkyBound) {
            try { unbindService(smartSkyConnection); } catch (Exception ignored) {}
        }
        smartSkyBinder = null;
        smartSkyBound = false;
        smartSkyBindingRequested = false;
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }

    private void bindSmartSky() {
        if (smartSkyBound && smartSkyBinder != null && smartSkyBinder.isBinderAlive()) return;
        if (smartSkyBindingRequested) return;
        smartSkyBindingRequested = true;
        try {
            Intent intent = new Intent(SMARTSKY_ACTION);
            intent.setComponent(new ComponentName(SMARTSKY_PACKAGE, SMARTSKY_SERVICE));
            boolean ok = bindService(intent, smartSkyConnection, Context.BIND_AUTO_CREATE);
            Log.i(TAG, "SMARTSKY_BIND_REQUEST ok=" + ok);
            if (!ok) {
                smartSkyBindingRequested = false;
                smartSkyBound = false;
                smartSkyBinder = null;
            }
        } catch (Exception e) {
            smartSkyBindingRequested = false;
            smartSkyBound = false;
            smartSkyBinder = null;
            Log.e(TAG, "SMARTSKY_BIND_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
        }
    }

    private void runBridge(UsbAccessory accessory) {
        UsbManager manager = (UsbManager) getSystemService(USB_SERVICE);
        Log.i(TAG, "OPEN_ACCESSORY manufacturer=" + token(accessory.getManufacturer()) +
                " model=" + token(accessory.getModel()) + " version=" + token(accessory.getVersion()));
        try {
            ParcelFileDescriptor localFd = manager.openAccessory(accessory);
            if (localFd == null) {
                Log.e(TAG, "OPEN_ACCESSORY_FAILED null_fd");
                return;
            }
            synchronized (accessoryLock) { parcelFd = localFd; }

            BufferedReader reader = new BufferedReader(new InputStreamReader(
                    new FileInputStream(localFd.getFileDescriptor()), StandardCharsets.UTF_8));
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
                    new FileOutputStream(localFd.getFileDescriptor()), StandardCharsets.UTF_8));

            Log.i(TAG, "BRIDGE_READY transport=AOA bridge=" + BRIDGE_VERSION +
                    " smartsky=" + (isSmartSkyReady() ? "bound" : "not_bound") +
                    " noAutoRetry=true");

            String line;
            while ((line = reader.readLine()) != null) {
                String request = line.trim();
                if (request.isEmpty()) continue;
                Log.i(TAG, "RX " + BridgeProtocolSanitizer.safeLogLine(request));
                String response = handleRequest(request);
                writer.write(response);
                writer.write("\n");
                writer.flush();
                Log.i(TAG, "TX " + BridgeProtocolSanitizer.safeLogLine(response));
            }
            Log.i(TAG, "BRIDGE_EOF");
        } catch (Exception e) {
            Log.e(TAG, "BRIDGE_IO_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
        } finally {
            synchronized (accessoryLock) { closeAccessoryLocked(); }
        }
    }

    private String handleRequest(String request) {
        String[] parts = request.split("\\s+", 3);
        String command = parts[0].toUpperCase();
        String id = parts.length > 1 ? parts[1] : "0";
        String args = parts.length > 2 ? parts[2] : "";

        if ("PING".equals(command)) {
            return "PONG " + id + " bridge=" + BRIDGE_VERSION +
                    " role=kozen-payment-bridge manufacturer=" + token(Build.MANUFACTURER) +
                    " model=" + token(Build.MODEL) + " android=" + token(Build.VERSION.RELEASE) +
                    " sdk=" + Build.VERSION.SDK_INT;
        }
        if ("INFO".equals(command)) {
            return "INFO " + id + " protocol=4 transport=AOA role=kozen-payment-bridge bridge=" + BRIDGE_VERSION +
                    " smartsky=" + (isSmartSkyReady() ? "bound" : "not_bound") +
                    " commands=PING,INFO,GET_STATE,GET_TERMINAL_DATA,GET_SBP_ROUTE,SBP_ECHO_QR,GET_SBP_QR_EVENT,ACK_SBP_QR_EVENT,PAYMENT,QR_PAYMENT_BLOCKED,START_SBP_QR_PROBE,GET_SBP_PROBE_STATUS,GET_PAYMENT_STATUS,GET_LAST_TRANSACTION,GET_TRANSACTION" +
                    " paymentPolicy=EXPLICIT_SINGLE_NO_AUTO_RETRY sbpLiveEnabled=" + LIVE_QR_PAYMENT_ENABLED +
                    " sbpProbeEnabled=" + LIVE_QR_GENERATION_PROBE_ENABLED +
                    " sbpCallbackContract=CAPTURE_HASHED_V1 sbpWireContract=BASE64URL_REDACTED_V1" +
                    " sbpEventContract=QR_EVENT_PEEK_ACK_V1";
        }
        if ("GET_STATE".equals(command)) return getStateResponse(id);
        if ("GET_TERMINAL_DATA".equals(command)) return getTerminalDataResponse(id);
        if ("GET_SBP_ROUTE".equals(command)) return getSbpRouteResponse(id);
        if ("SBP_ECHO_QR".equals(command)) return sbpEchoQr(id, args);
        if ("GET_SBP_QR_EVENT".equals(command)) return getSbpQrEvent(id);
        if ("ACK_SBP_QR_EVENT".equals(command)) return ackSbpQrEvent(id, args);
        if ("PAYMENT".equals(command)) return payment(id, args);
        if ("QR_PAYMENT".equals(command)) return qrPaymentBlocked(id);
        if ("START_SBP_QR_PROBE".equals(command)) return startSbpQrGenerationProbe(id, args);
        if ("GET_SBP_PROBE_STATUS".equals(command)) return getSbpProbeStatus(id);
        if ("GET_PAYMENT_STATUS".equals(command)) return getPaymentStatus(id);
        if ("GET_LAST_TRANSACTION".equals(command)) return getLastTransactionResponse(id, arg(args, "terminalId"));
        if ("GET_TRANSACTION".equals(command)) return getTransactionResponse(id, arg(args, "terminalId"), arg(args, "receiptNumber"));
        return "ERROR " + id + " code=UNKNOWN_COMMAND command=" + token(command);
    }

    private boolean isSmartSkyReady() {
        IBinder binder = smartSkyBinder;
        return smartSkyBound && binder != null && binder.isBinderAlive();
    }

    private IBinder requireBinder() {
        IBinder binder = smartSkyBinder;
        if (!smartSkyBound || binder == null || !binder.isBinderAlive()) {
            bindSmartSky();
            throw new IllegalStateException("SMARTSKY_NOT_BOUND");
        }
        return binder;
    }

    private int readState() throws Exception {
        IBinder binder = requireBinder();
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(SMARTSKY_DESCRIPTOR);
            if (!binder.transact(TX_GET_STATE, data, reply, 0)) throw new IllegalStateException("GET_STATE_TRANSACT_FALSE");
            reply.readException();
            return reply.readInt();
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private TerminalData readTerminalData() throws Exception {
        IBinder binder = requireBinder();
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(SMARTSKY_DESCRIPTOR);
            if (!binder.transact(TX_GET_TERMINAL_DATA, data, reply, 0)) throw new IllegalStateException("GET_TERMINAL_DATA_TRANSACT_FALSE");
            reply.readException();
            int present = reply.readInt();
            if (present == 0) throw new IllegalStateException("GET_TERMINAL_DATA_NULL");
            return TerminalData.CREATOR.createFromParcel(reply);
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private String getStateResponse(String id) {
        try {
            int state = readState();
            return "STATE " + id + " code=0 state=" + state + " bound=true";
        } catch (Exception e) {
            Log.e(TAG, "SMARTSKY_GET_STATE_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            return "STATE " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) + " message=" + token(safe(e.getMessage()));
        }
    }

    private String getTerminalDataResponse(String id) {
        try {
            TerminalData data = readTerminalData();
            PaymentRoute route = findPaymentRoute(data, null, null);
            PaymentRoute sbpRoute = findRoute(data, "42", "qrPayment", null, SUPPORTED_CURRENCY);
            int count = data.getTerminals() == null ? 0 : data.getTerminals().size();
            return "TERMINAL_DATA " + id +
                    " code=" + data.getCode() +
                    " message=" + token(data.getMessage()) +
                    " terminalId=" + token(data.getTerminalId()) +
                    " merchantId=" + token(data.getMerchantId()) +
                    " terminals=" + count +
                    " payment=" + (route != null) +
                    " paymentTid=" + (route == null ? "-" : route.tid) +
                    " paymentType=" + (route == null ? "-" : route.type) +
                    " transactionType=" + (route == null ? "-" : route.transactionType) +
                    " currencies=" + (route == null ? "-" : route.currency) +
                    " sbp=" + (sbpRoute != null) +
                    " sbpTidPresent=" + (sbpRoute != null && sbpRoute.tid != null && !sbpRoute.tid.isEmpty()) +
                    " sbpType=" + (sbpRoute == null ? "-" : sbpRoute.type) +
                    " sbpTransactionType=" + (sbpRoute == null ? "-" : sbpRoute.transactionType) +
                    " sbpCurrency=" + (sbpRoute == null ? "-" : sbpRoute.currency) +
                    " bound=true";
        } catch (Exception e) {
            Log.e(TAG, "SMARTSKY_GET_TERMINAL_DATA_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            return "TERMINAL_DATA " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) + " message=" + token(safe(e.getMessage()));
        }
    }

    private String getSbpRouteResponse(String id) {
        try {
            TerminalData data = readTerminalData();
            PaymentRoute route = findRoute(data, "42", "qrPayment", null, SUPPORTED_CURRENCY);
            return "SBP_ROUTE " + id +
                    " code=0 available=" + (route != null) +
                    " operationType=" + (route == null ? "-" : route.type) +
                    " transactionType=" + (route == null ? "-" : route.transactionType) +
                    " currency=" + (route == null ? "-" : route.currency) +
                    " tidPresent=" + (route != null && route.tid != null && !route.tid.isEmpty()) +
                    " liveEnabled=" + LIVE_QR_PAYMENT_ENABLED +
                    " callbackContract=CAPTURE_HASHED_V1" +
                    " safety=READ_ONLY";
        } catch (Exception e) {
            Log.e(TAG, "SMARTSKY_GET_SBP_ROUTE_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            return "SBP_ROUTE " + id + " code=EXCEPTION available=false type=" +
                    token(e.getClass().getSimpleName()) + " message=" + token(safe(e.getMessage())) +
                    " liveEnabled=" + LIVE_QR_PAYMENT_ENABLED + " safety=READ_ONLY";
        }
    }

    private String sbpEchoQr(String id, String args) {
        if (!validRequestId(id)) return "SBP_QR " + token(id) + " code=BAD_REQUEST_ID synthetic=true liveEnabled=false";
        String payloadB64 = arg(args, "payloadB64");
        if (!SbpWireCodec.validEncoded(payloadB64)) return "SBP_QR " + token(id) + " code=BAD_PAYLOAD synthetic=true liveEnabled=false";
        try {
            String payload = SbpWireCodec.decode(payloadB64);
            String qrId = "synthetic-" + id;
            SbpQrCapture.Event event = sbpQrCapture.capture(qrId, payload, "synthetic");
            SbpQrCapture.SafeSummary safe = event.safeSummary();
            return "SBP_QR " + id +
                    " code=0 qrIdB64=" + SbpWireCodec.encode(qrId) +
                    " payloadB64=" + payloadB64 +
                    " payloadHash=" + safe.payloadHash +
                    " payloadLength=" + safe.payloadLength +
                    " eventSequence=" + event.sequence +
                    " queueSize=" + sbpQrCapture.size() +
                    " dropped=" + sbpQrCapture.droppedCount() +
                    " synthetic=true liveEnabled=" + LIVE_QR_PAYMENT_ENABLED +
                    " wireContract=BASE64URL_REDACTED_V1";
        } catch (Exception ex) {
            return "SBP_QR " + token(id) + " code=EXCEPTION type=" + token(ex.getClass().getSimpleName()) + " synthetic=true liveEnabled=false";
        }
    }

    private String getSbpQrEvent(String id) {
        if (!validRequestId(id)) return "SBP_EVENT " + token(id) + " code=BAD_REQUEST_ID eventContract=QR_EVENT_PEEK_ACK_V1 noFinancialCommand=true";
        SbpQrCapture.Event event = sbpQrCapture.peek();
        if (event == null) {
            return "SBP_EVENT " + id + " code=EMPTY queueSize=0 dropped=" + sbpQrCapture.droppedCount() +
                    " eventContract=QR_EVENT_PEEK_ACK_V1 noFinancialCommand=true";
        }
        try {
            SbpQrCapture.SafeSummary safe = event.safeSummary();
            return "SBP_EVENT " + id +
                    " code=0 sequence=" + event.sequence +
                    " qrIdB64=" + SbpWireCodec.encode(event.qrId) +
                    " payloadB64=" + SbpWireCodec.encode(event.payload) +
                    " payloadHash=" + safe.payloadHash +
                    " payloadLength=" + safe.payloadLength +
                    " source=" + token(event.source) +
                    " queueSize=" + sbpQrCapture.size() +
                    " dropped=" + sbpQrCapture.droppedCount() +
                    " eventContract=QR_EVENT_PEEK_ACK_V1 noFinancialCommand=true";
        } catch (Exception ex) {
            return "SBP_EVENT " + id + " code=EXCEPTION type=" + token(ex.getClass().getSimpleName()) +
                    " eventContract=QR_EVENT_PEEK_ACK_V1 noFinancialCommand=true";
        }
    }

    private String ackSbpQrEvent(String id, String args) {
        if (!validRequestId(id)) return "SBP_ACK " + token(id) + " code=BAD_REQUEST_ID eventContract=QR_EVENT_PEEK_ACK_V1 noFinancialCommand=true";
        long sequence;
        try {
            String value = arg(args, "sequence");
            sequence = Long.parseLong(value == null ? "" : value);
        } catch (Exception ex) {
            return "SBP_ACK " + id + " code=BAD_SEQUENCE eventContract=QR_EVENT_PEEK_ACK_V1 noFinancialCommand=true";
        }
        SbpQrCapture.AckStatus status = sbpQrCapture.ack(sequence);
        boolean accepted = status == SbpQrCapture.AckStatus.ACKED || status == SbpQrCapture.AckStatus.ALREADY_ACKED;
        return "SBP_ACK " + id +
                " code=" + (accepted ? "0" : status.name()) +
                " status=" + status.name() +
                " sequence=" + sequence +
                " headSequence=" + sbpQrCapture.headSequence() +
                " queueSize=" + sbpQrCapture.size() +
                " dropped=" + sbpQrCapture.droppedCount() +
                " eventContract=QR_EVENT_PEEK_ACK_V1 noFinancialCommand=true";
    }

    private String qrPaymentBlocked(String id) {
        return "SBP_RESULT " + token(id) +
                " status=BLOCKED code=LIVE_QR_PAYMENT_NOT_APPROVED liveEnabled=" +
                LIVE_QR_PAYMENT_ENABLED + " callbackContract=CAPTURE_HASHED_V1 noFinancialCommand=true";
    }

    /**
     * Controlled one-ruble live QR generation probe.
     *
     * This is deliberately NOT the normal production QR_PAYMENT path:
     *  - exact amount 1.00 RUB only;
     *  - explicit probe token is mandatory;
     *  - one requestId can invoke Binder transaction #19 at most once;
     *  - the Binder call runs on a separate worker so AOA remains available for QR callback delivery;
     *  - no automatic retry is ever performed.
     */
    private String startSbpQrGenerationProbe(String requestId, String args) {
        synchronized (paymentLock) {
            if (!LIVE_QR_GENERATION_PROBE_ENABLED) return sbpProbeBlocked(requestId, "PROBE_DISABLED");
            if (!validRequestId(requestId)) return sbpProbeBlocked(requestId, "BAD_REQUEST_ID");

            String probeToken = arg(args, "probeToken");
            if (!LIVE_QR_PROBE_TOKEN.equals(probeToken)) return sbpProbeBlocked(requestId, "BAD_PROBE_TOKEN");

            BigDecimal amount;
            try { amount = normalizeAmount(arg(args, "amount")); }
            catch (Exception e) { return sbpProbeBlocked(requestId, "BAD_AMOUNT"); }
            if (amount.compareTo(new BigDecimal("1.00")) != 0) return sbpProbeBlocked(requestId, "PROBE_AMOUNT_MUST_BE_1_00");
            if (!SUPPORTED_CURRENCY.equals(arg(args, "currency"))) return sbpProbeBlocked(requestId, "UNSUPPORTED_CURRENCY");

            SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
            String storedResponse = prefs.getString(sbpProbeResponseKey(requestId), null);
            String storedStatus = prefs.getString(sbpProbeStatusKey(requestId), null);
            if (storedResponse != null) return storedResponse + " replayed=true";
            if ("STARTED".equals(storedStatus) || "UNCERTAIN".equals(storedStatus)) {
                return "SBP_PROBE_RESULT " + requestId +
                        " status=" + storedStatus + " code=PREVIOUS_UNRESOLVED noRetry=true";
            }

            String activeCard = prefs.getString(PREF_ACTIVE_REQUEST, "");
            if (activeCard != null && !activeCard.isEmpty()) {
                return sbpProbeBlocked(requestId, "CARD_REQUEST_UNRESOLVED");
            }
            String activeSbp = prefs.getString(PREF_ACTIVE_SBP_REQUEST, "");
            if (activeSbp != null && !activeSbp.isEmpty() && !activeSbp.equals(requestId)) {
                return "SBP_PROBE_RESULT " + requestId +
                        " status=BLOCKED code=ANOTHER_SBP_REQUEST_UNRESOLVED active=" + token(activeSbp) +
                        " noRetry=true";
            }

            try {
                int state = readState();
                if (state != 0) {
                    return "SBP_PROBE_RESULT " + requestId +
                            " status=BLOCKED code=STATE_NOT_READY state=" + state + " noRetry=true";
                }

                TerminalData fresh = readTerminalData();
                PaymentRoute route = findRoute(fresh, "42", "qrPayment", null, SUPPORTED_CURRENCY);
                if (route == null || route.tid == null || route.tid.isEmpty()) {
                    return sbpProbeBlocked(requestId, "FRESH_SBP_ROUTE_NOT_FOUND");
                }

                prefs.edit()
                        .putString(sbpProbeStatusKey(requestId), "STARTED")
                        .putString(PREF_ACTIVE_SBP_REQUEST, requestId)
                        .putString(sbpProbeAmountKey(requestId), amount.toPlainString())
                        .putString(sbpProbeTidKey(requestId), route.tid)
                        .putBoolean(sbpProbeQrReadyKey(requestId), false)
                        .putLong(sbpProbeStartedKey(requestId), System.currentTimeMillis())
                        .apply();

                final String workerRequestId = requestId;
                final BigDecimal workerAmount = amount;
                final String workerTid = route.tid;
                Thread worker = new Thread(
                        () -> runSbpQrGenerationProbe(workerRequestId, workerAmount, workerTid, SUPPORTED_CURRENCY),
                        "iretail-sbp-qr-probe-" + sdkTransactionId(requestId));
                worker.start();

                Log.w(TAG, "SBP_PROBE_CALL_BEGIN requestId=" + requestId +
                        " amount=1.00 currency=" + SUPPORTED_CURRENCY +
                        " tidPresent=true binderTransaction=" + TX_QR_PAYMENT +
                        " noAutoRetry=true doNotScan=true");
                return "SBP_PROBE_RESULT " + requestId +
                        " status=STARTED code=0 amount=1.00 currency=" + SUPPORTED_CURRENCY +
                        " qrReady=false noRetry=true doNotScan=true";
            } catch (Exception e) {
                String response = "SBP_PROBE_RESULT " + requestId +
                        " status=FAILED code=PRECHECK_EXCEPTION type=" + token(e.getClass().getSimpleName()) +
                        " message=" + token(safe(e.getMessage())) + " noRetry=true";
                prefs.edit()
                        .putString(sbpProbeStatusKey(requestId), "FAILED")
                        .putString(sbpProbeResponseKey(requestId), response)
                        .remove(PREF_ACTIVE_SBP_REQUEST)
                        .apply();
                return response;
            }
        }
    }

    private void runSbpQrGenerationProbe(String requestId, BigDecimal amount, String tid, String currency) {
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        try {
            Bundle result = callSbpQrPayment(requestId, amount, tid, currency);
            ResultSnapshot snapshot = ResultSnapshot.from(result);
            String status = classify(snapshot);
            String response = "SBP_PROBE_RESULT " + requestId +
                    " status=" + status +
                    " code=" + snapshot.code +
                    " codePresent=" + snapshot.codePresent +
                    " approved=" + snapshot.approvedText() +
                    " approvedPresent=" + snapshot.approvedPresent +
                    " message=" + token(snapshot.message) +
                    " rc=" + token(snapshot.rc) +
                    " rrn=" + token(snapshot.rrn) +
                    " amount=" + token(snapshot.amount) +
                    " currency=" + token(snapshot.currency) +
                    " terminalIdPresent=" + (snapshot.terminalId != null && !snapshot.terminalId.isEmpty()) +
                    " receiptPresent=" + (snapshot.receipt != null && !snapshot.receipt.isEmpty()) +
                    " transactionIdPresent=" + (snapshot.transactionId != null && !snapshot.transactionId.isEmpty()) +
                    " qrReady=" + prefs.getBoolean(sbpProbeQrReadyKey(requestId), false) +
                    " noRetry=true";

            SharedPreferences.Editor editor = prefs.edit()
                    .putString(sbpProbeStatusKey(requestId), status)
                    .putString(sbpProbeResponseKey(requestId), response);
            if (!"UNCERTAIN".equals(status)) editor.remove(PREF_ACTIVE_SBP_REQUEST);
            editor.apply();

            Log.w(TAG, "SBP_PROBE_CALL_RESULT requestId=" + requestId +
                    " status=" + status + " code=" + snapshot.code +
                    " approved=" + snapshot.approvedText() + " rc=" + token(snapshot.rc) +
                    " qrReady=" + prefs.getBoolean(sbpProbeQrReadyKey(requestId), false) +
                    " noAutoRetry=true");
        } catch (Exception e) {
            String response = "SBP_PROBE_RESULT " + requestId +
                    " status=UNCERTAIN code=EXCEPTION type=" + token(e.getClass().getSimpleName()) +
                    " message=" + token(safe(e.getMessage())) +
                    " qrReady=" + prefs.getBoolean(sbpProbeQrReadyKey(requestId), false) +
                    " noRetry=true";
            prefs.edit()
                    .putString(sbpProbeStatusKey(requestId), "UNCERTAIN")
                    .putString(sbpProbeResponseKey(requestId), response)
                    .putString(PREF_ACTIVE_SBP_REQUEST, requestId)
                    .apply();
            Log.e(TAG, "SBP_PROBE_CALL_UNCERTAIN requestId=" + requestId +
                    " noAutoRetry=true " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
        }
    }

    private Bundle callSbpQrPayment(String requestId, BigDecimal amount, String tid, String currency) throws Exception {
        IBinder binder = requireBinder();
        Bundle params = new Bundle();
        params.putSerializable("amount", amount);
        params.putString("terminalId", tid);
        params.putString("currencyCode", currency);
        params.putString("id", sdkTransactionId(requestId));

        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(SMARTSKY_DESCRIPTOR);
            data.writeInt(1);
            data.writeBundle(params);
            data.writeStrongBinder(new SbpTransactionCallback());
            if (!binder.transact(TX_QR_PAYMENT, data, reply, 0)) {
                throw new IllegalStateException("SBP_QR_TRANSACT_FALSE");
            }
            reply.readException();
            int present = reply.readInt();
            if (present == 0) throw new IllegalStateException("SBP_QR_NULL_RESULT");
            Bundle result = reply.readBundle(getClassLoader());
            if (result == null) throw new IllegalStateException("SBP_QR_BUNDLE_NULL");
            result.setClassLoader(getClassLoader());
            return result;
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private String getSbpProbeStatus(String requestId) {
        if (!validRequestId(requestId)) return sbpProbeBlocked(requestId, "BAD_REQUEST_ID");
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        String response = prefs.getString(sbpProbeResponseKey(requestId), null);
        String status = prefs.getString(sbpProbeStatusKey(requestId), null);
        boolean qrReady = prefs.getBoolean(sbpProbeQrReadyKey(requestId), false);
        if (response != null) return response + " statusQuery=true";
        if (status != null) {
            return "SBP_PROBE_RESULT " + requestId +
                    " status=" + token(status) + " code=NO_FINAL_RESULT qrReady=" + qrReady +
                    " noRetry=true statusQuery=true";
        }
        return "SBP_PROBE_RESULT " + requestId +
                " status=UNKNOWN code=NOT_FOUND qrReady=false noRetry=true statusQuery=true";
    }

    private static String sbpProbeBlocked(String id, String code) {
        return "SBP_PROBE_RESULT " + token(id) +
                " status=BLOCKED code=" + code + " qrReady=false noRetry=true";
    }


    private PaymentRoute findPaymentRoute(TerminalData data, String requiredTid, String requiredCurrency) {
        return findRoute(data, "00", "payment", requiredTid, requiredCurrency);
    }

    private PaymentRoute findRoute(TerminalData data, String requiredType, String requiredTransactionType,
                                   String requiredTid, String requiredCurrency) {
        if (data == null || data.getCode() != 0 || data.getTerminals() == null) return null;
        for (Terminal terminal : data.getTerminals()) {
            if (terminal == null) continue;
            String tid = terminal.getTerminalId();
            if (requiredTid != null && !requiredTid.equals(tid)) continue;
            ArrayList<Operation> operations = terminal.getOperations();
            if (operations == null) continue;
            for (Operation operation : operations) {
                if (operation == null) continue;
                String type = operation.getType();
                String txType = operation.getTransactionType();
                if (!requiredType.equals(type) || !requiredTransactionType.equalsIgnoreCase(txType)) continue;
                Set<String> currencies = new LinkedHashSet<>();
                ArrayList<Currency> list = operation.getCurrencies();
                if (list != null) {
                    for (Currency currency : list) {
                        if (currency != null && currency.getCurrencyCode() != null) currencies.add(currency.getCurrencyCode().trim());
                    }
                }
                if (requiredCurrency != null) {
                    if (currencies.contains(requiredCurrency)) return new PaymentRoute(tid, type, txType, requiredCurrency);
                } else if (!currencies.isEmpty()) {
                    return new PaymentRoute(tid, type, txType, currencies.iterator().next());
                }
            }
        }
        return null;
    }

    private String payment(String requestId, String args) {
        synchronized (paymentLock) {
            if (!validRequestId(requestId)) return blocked(requestId, "BAD_REQUEST_ID");

            SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
            String stored = prefs.getString(paymentResponseKey(requestId), null);
            String storedStatus = prefs.getString(paymentStatusKey(requestId), null);
            if (stored != null) {
                Log.w(TAG, "PAYMENT_DUPLICATE_REQUEST id=" + requestId + " storedStatus=" + storedStatus + " noRetry=true");
                return stored + " replayed=true";
            }
            if ("STARTED".equals(storedStatus) || "UNCERTAIN".equals(storedStatus)) {
                return "PAYMENT_RESULT " + requestId + " status=UNCERTAIN_RECOVERY_REQUIRED code=PREVIOUS_UNRESOLVED approved=null noRetry=true";
            }

            String activeSbp = prefs.getString(PREF_ACTIVE_SBP_REQUEST, "");
            if (activeSbp != null && !activeSbp.isEmpty()) {
                return "PAYMENT_RESULT " + requestId + " status=BLOCKED code=SBP_REQUEST_UNRESOLVED active=" + token(activeSbp) + " approved=null noRetry=true";
            }

            String active = prefs.getString(PREF_ACTIVE_REQUEST, "");
            if (active != null && !active.isEmpty() && !active.equals(requestId)) {
                return "PAYMENT_RESULT " + requestId + " status=BLOCKED code=ANOTHER_REQUEST_UNRESOLVED active=" + token(active) + " approved=null noRetry=true";
            }

            String amountRaw = arg(args, "amount");
            String tid = arg(args, "terminalId");
            String currency = arg(args, "currency");
            BigDecimal amount;
            try { amount = normalizeAmount(amountRaw); }
            catch (Exception e) { return blocked(requestId, "BAD_AMOUNT"); }
            if (tid == null || tid.trim().isEmpty()) return blocked(requestId, "BAD_TERMINAL_ID");
            tid = tid.trim();
            if (!SUPPORTED_CURRENCY.equals(currency)) return blocked(requestId, "UNSUPPORTED_CURRENCY");

            try {
                int state = readState();
                if (state != 0) return "PAYMENT_RESULT " + requestId + " status=BLOCKED code=STATE_NOT_READY state=" + state + " approved=null noRetry=true";

                TerminalData fresh = readTerminalData();
                PaymentRoute route = findPaymentRoute(fresh, tid, currency);
                if (route == null) return blocked(requestId, "FRESH_ROUTE_NOT_FOUND");

                prefs.edit()
                        .putString(paymentStatusKey(requestId), "STARTED")
                        .putString(PREF_ACTIVE_REQUEST, requestId)
                        .putString(paymentAmountKey(requestId), amount.toPlainString())
                        .putString(paymentTidKey(requestId), tid)
                        .putString(paymentCurrencyKey(requestId), currency)
                        .putLong(paymentStartedKey(requestId), System.currentTimeMillis())
                        .apply();

                Log.w(TAG, "PAYMENT_CALL_BEGIN requestId=" + requestId + " amount=" + amount.toPlainString() +
                        " terminalId=" + tid + " currency=" + currency + " noAutoRetry=true");

                Bundle result = callPayment(requestId, amount, tid, currency);
                ResultSnapshot snapshot = ResultSnapshot.from(result);
                String status = classify(snapshot);

                String response = "PAYMENT_RESULT " + requestId +
                        " status=" + status +
                        " code=" + snapshot.code +
                        " codePresent=" + snapshot.codePresent +
                        " approved=" + snapshot.approvedText() +
                        " approvedPresent=" + snapshot.approvedPresent +
                        " message=" + token(snapshot.message) +
                        " rc=" + token(snapshot.rc) +
                        " rrn=" + token(snapshot.rrn) +
                        " authCode=" + token(snapshot.authCode) +
                        " amount=" + token(snapshot.amount) +
                        " currency=" + token(snapshot.currency) +
                        " terminalId=" + token(snapshot.terminalId) +
                        " receipt=" + token(snapshot.receipt) +
                        " transactionId=" + token(snapshot.transactionId) +
                        " type=" + token(snapshot.type) +
                        " noRetry=true";

                SharedPreferences.Editor editor = prefs.edit()
                        .putString(paymentStatusKey(requestId), status)
                        .putString(paymentResponseKey(requestId), response);
                if (!"UNCERTAIN".equals(status)) editor.remove(PREF_ACTIVE_REQUEST);
                editor.apply();

                Log.w(TAG, "PAYMENT_CALL_RESULT requestId=" + requestId + " status=" + status +
                        " code=" + snapshot.code + " codePresent=" + snapshot.codePresent +
                        " approved=" + snapshot.approvedText() + " approvedPresent=" + snapshot.approvedPresent +
                        " rc=" + token(snapshot.rc) + " rrn=" + token(snapshot.rrn) + " receipt=" + token(snapshot.receipt) +
                        " noAutoRetry=true");
                return response;
            } catch (Exception e) {
                String response = "PAYMENT_RESULT " + requestId + " status=UNCERTAIN code=EXCEPTION type=" +
                        token(e.getClass().getSimpleName()) + " message=" + token(safe(e.getMessage())) +
                        " approved=null approvedPresent=false noRetry=true";
                prefs.edit()
                        .putString(paymentStatusKey(requestId), "UNCERTAIN")
                        .putString(paymentResponseKey(requestId), response)
                        .putString(PREF_ACTIVE_REQUEST, requestId)
                        .apply();
                Log.e(TAG, "PAYMENT_CALL_UNCERTAIN requestId=" + requestId + " noAutoRetry=true " +
                        e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
                return response;
            }
        }
    }

    private Bundle callPayment(String requestId, BigDecimal amount, String tid, String currency) throws Exception {
        IBinder binder = requireBinder();
        Bundle params = new Bundle();
        params.putSerializable("amount", amount);
        params.putString("terminalId", tid);
        params.putString("currencyCode", currency);
        params.putString("id", sdkTransactionId(requestId));

        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(SMARTSKY_DESCRIPTOR);
            data.writeInt(1);
            data.writeBundle(params);
            data.writeStrongBinder(new PaymentCallback());
            if (!binder.transact(TX_PAYMENT, data, reply, 0)) throw new IllegalStateException("PAYMENT_TRANSACT_FALSE");
            reply.readException();
            int present = reply.readInt();
            if (present == 0) throw new IllegalStateException("PAYMENT_NULL_RESULT");
            Bundle result = reply.readBundle(getClassLoader());
            if (result == null) throw new IllegalStateException("PAYMENT_BUNDLE_NULL");
            result.setClassLoader(getClassLoader());
            return result;
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private String getPaymentStatus(String requestId) {
        if (!validRequestId(requestId)) return blocked(requestId, "BAD_REQUEST_ID");
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        String response = prefs.getString(paymentResponseKey(requestId), null);
        String status = prefs.getString(paymentStatusKey(requestId), null);
        if (response != null) return response + " statusQuery=true";
        if (status != null) return "PAYMENT_RESULT " + requestId + " status=" + token(status) + " code=NO_FINAL_RESULT approved=null noRetry=true statusQuery=true";
        return "PAYMENT_RESULT " + requestId + " status=UNKNOWN code=NOT_FOUND approved=null noRetry=true statusQuery=true";
    }

    private String getLastTransactionResponse(String id, String terminalId) {
        if (terminalId == null || terminalId.trim().isEmpty()) return "LAST_TRANSACTION " + id + " code=BAD_TERMINAL_ID safety=READ_ONLY";
        try {
            Bundle result = callTransactionLookup(TX_GET_LAST_TRANSACTION, terminalId.trim(), null);
            return transactionSummary("LAST_TRANSACTION", id, result);
        } catch (Exception e) {
            Log.e(TAG, "GET_LAST_TRANSACTION_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            return "LAST_TRANSACTION " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) + " message=" + token(safe(e.getMessage())) + " safety=READ_ONLY";
        }
    }

    private String getTransactionResponse(String id, String terminalId, String receiptNumber) {
        if (terminalId == null || terminalId.trim().isEmpty() || receiptNumber == null || receiptNumber.trim().isEmpty()) {
            return "TRANSACTION " + id + " code=BAD_LOOKUP_PARAMS safety=READ_ONLY";
        }
        try {
            Bundle result = callTransactionLookup(TX_GET_TRANSACTION, terminalId.trim(), receiptNumber.trim());
            return transactionSummary("TRANSACTION", id, result);
        } catch (Exception e) {
            Log.e(TAG, "GET_TRANSACTION_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            return "TRANSACTION " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) + " message=" + token(safe(e.getMessage())) + " safety=READ_ONLY";
        }
    }

    private Bundle callTransactionLookup(int transactionCode, String terminalId, String receiptNumber) throws Exception {
        IBinder binder = requireBinder();
        Bundle params = new Bundle();
        params.putString("terminalId", terminalId);
        params.putString("id", receiptNumber == null ? "auditlast" : "audittxn1");
        if (receiptNumber != null) params.putString("receiptNumber", receiptNumber);

        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(SMARTSKY_DESCRIPTOR);
            data.writeInt(1);
            data.writeBundle(params);
            if (!binder.transact(transactionCode, data, reply, 0)) throw new IllegalStateException("TRANSACTION_LOOKUP_TRANSACT_FALSE_" + transactionCode);
            reply.readException();
            int present = reply.readInt();
            if (present == 0) throw new IllegalStateException("TRANSACTION_LOOKUP_NULL_" + transactionCode);
            Bundle result = reply.readBundle(getClassLoader());
            if (result == null) throw new IllegalStateException("TRANSACTION_LOOKUP_BUNDLE_NULL_" + transactionCode);
            result.setClassLoader(getClassLoader());
            return result;
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private static String transactionSummary(String prefix, String id, Bundle result) {
        ResultSnapshot s = ResultSnapshot.from(result);
        return prefix + " " + id +
                " code=" + s.code +
                " codePresent=" + s.codePresent +
                " approved=" + s.approvedText() +
                " approvedPresent=" + s.approvedPresent +
                " message=" + token(s.message) +
                " rc=" + token(s.rc) +
                " rrn=" + token(s.rrn) +
                " authCode=" + token(s.authCode) +
                " amount=" + token(s.amount) +
                " currency=" + token(s.currency) +
                " terminalId=" + token(s.terminalId) +
                " receipt=" + token(s.receipt) +
                " transactionId=" + token(s.transactionId) +
                " type=" + token(s.type) +
                " safety=READ_ONLY sensitiveFields=OMITTED";
    }

    private static String classify(ResultSnapshot s) {
        if (s.code != 0) return "FAILED";
        if (Boolean.TRUE.equals(s.approved)) return isApprovedRc(s.rc) ? "APPROVED" : "UNCERTAIN";
        if (Boolean.FALSE.equals(s.approved)) return "DECLINED";
        return "UNCERTAIN";
    }

    private static boolean isApprovedRc(String rc) {
        return "00".equals(rc) || "000".equals(rc) || "001".equals(rc) || "007".equals(rc);
    }

    private static BigDecimal normalizeAmount(String value) {
        if (value == null || value.trim().isEmpty()) throw new IllegalArgumentException("empty");
        BigDecimal amount = new BigDecimal(value.trim());
        if (amount.signum() <= 0 || amount.compareTo(MAX_AMOUNT) > 0) throw new IllegalArgumentException("range");
        if (amount.scale() > 2) throw new IllegalArgumentException("scale");
        return amount.setScale(2);
    }

    private static String blocked(String id, String code) {
        return "PAYMENT_RESULT " + token(id) + " status=BLOCKED code=" + code + " approved=null noRetry=true";
    }

    private final class PaymentCallback extends Binder {
        PaymentCallback() { attachInterface(null, TRANSACTION_CALLBACK_DESCRIPTOR); }

        @Override protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
            if (code == IBinder.INTERFACE_TRANSACTION) {
                if (reply != null) reply.writeString(TRANSACTION_CALLBACK_DESCRIPTOR);
                return true;
            }
            data.enforceInterface(TRANSACTION_CALLBACK_DESCRIPTOR);
            switch (code) {
                case 1: {
                    int state = data.readInt();
                    String message = data.readString();
                    Log.i(TAG, "PAYMENT_CALLBACK_STATE state=" + state + " message=" + token(message));
                    if (reply != null) reply.writeNoException();
                    return true;
                }
                case 2: {
                    String qrId = data.readString();
                    String qrPayload = data.readString();
                    SbpQrCapture.SafeSummary safe = SbpQrCapture.summarize(
                            qrId, qrPayload, System.currentTimeMillis());
                    Log.i(TAG, "PAYMENT_CALLBACK_QR qrIdHash=" + safe.qrIdHash +
                            " payloadHash=" + safe.payloadHash +
                            " payloadLength=" + safe.payloadLength +
                            " rawPayloadLogged=false");
                    if (reply != null) reply.writeNoException();
                    return true;
                }
                case 3: {
                    if (reply != null) reply.writeNoException();
                    return true;
                }
                case 4: {
                    String operation = data.readString();
                    Log.i(TAG, "PAYMENT_CALLBACK_OPERATION name=" + token(operation));
                    if (reply != null) reply.writeNoException();
                    return true;
                }
                case 5: {
                    String prompt = data.readString();
                    Log.w(TAG, "PAYMENT_CALLBACK_PASSWORD requested=" + token(prompt) + " returning_empty=true");
                    if (reply != null) {
                        reply.writeNoException();
                        reply.writeString("");
                    }
                    return true;
                }
                default:
                    return super.onTransact(code, data, reply, flags);
            }
        }
    }

    private final class SbpTransactionCallback extends Binder {
        SbpTransactionCallback() { attachInterface(null, TRANSACTION_CALLBACK_DESCRIPTOR); }

        @Override protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
            if (code == IBinder.INTERFACE_TRANSACTION) {
                if (reply != null) reply.writeString(TRANSACTION_CALLBACK_DESCRIPTOR);
                return true;
            }
            data.enforceInterface(TRANSACTION_CALLBACK_DESCRIPTOR);
            switch (code) {
                case 1: {
                    int state = data.readInt();
                    String message = data.readString();
                    Log.i(TAG, "SBP_CALLBACK_STATE state=" + state + " message=" + token(message) +
                            " liveEnabled=" + LIVE_QR_PAYMENT_ENABLED);
                    if (reply != null) reply.writeNoException();
                    return true;
                }
                case 2: {
                    String qrId = data.readString();
                    String qrPayload = data.readString();
                    SbpQrCapture.Event event = sbpQrCapture.capture(qrId, qrPayload, "smartsky-callback");
                    SharedPreferences probePrefs = getSharedPreferences(PREFS, MODE_PRIVATE);
                    String activeProbe = probePrefs.getString(PREF_ACTIVE_SBP_REQUEST, "");
                    if (activeProbe != null && !activeProbe.isEmpty()) {
                        probePrefs.edit().putBoolean(sbpProbeQrReadyKey(activeProbe), true).apply();
                    }
                    SbpQrCapture.SafeSummary safe = event.safeSummary();
                    Log.i(TAG, "SBP_CALLBACK_QR sequence=" + event.sequence +
                            " qrIdHash=" + safe.qrIdHash +
                            " payloadHash=" + safe.payloadHash +
                            " payloadLength=" + safe.payloadLength +
                            " queueSize=" + sbpQrCapture.size() +
                            " dropped=" + sbpQrCapture.droppedCount() +
                            " rawPayloadLogged=false liveEnabled=" + LIVE_QR_PAYMENT_ENABLED);
                    if (reply != null) reply.writeNoException();
                    return true;
                }
                case 3: {
                    if (reply != null) reply.writeNoException();
                    return true;
                }
                case 4: {
                    String operation = data.readString();
                    Log.i(TAG, "SBP_CALLBACK_OPERATION name=" + token(operation) +
                            " liveEnabled=" + LIVE_QR_PAYMENT_ENABLED);
                    if (reply != null) reply.writeNoException();
                    return true;
                }
                case 5: {
                    String prompt = data.readString();
                    Log.w(TAG, "SBP_CALLBACK_PASSWORD requested=" + token(prompt) +
                            " returning_empty=true liveEnabled=" + LIVE_QR_PAYMENT_ENABLED);
                    if (reply != null) {
                        reply.writeNoException();
                        reply.writeString("");
                    }
                    return true;
                }
                default:
                    return super.onTransact(code, data, reply, flags);
            }
        }
    }

    private static final class PaymentRoute {
        final String tid;
        final String type;
        final String transactionType;
        final String currency;
        PaymentRoute(String tid, String type, String transactionType, String currency) {
            this.tid = tid;
            this.type = type;
            this.transactionType = transactionType;
            this.currency = currency;
        }
    }

    private static final class ResultSnapshot {
        final boolean codePresent;
        final int code;
        final boolean approvedPresent;
        final Boolean approved;
        final String message;
        final String rc;
        final String rrn;
        final String authCode;
        final String amount;
        final String currency;
        final String terminalId;
        final String receipt;
        final String transactionId;
        final String type;

        private ResultSnapshot(boolean codePresent, int code, boolean approvedPresent, Boolean approved,
                               String message, String rc, String rrn, String authCode, String amount,
                               String currency, String terminalId, String receipt, String transactionId, String type) {
            this.codePresent = codePresent;
            this.code = code;
            this.approvedPresent = approvedPresent;
            this.approved = approved;
            this.message = message;
            this.rc = rc;
            this.rrn = rrn;
            this.authCode = authCode;
            this.amount = amount;
            this.currency = currency;
            this.terminalId = terminalId;
            this.receipt = receipt;
            this.transactionId = transactionId;
            this.type = type;
        }

        static ResultSnapshot from(Bundle result) {
            if (result == null) {
                return new ResultSnapshot(false, 0, false, null, null, null, null, null, null, null, null, null, null, null);
            }
            boolean codePresent = result.containsKey("code");
            int code = result.getInt("code");
            boolean approvedPresent = result.containsKey("isApproved");
            Object approvedRaw = result.get("isApproved");
            Boolean approved = approvedRaw instanceof Boolean ? (Boolean) approvedRaw : null;
            return new ResultSnapshot(
                    codePresent,
                    code,
                    approvedPresent,
                    approved,
                    result.getString("message"),
                    result.getString("rc"),
                    result.getString("rrn"),
                    result.getString("authCode"),
                    objectString(result.get("amount")),
                    result.getString("currencyCode"),
                    result.getString("terminalId"),
                    objectString(result.get("receiptNumber")),
                    result.getString("id"),
                    result.getString("type")
            );
        }

        String approvedText() { return approved == null ? "null" : approved.toString(); }
    }

    private void closeAccessoryLocked() {
        if (ioThread != null && ioThread != Thread.currentThread()) ioThread.interrupt();
        ioThread = null;
        if (parcelFd != null) {
            try { parcelFd.close(); } catch (Exception ignored) {}
            parcelFd = null;
        }
    }

    private static String arg(String args, String name) {
        if (args == null) return null;
        String prefix = name + "=";
        for (String part : args.split("\\s+")) if (part.startsWith(prefix)) return part.substring(prefix.length());
        return null;
    }

    private static boolean validRequestId(String id) {
        return id != null && id.matches("[A-Za-z0-9._-]{4,64}");
    }

    private static String sdkTransactionId(String requestId) {
        String s = requestId == null ? "00000000" : requestId.replaceAll("[^A-Za-z0-9]", "");
        if (s.length() < 8) s = (s + "00000000").substring(0, 8);
        return s.substring(Math.max(0, s.length() - 8));
    }

    private static String sbpProbeStatusKey(String id) { return "sbp." + id + ".status"; }
    private static String sbpProbeResponseKey(String id) { return "sbp." + id + ".response"; }
    private static String sbpProbeStartedKey(String id) { return "sbp." + id + ".started"; }
    static String sbpProbeAmountKey(String id) { return "sbp." + id + ".amount"; }
    static String sbpProbeTidKey(String id) { return "sbp." + id + ".tid"; }
    static String sbpProbeQrReadyKey(String id) { return "sbp." + id + ".qr_ready"; }

    private static String paymentStatusKey(String id) { return "payment." + id + ".status"; }
    private static String paymentResponseKey(String id) { return "payment." + id + ".response"; }
    private static String paymentStartedKey(String id) { return "payment." + id + ".started"; }
    static String paymentAmountKey(String id) { return "payment." + id + ".amount"; }
    static String paymentTidKey(String id) { return "payment." + id + ".tid"; }
    static String paymentCurrencyKey(String id) { return "payment." + id + ".currency"; }

    private static String objectString(Object value) { return value == null ? null : String.valueOf(value); }

    private static String token(String value) {
        if (value == null || value.isEmpty()) return "-";
        return value.replace(' ', '_').replace('\n', '_').replace('\r', '_');
    }

    private static String safe(String value) {
        if (value == null) return "-";
        value = value.replace('\n', ' ').replace('\r', ' ');
        return value.length() <= 700 ? value : value.substring(0, 700);
    }
}
