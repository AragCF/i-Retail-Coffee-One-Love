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
 * USB/AOA payment bridge running locally on Kozen P12.
 *
 * v0.4.0 adds one deliberately narrow financial command for the controlled bench test:
 * PAYMENT amount=1.00 currency=643, with fail-closed prechecks and persistent request-id
 * idempotency. No automatic retry is ever performed.
 */
public class BridgeService extends Service {
    private static final String TAG = "IretailKozenBridge";
    private static final String BRIDGE_VERSION = "0.4.0";

    private static final String SMARTSKY_ACTION = "com.skytech.smartskypos.ISmartSkyPos";
    private static final String SMARTSKY_PACKAGE = "com.skytech.smartskypos";
    private static final String SMARTSKY_SERVICE = "com.crestwavetech.smartskyposservice.SmartSkyPosService";
    private static final String SMARTSKY_DESCRIPTOR = "com.skytech.smartskyposlib.ISmartSkyPos";
    private static final String TRANSACTION_CALLBACK_DESCRIPTOR = "com.skytech.smartskyposlib.TransactionCallback";

    private static final int SMARTSKY_TX_GET_STATE = 1;
    private static final int SMARTSKY_TX_GET_TERMINAL_DATA = 4;
    private static final int SMARTSKY_TX_PAYMENT = 5;

    private static final String TEST_AMOUNT = "1.00";
    private static final String TEST_CURRENCY = "643";

    private static final String PREFS = "iretail_payment_bridge_v1";
    private static final String PREF_ACTIVE_REQUEST = "active_request";

    private final Object lock = new Object();
    private final Object paymentLock = new Object();
    private Thread ioThread;
    private ParcelFileDescriptor parcelFd;

    private volatile IBinder smartSkyBinder;
    private volatile boolean smartSkyBound;

    private final ServiceConnection smartSkyConnection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            smartSkyBinder = service;
            smartSkyBound = true;
            String descriptor = "-";
            try { descriptor = service == null ? "-" : service.getInterfaceDescriptor(); }
            catch (Exception ignored) {}
            Log.i(TAG, "SMARTSKY_BOUND component=" + name + " descriptor=" + descriptor);
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            smartSkyBinder = null;
            smartSkyBound = false;
            Log.w(TAG, "SMARTSKY_DISCONNECTED component=" + name);
        }

        @Override
        public void onBindingDied(ComponentName name) {
            smartSkyBinder = null;
            smartSkyBound = false;
            Log.w(TAG, "SMARTSKY_BINDING_DIED component=" + name);
            bindSmartSky();
        }

        @Override
        public void onNullBinding(ComponentName name) {
            smartSkyBinder = null;
            smartSkyBound = false;
            Log.e(TAG, "SMARTSKY_NULL_BINDING component=" + name);
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        bindSmartSky();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
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
        synchronized (lock) {
            closeAccessoryLocked();
            ioThread = new Thread(() -> runBridge(selected), "iretail-kozen-aoa-bridge");
            ioThread.start();
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        synchronized (lock) {
            closeAccessoryLocked();
        }
        if (smartSkyBound) {
            try { unbindService(smartSkyConnection); } catch (Exception ignored) {}
        }
        smartSkyBinder = null;
        smartSkyBound = false;
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    private void bindSmartSky() {
        if (smartSkyBound && smartSkyBinder != null && smartSkyBinder.isBinderAlive()) return;
        try {
            Intent intent = new Intent(SMARTSKY_ACTION);
            intent.setComponent(new ComponentName(SMARTSKY_PACKAGE, SMARTSKY_SERVICE));
            boolean ok = bindService(intent, smartSkyConnection, Context.BIND_AUTO_CREATE);
            Log.i(TAG, "SMARTSKY_BIND_REQUEST ok=" + ok);
            if (!ok) {
                smartSkyBound = false;
                smartSkyBinder = null;
            }
        } catch (Exception e) {
            smartSkyBound = false;
            smartSkyBinder = null;
            Log.e(TAG, "SMARTSKY_BIND_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
        }
    }

    private void runBridge(UsbAccessory accessory) {
        UsbManager manager = (UsbManager) getSystemService(USB_SERVICE);
        Log.i(TAG, "OPEN_ACCESSORY manufacturer=" + accessory.getManufacturer() +
                " model=" + accessory.getModel() + " version=" + accessory.getVersion());
        try {
            ParcelFileDescriptor localFd = manager.openAccessory(accessory);
            if (localFd == null) {
                Log.e(TAG, "OPEN_ACCESSORY_FAILED null fd");
                return;
            }
            synchronized (lock) { parcelFd = localFd; }

            FileInputStream input = new FileInputStream(localFd.getFileDescriptor());
            FileOutputStream output = new FileOutputStream(localFd.getFileDescriptor());
            BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8));
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(output, StandardCharsets.UTF_8));

            Log.i(TAG, "BRIDGE_READY transport=AOA bridge=" + BRIDGE_VERSION +
                    " smartsky=" + (isSmartSkyReady() ? "bound" : "not_bound"));
            String line;
            while ((line = reader.readLine()) != null) {
                String request = line.trim();
                if (request.isEmpty()) continue;
                Log.i(TAG, "RX " + safe(request));
                String response = handleRequest(request);
                writer.write(response);
                writer.write("\n");
                writer.flush();
                Log.i(TAG, "TX " + safe(response));
            }
            Log.i(TAG, "BRIDGE_EOF");
        } catch (Exception e) {
            Log.e(TAG, "BRIDGE_IO_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
        } finally {
            synchronized (lock) { closeAccessoryLocked(); }
        }
    }

    private String handleRequest(String request) {
        String[] parts = request.split("\\s+", 3);
        String command = parts[0].toUpperCase();
        String id = parts.length > 1 ? parts[1] : "0";
        String args = parts.length > 2 ? parts[2] : "";

        if ("PING".equals(command)) {
            return "PONG " + id +
                    " bridge=" + BRIDGE_VERSION +
                    " manufacturer=" + token(Build.MANUFACTURER) +
                    " model=" + token(Build.MODEL) +
                    " android=" + token(Build.VERSION.RELEASE) +
                    " sdk=" + Build.VERSION.SDK_INT;
        }
        if ("INFO".equals(command)) {
            return "INFO " + id +
                    " protocol=3" +
                    " transport=AOA" +
                    " role=kozen-payment-bridge" +
                    " bridge=" + BRIDGE_VERSION +
                    " smartsky=" + (isSmartSkyReady() ? "bound" : "not_bound") +
                    " commands=PING,INFO,GET_STATE,GET_TERMINAL_DATA,PAYMENT,GET_PAYMENT_STATUS";
        }
        if ("GET_STATE".equals(command)) return getSmartSkyStateResponse(id);
        if ("GET_TERMINAL_DATA".equals(command)) return getSmartSkyTerminalDataResponse(id);
        if ("PAYMENT".equals(command)) return payment(id, args);
        if ("GET_PAYMENT_STATUS".equals(command)) return getPaymentStatus(id);
        return "ERROR " + id + " code=UNKNOWN_COMMAND command=" + token(command);
    }

    private boolean isSmartSkyReady() {
        IBinder binder = smartSkyBinder;
        return smartSkyBound && binder != null && binder.isBinderAlive();
    }

    private int readState() throws Exception {
        IBinder binder = requireBinder();
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(SMARTSKY_DESCRIPTOR);
            if (!binder.transact(SMARTSKY_TX_GET_STATE, data, reply, 0)) throw new IllegalStateException("GET_STATE_TRANSACT_FALSE");
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
            if (!binder.transact(SMARTSKY_TX_GET_TERMINAL_DATA, data, reply, 0)) throw new IllegalStateException("GET_TERMINAL_DATA_TRANSACT_FALSE");
            reply.readException();
            int present = reply.readInt();
            if (present == 0) throw new IllegalStateException("GET_TERMINAL_DATA_NULL");
            return TerminalData.CREATOR.createFromParcel(reply);
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private IBinder requireBinder() {
        IBinder binder = smartSkyBinder;
        if (!smartSkyBound || binder == null || !binder.isBinderAlive()) {
            bindSmartSky();
            throw new IllegalStateException("SMARTSKY_NOT_BOUND");
        }
        return binder;
    }

    private String getSmartSkyStateResponse(String id) {
        try {
            int state = readState();
            String descriptor = "-";
            try { descriptor = requireBinder().getInterfaceDescriptor(); } catch (Exception ignored) {}
            Log.i(TAG, "SMARTSKY_GET_STATE_OK state=" + state + " descriptor=" + descriptor);
            return "STATE " + id + " code=0 state=" + state + " bound=true descriptor=" + token(descriptor);
        } catch (Exception e) {
            Log.e(TAG, "SMARTSKY_GET_STATE_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            return "STATE " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) + " message=" + token(safe(e.getMessage()));
        }
    }

    private String getSmartSkyTerminalDataResponse(String id) {
        try {
            TerminalData terminalData = readTerminalData();
            PaymentRoute route = findPaymentRoute(terminalData, null, null);
            int terminalCount = terminalData.getTerminals() == null ? 0 : terminalData.getTerminals().size();
            String currencies = route == null ? "-" : route.currency;

            Log.i(TAG, "SMARTSKY_GET_TERMINAL_DATA_OK code=" + terminalData.getCode() +
                    " defaultTid=" + token(terminalData.getTerminalId()) +
                    " terminals=" + terminalCount +
                    " payment=" + (route != null) +
                    " paymentTid=" + (route == null ? "-" : route.tid) +
                    " paymentType=" + (route == null ? "-" : route.type) +
                    " transactionType=" + (route == null ? "-" : route.transactionType) +
                    " currencies=" + currencies);

            return "TERMINAL_DATA " + id +
                    " code=" + terminalData.getCode() +
                    " message=" + token(terminalData.getMessage()) +
                    " terminalId=" + token(terminalData.getTerminalId()) +
                    " merchantId=" + token(terminalData.getMerchantId()) +
                    " serial=" + token(terminalData.getSerialNumber()) +
                    " tmsId=" + token(terminalData.getTmsId()) +
                    " terminals=" + terminalCount +
                    " payment=" + (route != null) +
                    " paymentTid=" + (route == null ? "-" : route.tid) +
                    " paymentType=" + (route == null ? "-" : route.type) +
                    " transactionType=" + (route == null ? "-" : route.transactionType) +
                    " currencies=" + currencies +
                    " bound=true";
        } catch (Exception e) {
            Log.e(TAG, "SMARTSKY_GET_TERMINAL_DATA_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            return "TERMINAL_DATA " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) + " message=" + token(safe(e.getMessage()));
        }
    }

    private PaymentRoute findPaymentRoute(TerminalData data, String requiredTid, String requiredCurrency) {
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
                Set<String> currencies = new LinkedHashSet<>();
                ArrayList<Currency> list = operation.getCurrencies();
                if (list != null) {
                    for (Currency currency : list) {
                        if (currency != null && currency.getCurrencyCode() != null) currencies.add(currency.getCurrencyCode().trim());
                    }
                }
                Log.i(TAG, "SMARTSKY_OPERATION tid=" + token(tid) + " name=" + token(operation.getName()) +
                        " type=" + token(type) + " transactionType=" + token(txType) +
                        " currencies=" + (currencies.isEmpty() ? "-" : join(currencies, ",")));

                boolean exactPayment = "00".equals(type) && "payment".equalsIgnoreCase(txType);
                if (!exactPayment) continue;
                String selectedCurrency = null;
                if (requiredCurrency != null) {
                    if (currencies.contains(requiredCurrency)) selectedCurrency = requiredCurrency;
                } else if (!currencies.isEmpty()) {
                    selectedCurrency = currencies.iterator().next();
                }
                if (selectedCurrency != null) return new PaymentRoute(tid, type, txType, selectedCurrency);
            }
        }
        return null;
    }

    private String payment(String requestId, String args) {
        synchronized (paymentLock) {
            if (!validRequestId(requestId)) {
                return "PAYMENT_RESULT " + token(requestId) + " status=BLOCKED code=BAD_REQUEST_ID approved=false noRetry=true";
            }

            SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
            String stored = prefs.getString(paymentResponseKey(requestId), null);
            String storedStatus = prefs.getString(paymentStatusKey(requestId), null);
            if (stored != null) {
                Log.w(TAG, "PAYMENT_DUPLICATE_REQUEST id=" + requestId + " storedStatus=" + storedStatus + " noRetry=true");
                return stored + " replayed=true";
            }
            if ("STARTED".equals(storedStatus)) {
                return "PAYMENT_RESULT " + requestId + " status=UNCERTAIN_RECOVERY_REQUIRED code=PREVIOUS_START_FOUND approved=false noRetry=true";
            }

            String active = prefs.getString(PREF_ACTIVE_REQUEST, "");
            if (active != null && !active.isEmpty() && !active.equals(requestId)) {
                return "PAYMENT_RESULT " + requestId + " status=BLOCKED code=ANOTHER_REQUEST_UNRESOLVED active=" + token(active) + " approved=false noRetry=true";
            }

            String amount = arg(args, "amount");
            String tid = arg(args, "terminalId");
            String currency = arg(args, "currency");
            if (!TEST_AMOUNT.equals(amount) || !TEST_CURRENCY.equals(currency) || tid == null || tid.isEmpty()) {
                return "PAYMENT_RESULT " + requestId + " status=BLOCKED code=TEST_CONSTRAINT_FAILED amount=" + token(amount) +
                        " terminalId=" + token(tid) + " currency=" + token(currency) + " approved=false noRetry=true";
            }

            try {
                int state = readState();
                if (state != 0) {
                    return "PAYMENT_RESULT " + requestId + " status=BLOCKED code=STATE_NOT_READY state=" + state + " approved=false noRetry=true";
                }
                TerminalData fresh = readTerminalData();
                PaymentRoute route = findPaymentRoute(fresh, tid, currency);
                if (route == null) {
                    return "PAYMENT_RESULT " + requestId + " status=BLOCKED code=FRESH_ROUTE_NOT_FOUND approved=false noRetry=true";
                }

                prefs.edit()
                        .putString(paymentStatusKey(requestId), "STARTED")
                        .putString(PREF_ACTIVE_REQUEST, requestId)
                        .putLong(paymentStartedKey(requestId), System.currentTimeMillis())
                        .apply();

                Log.w(TAG, "PAYMENT_CALL_BEGIN requestId=" + requestId + " amount=" + amount + " terminalId=" + tid + " currency=" + currency + " noAutoRetry=true");
                Bundle result = callPayment(requestId, new BigDecimal(amount), tid, currency);

                int code = result == null ? Integer.MIN_VALUE : result.getInt("code", Integer.MIN_VALUE);
                Object approvedRaw = result == null ? null : result.get("isApproved");
                Boolean approved = approvedRaw instanceof Boolean ? (Boolean) approvedRaw : null;
                String message = result == null ? null : result.getString("message");
                String rc = result == null ? null : result.getString("rc");
                String rrn = result == null ? null : result.getString("rrn");
                String authCode = result == null ? null : result.getString("authCode");
                Object amountRaw = result == null ? null : result.get("amount");
                String currencyResult = result == null ? null : result.getString("currencyCode");
                String tidResult = result == null ? null : result.getString("terminalId");
                Object receiptRaw = result == null ? null : result.get("receiptNumber");
                String txId = result == null ? null : result.getString("id");
                String type = result == null ? null : result.getString("type");

                String response = "PAYMENT_RESULT " + requestId +
                        " status=COMPLETED code=" + code +
                        " approved=" + (approved == null ? "null" : approved.toString()) +
                        " message=" + token(message) +
                        " rc=" + token(rc) +
                        " rrn=" + token(rrn) +
                        " authCode=" + token(authCode) +
                        " amount=" + token(amountRaw == null ? null : String.valueOf(amountRaw)) +
                        " currency=" + token(currencyResult) +
                        " terminalId=" + token(tidResult) +
                        " receipt=" + token(receiptRaw == null ? null : String.valueOf(receiptRaw)) +
                        " transactionId=" + token(txId) +
                        " type=" + token(type) +
                        " noRetry=true";

                prefs.edit()
                        .putString(paymentStatusKey(requestId), "COMPLETED")
                        .putString(paymentResponseKey(requestId), response)
                        .remove(PREF_ACTIVE_REQUEST)
                        .apply();

                Log.w(TAG, "PAYMENT_CALL_RESULT requestId=" + requestId + " code=" + code + " approved=" + approved +
                        " rrn=" + token(rrn) + " receipt=" + token(receiptRaw == null ? null : String.valueOf(receiptRaw)) +
                        " noAutoRetry=true");
                return response;
            } catch (Exception e) {
                String response = "PAYMENT_RESULT " + requestId + " status=UNCERTAIN code=EXCEPTION type=" +
                        token(e.getClass().getSimpleName()) + " message=" + token(safe(e.getMessage())) +
                        " approved=null noRetry=true";
                prefs.edit()
                        .putString(paymentStatusKey(requestId), "UNCERTAIN")
                        .putString(paymentResponseKey(requestId), response)
                        .putString(PREF_ACTIVE_REQUEST, requestId)
                        .apply();
                Log.e(TAG, "PAYMENT_CALL_UNCERTAIN requestId=" + requestId + " noAutoRetry=true " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
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
            if (!binder.transact(SMARTSKY_TX_PAYMENT, data, reply, 0)) throw new IllegalStateException("PAYMENT_TRANSACT_FALSE");
            reply.readException();
            int present = reply.readInt();
            if (present == 0) throw new IllegalStateException("PAYMENT_NULL_RESULT");
            Bundle result = reply.readBundle(getClassLoader());
            if (result != null) result.setClassLoader(getClassLoader());
            return result;
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private String getPaymentStatus(String requestId) {
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        String response = prefs.getString(paymentResponseKey(requestId), null);
        String status = prefs.getString(paymentStatusKey(requestId), null);
        if (response != null) return response + " statusQuery=true";
        if (status != null) return "PAYMENT_RESULT " + requestId + " status=" + token(status) + " code=NO_FINAL_RESULT approved=null noRetry=true statusQuery=true";
        return "PAYMENT_RESULT " + requestId + " status=UNKNOWN code=NOT_FOUND approved=null noRetry=true statusQuery=true";
    }

    private final class PaymentCallback extends Binder {
        PaymentCallback() { attachInterface(null, TRANSACTION_CALLBACK_DESCRIPTOR); }

        @Override
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
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
                    data.readString();
                    Log.i(TAG, "PAYMENT_CALLBACK_QR id=" + token(qrId) + " payload=redacted");
                    if (reply != null) reply.writeNoException();
                    return true;
                }
                case 3: {
                    Log.i(TAG, "PAYMENT_CALLBACK_RESERVED3");
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
        for (String part : args.split("\\s+")) {
            if (part.startsWith(prefix)) return part.substring(prefix.length());
        }
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

    private static String paymentStatusKey(String id) { return "payment." + id + ".status"; }
    private static String paymentResponseKey(String id) { return "payment." + id + ".response"; }
    private static String paymentStartedKey(String id) { return "payment." + id + ".started"; }

    private static String join(Set<String> values, String separator) {
        StringBuilder out = new StringBuilder();
        for (String value : values) {
            if (out.length() > 0) out.append(separator);
            out.append(value);
        }
        return out.toString();
    }

    private static String token(String value) {
        if (value == null || value.isEmpty()) return "-";
        return value.replace(' ', '_').replace('\n', '_').replace('\r', '_');
    }

    private static String safe(String value) {
        if (value == null) return "-";
        value = value.replace('\n', ' ').replace('\r', ' ');
        return value.length() <= 300 ? value : value.substring(0, 300);
    }
}
