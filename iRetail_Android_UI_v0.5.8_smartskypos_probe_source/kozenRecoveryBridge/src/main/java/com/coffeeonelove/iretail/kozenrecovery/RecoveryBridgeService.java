package com.coffeeonelove.iretail.kozenrecovery;

import android.app.Service;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.hardware.usb.UsbAccessory;
import android.hardware.usb.UsbManager;
import android.os.Bundle;
import android.os.IBinder;
import android.os.Parcel;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;

/**
 * Read-only SmartSkyPOS transaction recovery bridge.
 *
 * This service intentionally contains no Binder transaction for payment, cancel, refund,
 * reconciliation or report. It only exposes state and transaction lookup operations.
 */
public class RecoveryBridgeService extends Service {
    private static final String TAG = "IretailKozenRecovery";
    private static final String BRIDGE_VERSION = "0.1.0";

    private static final String SMARTSKY_ACTION = "com.skytech.smartskypos.ISmartSkyPos";
    private static final String SMARTSKY_PACKAGE = "com.skytech.smartskypos";
    private static final String SMARTSKY_SERVICE = "com.crestwavetech.smartskyposservice.SmartSkyPosService";
    private static final String SMARTSKY_DESCRIPTOR = "com.skytech.smartskyposlib.ISmartSkyPos";

    private static final int TX_GET_STATE = 1;
    private static final int TX_GET_LAST_TRANSACTION = 20;
    private static final int TX_GET_TRANSACTION = 21;

    private final Object lock = new Object();
    private Thread ioThread;
    private ParcelFileDescriptor parcelFd;

    private volatile IBinder smartSkyBinder;
    private volatile boolean smartSkyBound;

    private final ServiceConnection smartSkyConnection = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder service) {
            smartSkyBinder = service;
            smartSkyBound = true;
            String descriptor = "-";
            try { descriptor = service == null ? "-" : service.getInterfaceDescriptor(); }
            catch (Exception ignored) {}
            Log.i(TAG, "SMARTSKY_BOUND component=" + name + " descriptor=" + descriptor);
        }

        @Override public void onServiceDisconnected(ComponentName name) {
            smartSkyBinder = null;
            smartSkyBound = false;
            Log.w(TAG, "SMARTSKY_DISCONNECTED component=" + name);
        }

        @Override public void onBindingDied(ComponentName name) {
            smartSkyBinder = null;
            smartSkyBound = false;
            Log.w(TAG, "SMARTSKY_BINDING_DIED component=" + name);
            bindSmartSky();
        }

        @Override public void onNullBinding(ComponentName name) {
            smartSkyBinder = null;
            smartSkyBound = false;
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
        synchronized (lock) {
            closeAccessoryLocked();
            ioThread = new Thread(() -> runBridge(selected), "iretail-kozen-recovery-aoa");
            ioThread.start();
        }
        return START_NOT_STICKY;
    }

    @Override public void onDestroy() {
        synchronized (lock) { closeAccessoryLocked(); }
        if (smartSkyBound) {
            try { unbindService(smartSkyConnection); } catch (Exception ignored) {}
        }
        smartSkyBinder = null;
        smartSkyBound = false;
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }

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
        Log.i(TAG, "OPEN_ACCESSORY manufacturer=" + token(accessory.getManufacturer()) +
                " model=" + token(accessory.getModel()) + " version=" + token(accessory.getVersion()));
        try {
            ParcelFileDescriptor localFd = manager.openAccessory(accessory);
            if (localFd == null) {
                Log.e(TAG, "OPEN_ACCESSORY_FAILED null_fd");
                return;
            }
            synchronized (lock) { parcelFd = localFd; }
            BufferedReader reader = new BufferedReader(new InputStreamReader(
                    new FileInputStream(localFd.getFileDescriptor()), StandardCharsets.UTF_8));
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
                    new FileOutputStream(localFd.getFileDescriptor()), StandardCharsets.UTF_8));

            Log.i(TAG, "RECOVERY_BRIDGE_READY transport=AOA bridge=" + BRIDGE_VERSION +
                    " smartsky=" + (isSmartSkyReady() ? "bound" : "not_bound") +
                    " safety=READ_ONLY_NO_FINANCIAL_COMMANDS");
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
            Log.i(TAG, "RECOVERY_BRIDGE_EOF");
        } catch (Exception e) {
            Log.e(TAG, "RECOVERY_BRIDGE_IO_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
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
            return "PONG " + id + " bridge=" + BRIDGE_VERSION +
                    " role=kozen-read-only-recovery safety=READ_ONLY";
        }
        if ("INFO".equals(command)) {
            return "INFO " + id + " protocol=1 transport=AOA role=kozen-read-only-recovery" +
                    " bridge=" + BRIDGE_VERSION +
                    " smartsky=" + (isSmartSkyReady() ? "bound" : "not_bound") +
                    " commands=PING,INFO,GET_STATE,GET_LAST_TRANSACTION,GET_TRANSACTION" +
                    " financialCommands=NONE";
        }
        if ("GET_STATE".equals(command)) return getStateResponse(id);
        if ("GET_LAST_TRANSACTION".equals(command)) {
            return getLastTransactionResponse(id, arg(args, "terminalId"));
        }
        if ("GET_TRANSACTION".equals(command)) {
            return getTransactionResponse(id, arg(args, "terminalId"), arg(args, "receiptNumber"));
        }
        return "ERROR " + id + " code=UNKNOWN_COMMAND command=" + token(command) + " safety=READ_ONLY";
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

    private String getStateResponse(String id) {
        try {
            IBinder binder = requireBinder();
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                data.writeInterfaceToken(SMARTSKY_DESCRIPTOR);
                if (!binder.transact(TX_GET_STATE, data, reply, 0)) throw new IllegalStateException("GET_STATE_TRANSACT_FALSE");
                reply.readException();
                int state = reply.readInt();
                Log.i(TAG, "RECOVERY_GET_STATE_OK state=" + state);
                return "STATE " + id + " code=0 state=" + state + " safety=READ_ONLY";
            } finally {
                data.recycle();
                reply.recycle();
            }
        } catch (Exception e) {
            return "STATE " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) +
                    " message=" + token(safe(e.getMessage())) + " safety=READ_ONLY";
        }
    }

    private String getLastTransactionResponse(String id, String terminalId) {
        if (terminalId == null || terminalId.isEmpty()) {
            return "LAST_TRANSACTION " + id + " code=BAD_TERMINAL_ID safety=READ_ONLY";
        }
        try {
            Bundle result = callTransactionLookup(TX_GET_LAST_TRANSACTION, terminalId, null);
            String response = transactionSummary("LAST_TRANSACTION", id, result);
            Log.i(TAG, "RECOVERY_LAST_TRANSACTION_OK terminalId=" + token(terminalId) + " " + safe(response));
            return response;
        } catch (Exception e) {
            Log.e(TAG, "RECOVERY_LAST_TRANSACTION_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            return "LAST_TRANSACTION " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) +
                    " message=" + token(safe(e.getMessage())) + " safety=READ_ONLY";
        }
    }

    private String getTransactionResponse(String id, String terminalId, String receiptNumber) {
        if (terminalId == null || terminalId.isEmpty() || receiptNumber == null || receiptNumber.isEmpty()) {
            return "TRANSACTION " + id + " code=BAD_LOOKUP_PARAMS safety=READ_ONLY";
        }
        try {
            Bundle result = callTransactionLookup(TX_GET_TRANSACTION, terminalId, receiptNumber);
            String response = transactionSummary("TRANSACTION", id, result);
            Log.i(TAG, "RECOVERY_TRANSACTION_OK terminalId=" + token(terminalId) +
                    " receipt=" + token(receiptNumber) + " " + safe(response));
            return response;
        } catch (Exception e) {
            Log.e(TAG, "RECOVERY_TRANSACTION_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            return "TRANSACTION " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) +
                    " message=" + token(safe(e.getMessage())) + " safety=READ_ONLY";
        }
    }

    private Bundle callTransactionLookup(int transactionCode, String terminalId, String receiptNumber) throws Exception {
        IBinder binder = requireBinder();
        Bundle params = new Bundle();
        params.putString("terminalId", terminalId);
        params.putString("id", receiptNumber == null ? "recover1" : "recover2");
        if (receiptNumber != null) params.putString("receiptNumber", receiptNumber);

        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(SMARTSKY_DESCRIPTOR);
            data.writeInt(1);
            data.writeBundle(params);
            if (!binder.transact(transactionCode, data, reply, 0)) {
                throw new IllegalStateException("TRANSACTION_LOOKUP_TRANSACT_FALSE_" + transactionCode);
            }
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

    /** Only non-sensitive transaction fields are returned. PAN/EMV/cardholder/slips are never read or logged. */
    private static String transactionSummary(String prefix, String id, Bundle result) {
        boolean codePresent = result.containsKey("code");
        int code = result.getInt("code"); // matches recovered SDK getter: missing key -> 0
        Object approvedRaw = result.get("isApproved");
        String approved = approvedRaw instanceof Boolean ? approvedRaw.toString() : "null";
        boolean approvedPresent = result.containsKey("isApproved");

        return prefix + " " + id +
                " code=" + code +
                " codePresent=" + codePresent +
                " approved=" + approved +
                " approvedPresent=" + approvedPresent +
                " message=" + token(result.getString("message")) +
                " rc=" + token(result.getString("rc")) +
                " alternativeRc=" + token(result.getString("alternativeRc")) +
                " rrn=" + token(result.getString("rrn")) +
                " alternativeRrn=" + token(result.getString("alternativeRrn")) +
                " authCode=" + token(result.getString("authCode")) +
                " amount=" + token(objectString(result.get("amount"))) +
                " currency=" + token(result.getString("currencyCode")) +
                " terminalId=" + token(result.getString("terminalId")) +
                " receipt=" + token(objectString(result.get("receiptNumber"))) +
                " transactionId=" + token(result.getString("id")) +
                " type=" + token(result.getString("type")) +
                " safety=READ_ONLY sensitiveFields=OMITTED";
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

    private static String objectString(Object value) { return value == null ? null : String.valueOf(value); }

    private static String token(String value) {
        if (value == null || value.isEmpty()) return "-";
        return value.replace(' ', '_').replace('\n', '_').replace('\r', '_');
    }

    private static String safe(String value) {
        if (value == null) return "-";
        value = value.replace('\n', ' ').replace('\r', ' ');
        return value.length() <= 600 ? value : value.substring(0, 600);
    }
}
