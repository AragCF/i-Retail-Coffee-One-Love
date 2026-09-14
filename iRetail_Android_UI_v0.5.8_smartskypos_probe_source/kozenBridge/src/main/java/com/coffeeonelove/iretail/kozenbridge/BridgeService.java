package com.coffeeonelove.iretail.kozenbridge;

import android.app.Service;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.hardware.usb.UsbAccessory;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.IBinder;
import android.os.Parcel;
import android.os.ParcelFileDescriptor;
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
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * USB/AOA bridge running locally on Kozen P12.
 *
 * Financial operations are intentionally NOT implemented here yet.
 * SmartSkyPOS integration in this version is read-only and exposes only:
 *   Binder transaction #1 (getState)
 *   Binder transaction #4 (getTerminalData)
 */
public class BridgeService extends Service {
    private static final String TAG = "IretailKozenBridge";
    private static final String BRIDGE_VERSION = "0.3.1";

    private static final String SMARTSKY_ACTION = "com.skytech.smartskypos.ISmartSkyPos";
    private static final String SMARTSKY_PACKAGE = "com.skytech.smartskypos";
    private static final String SMARTSKY_SERVICE = "com.crestwavetech.smartskyposservice.SmartSkyPosService";
    private static final String SMARTSKY_DESCRIPTOR = "com.skytech.smartskyposlib.ISmartSkyPos";
    private static final int SMARTSKY_TX_GET_STATE = 1;
    private static final int SMARTSKY_TX_GET_TERMINAL_DATA = 4;

    private final Object lock = new Object();
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
    public IBinder onBind(Intent intent) {
        return null;
    }

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
            synchronized (lock) {
                parcelFd = localFd;
            }

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
            synchronized (lock) {
                closeAccessoryLocked();
            }
        }
    }

    private String handleRequest(String request) {
        String[] parts = request.split("\\s+", 3);
        String command = parts[0].toUpperCase();
        String id = parts.length > 1 ? parts[1] : "0";

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
                    " protocol=2" +
                    " transport=AOA" +
                    " role=kozen-payment-bridge" +
                    " bridge=" + BRIDGE_VERSION +
                    " smartsky=" + (isSmartSkyReady() ? "bound" : "not_bound") +
                    " commands=PING,INFO,GET_STATE,GET_TERMINAL_DATA";
        }
        if ("GET_STATE".equals(command)) {
            return getSmartSkyStateResponse(id);
        }
        if ("GET_TERMINAL_DATA".equals(command)) {
            return getSmartSkyTerminalDataResponse(id);
        }
        return "ERROR " + id + " code=UNKNOWN_COMMAND command=" + token(command);
    }

    private boolean isSmartSkyReady() {
        IBinder binder = smartSkyBinder;
        return smartSkyBound && binder != null && binder.isBinderAlive();
    }

    private String getSmartSkyStateResponse(String id) {
        IBinder binder = smartSkyBinder;
        if (!smartSkyBound || binder == null || !binder.isBinderAlive()) {
            bindSmartSky();
            return "STATE " + id + " code=NOT_BOUND bound=false";
        }

        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(SMARTSKY_DESCRIPTOR);
            boolean transacted = binder.transact(SMARTSKY_TX_GET_STATE, data, reply, 0);
            if (!transacted) {
                Log.e(TAG, "SMARTSKY_GET_STATE transact=false");
                return "STATE " + id + " code=TRANSACT_FALSE bound=true";
            }
            reply.readException();
            int state = reply.readInt();
            String descriptor = "-";
            try { descriptor = binder.getInterfaceDescriptor(); } catch (Exception ignored) {}
            Log.i(TAG, "SMARTSKY_GET_STATE_OK state=" + state + " descriptor=" + descriptor);
            return "STATE " + id + " code=0 state=" + state + " bound=true descriptor=" + token(descriptor);
        } catch (Exception e) {
            Log.e(TAG, "SMARTSKY_GET_STATE_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            if (!binder.isBinderAlive()) {
                smartSkyBinder = null;
                smartSkyBound = false;
                bindSmartSky();
            }
            return "STATE " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) +
                    " message=" + token(safe(e.getMessage()));
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private String getSmartSkyTerminalDataResponse(String id) {
        IBinder binder = smartSkyBinder;
        if (!smartSkyBound || binder == null || !binder.isBinderAlive()) {
            bindSmartSky();
            return "TERMINAL_DATA " + id + " code=NOT_BOUND bound=false";
        }

        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(SMARTSKY_DESCRIPTOR);
            boolean transacted = binder.transact(SMARTSKY_TX_GET_TERMINAL_DATA, data, reply, 0);
            if (!transacted) {
                Log.e(TAG, "SMARTSKY_GET_TERMINAL_DATA transact=false");
                return "TERMINAL_DATA " + id + " code=TRANSACT_FALSE bound=true";
            }
            reply.readException();
            int present = reply.readInt();
            if (present == 0) {
                Log.e(TAG, "SMARTSKY_GET_TERMINAL_DATA null result");
                return "TERMINAL_DATA " + id + " code=NULL_RESULT bound=true";
            }

            TerminalData terminalData = TerminalData.CREATOR.createFromParcel(reply);
            ArrayList<Terminal> terminals = terminalData.getTerminals();
            int terminalCount = terminals == null ? 0 : terminals.size();

            String paymentTid = "-";
            String paymentType = "-";
            String transactionType = "-";
            Set<String> currencyCodes = new LinkedHashSet<>();

            if (terminals != null) {
                for (Terminal terminal : terminals) {
                    if (terminal == null) continue;
                    ArrayList<Operation> operations = terminal.getOperations();
                    if (operations == null) {
                        Log.i(TAG, "SMARTSKY_TERMINAL tid=" + token(terminal.getTerminalId()) + " operations=null");
                        continue;
                    }
                    for (Operation operation : operations) {
                        if (operation == null) continue;
                        String type = operation.getType();
                        String txType = operation.getTransactionType();
                        String name = operation.getName();

                        ArrayList<Currency> currencies = operation.getCurrencies();
                        Set<String> operationCurrencyCodes = new LinkedHashSet<>();
                        if (currencies != null) {
                            for (Currency currency : currencies) {
                                if (currency == null) continue;
                                String code = currency.getCurrencyCode();
                                if (code != null && !code.trim().isEmpty()) operationCurrencyCodes.add(code.trim());
                            }
                        }
                        Log.i(TAG, "SMARTSKY_OPERATION tid=" + token(terminal.getTerminalId()) +
                                " name=" + token(name) +
                                " type=" + token(type) +
                                " transactionType=" + token(txType) +
                                " currencies=" + (operationCurrencyCodes.isEmpty() ? "-" : join(operationCurrencyCodes, ",")));

                        // Recovered SmartSkyPOS 1.9.19 layout observed on the real P12:
                        //   name=Оплата, type=00, transactionType=payment.
                        // Accept both semantic layouts defensively, but never infer a payment route
                        // from TID/currency alone.
                        boolean isPayment = "00".equalsIgnoreCase(type) ||
                                "payment".equalsIgnoreCase(txType) ||
                                "payment".equalsIgnoreCase(type) ||
                                "00".equalsIgnoreCase(txType);
                        if (!isPayment) continue;

                        paymentTid = token(terminal.getTerminalId());
                        paymentType = token(type);
                        transactionType = token(txType);
                        currencyCodes.addAll(operationCurrencyCodes);
                        break;
                    }
                    if (!"-".equals(paymentTid)) break;
                }
            }

            String currencies = currencyCodes.isEmpty() ? "-" : join(currencyCodes, ",");
            boolean paymentSupported = !"-".equals(paymentTid);

            Log.i(TAG, "SMARTSKY_GET_TERMINAL_DATA_OK code=" + terminalData.getCode() +
                    " defaultTid=" + token(terminalData.getTerminalId()) +
                    " terminals=" + terminalCount +
                    " payment=" + paymentSupported +
                    " paymentTid=" + paymentTid +
                    " paymentType=" + paymentType +
                    " transactionType=" + transactionType +
                    " currencies=" + currencies);

            return "TERMINAL_DATA " + id +
                    " code=" + terminalData.getCode() +
                    " message=" + token(terminalData.getMessage()) +
                    " terminalId=" + token(terminalData.getTerminalId()) +
                    " merchantId=" + token(terminalData.getMerchantId()) +
                    " serial=" + token(terminalData.getSerialNumber()) +
                    " tmsId=" + token(terminalData.getTmsId()) +
                    " terminals=" + terminalCount +
                    " payment=" + paymentSupported +
                    " paymentTid=" + paymentTid +
                    " paymentType=" + paymentType +
                    " transactionType=" + transactionType +
                    " currencies=" + currencies +
                    " bound=true";
        } catch (Exception e) {
            Log.e(TAG, "SMARTSKY_GET_TERMINAL_DATA_ERROR " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            if (!binder.isBinderAlive()) {
                smartSkyBinder = null;
                smartSkyBound = false;
                bindSmartSky();
            }
            return "TERMINAL_DATA " + id + " code=EXCEPTION type=" + token(e.getClass().getSimpleName()) +
                    " message=" + token(safe(e.getMessage()));
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private void closeAccessoryLocked() {
        if (ioThread != null && ioThread != Thread.currentThread()) {
            ioThread.interrupt();
        }
        ioThread = null;
        if (parcelFd != null) {
            try { parcelFd.close(); } catch (Exception ignored) {}
            parcelFd = null;
        }
    }

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
        return value.length() <= 240 ? value : value.substring(0, 240);
    }
}
