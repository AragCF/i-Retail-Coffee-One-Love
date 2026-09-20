package com.coffeeonelove.iretail.aoarecovery;

import android.app.Activity;
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
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * JL22 read-only AOA transaction recovery client.
 * There is deliberately no PAYMENT/CANCEL/REFUND command in this application.
 */
public class AoaRecoveryActivity extends Activity {
    public static final String TAG = "IretailAoaRecovery";
    private static final String ACTION_USB_PERMISSION = "com.coffeeonelove.iretail.aoarecovery.USB_PERMISSION";

    private static final int KOZEN_VID = 0x0e8d;
    private static final int KOZEN_PID = 0x201c;
    private static final int GOOGLE_VID = 0x18d1;
    private static final int AOA_GET_PROTOCOL = 51;
    private static final int AOA_SEND_STRING = 52;
    private static final int AOA_START = 53;

    private static final String ACCESSORY_MANUFACTURER = "Coffee One Love";
    private static final String ACCESSORY_MODEL = "iRetail Kozen Recovery Bridge";
    private static final String ACCESSORY_DESCRIPTION = "i-Retail read-only transaction recovery";
    private static final String ACCESSORY_VERSION = "0.1";
    private static final String ACCESSORY_URI = "https://thesystem.pro/";
    private static final String ACCESSORY_SERIAL = "iretail-kozen-recovery";

    private UsbManager usbManager;
    private PendingIntent permissionIntent;
    private TextView output;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private volatile boolean rawPermissionRequested;
    private volatile boolean aoaPermissionRequested;
    private volatile boolean handshakeStarted;
    private volatile boolean linkStarted;

    private String terminalId;
    private UsbDeviceConnection linkConnection;
    private UsbInterface linkInterface;

    private final BroadcastReceiver permissionReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (!ACTION_USB_PERMISSION.equals(intent.getAction())) return;
            UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
            log("USB_PERMISSION granted=" + granted + " device=" + deviceSummary(device));
            if (!granted || device == null) {
                append("USB-разрешение не выдано. Операции записи отсутствуют.");
                log("RECOVERY_OVER_AOA_FAILED reason=USB_PERMISSION noFinancialCommands=true");
                return;
            }
            if (isRawKozen(device)) startHandshake(device);
            else if (isAoaDevice(device)) openAoaLink(device);
        }
    };

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        terminalId = getIntent().getStringExtra("terminal_id");
        if (terminalId == null || terminalId.trim().isEmpty()) terminalId = "12000679";
        terminalId = terminalId.trim();
        buildUi();

        int flags = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags |= PendingIntent.FLAG_IMMUTABLE;
        permissionIntent = PendingIntent.getBroadcast(
                this, 0, new Intent(ACTION_USB_PERMISSION).setPackage(getPackageName()), flags);
        registerReceiver(permissionReceiver, new IntentFilter(ACTION_USB_PERMISSION));

        append("i-Retail READ-ONLY transaction recovery");
        append("TID=" + terminalId);
        append("payment/cancel/refund/reconciliation отсутствуют в этом приложении.");
        append("Ожидание Kozen…");
        main.postDelayed(this::discoverAndStart, 400);
    }

    @Override protected void onDestroy() {
        try { unregisterReceiver(permissionReceiver); } catch (Exception ignored) {}
        executor.shutdownNow();
        closeLink();
        super.onDestroy();
    }

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (14 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("JL22 → AOA → Kozen\nВосстановление транзакции");
        title.setTextSize(21f);
        root.addView(title);

        output = new TextView(this);
        output.setTextSize(15f);
        output.setTextIsSelectable(true);
        output.setPadding(0, pad, 0, 0);
        root.addView(output);
        setContentView(root);
    }

    private void discoverAndStart() {
        UsbDevice aoa = findAoaDevice();
        if (aoa != null) {
            append("Kozen уже в AOA: " + deviceSummary(aoa));
            ensurePermissionForAoa(aoa);
            return;
        }
        UsbDevice raw = findRawKozen();
        if (raw == null) {
            append("Kozen пока не найден. Повтор через 1 с…");
            main.postDelayed(this::discoverAndStart, 1000);
            return;
        }
        append("Kozen найден: " + deviceSummary(raw));
        if (!usbManager.hasPermission(raw)) {
            if (!rawPermissionRequested) {
                rawPermissionRequested = true;
                log("REQUEST_RAW_USB_PERMISSION " + deviceSummary(raw));
                usbManager.requestPermission(raw, permissionIntent);
            }
            return;
        }
        startHandshake(raw);
    }

    private void startHandshake(UsbDevice raw) {
        if (handshakeStarted) return;
        handshakeStarted = true;
        executor.execute(() -> performHandshake(raw));
    }

    private void performHandshake(UsbDevice raw) {
        UsbDeviceConnection connection = usbManager.openDevice(raw);
        if (connection == null) {
            append("Не удалось открыть Kozen для AOA handshake.");
            log("RECOVERY_OVER_AOA_FAILED reason=RAW_OPEN noFinancialCommands=true");
            handshakeStarted = false;
            return;
        }
        try {
            byte[] protocol = new byte[2];
            int n = connection.controlTransfer(0xC0, AOA_GET_PROTOCOL, 0, 0, protocol, protocol.length, 1500);
            if (n != 2) throw new IllegalStateException("AOA_GET_PROTOCOL_" + n);
            int version = (protocol[0] & 0xff) | ((protocol[1] & 0xff) << 8);
            log("AOA_PROTOCOL=" + version);
            if (version < 1) throw new IllegalStateException("AOA_PROTOCOL_UNSUPPORTED_" + version);

            if (!sendString(connection, 0, ACCESSORY_MANUFACTURER) ||
                    !sendString(connection, 1, ACCESSORY_MODEL) ||
                    !sendString(connection, 2, ACCESSORY_DESCRIPTION) ||
                    !sendString(connection, 3, ACCESSORY_VERSION) ||
                    !sendString(connection, 4, ACCESSORY_URI) ||
                    !sendString(connection, 5, ACCESSORY_SERIAL)) {
                throw new IllegalStateException("AOA_IDENTIFICATION_FAILED");
            }
            int rc = connection.controlTransfer(0x40, AOA_START, 0, 0, null, 0, 1500);
            log("AOA_START rc=" + rc);
            append("AOA START отправлен. Жду recovery accessory…");
        } catch (Exception e) {
            append("Ошибка AOA handshake: " + e.getClass().getSimpleName());
            log("RECOVERY_OVER_AOA_FAILED reason=HANDSHAKE type=" + e.getClass().getSimpleName() +
                    " message=" + safe(e.getMessage()) + " noFinancialCommands=true");
            handshakeStarted = false;
            return;
        } finally {
            connection.close();
        }

        main.postDelayed(new Runnable() {
            private int attempts;
            @Override public void run() {
                UsbDevice aoa = findAoaDevice();
                if (aoa != null) {
                    ensurePermissionForAoa(aoa);
                    return;
                }
                attempts++;
                if (attempts >= 80) {
                    append("Тайм-аут повторного перечисления AOA.");
                    log("RECOVERY_OVER_AOA_FAILED reason=REENUMERATION_TIMEOUT noFinancialCommands=true");
                    return;
                }
                main.postDelayed(this, 500);
            }
        }, 500);
    }

    private boolean sendString(UsbDeviceConnection connection, int index, String value) {
        byte[] raw = value.getBytes(StandardCharsets.UTF_8);
        byte[] zero = new byte[raw.length + 1];
        System.arraycopy(raw, 0, zero, 0, raw.length);
        return connection.controlTransfer(0x40, AOA_SEND_STRING, 0, index, zero, zero.length, 1500) >= 0;
    }

    private void ensurePermissionForAoa(UsbDevice device) {
        if (usbManager.hasPermission(device)) {
            openAoaLink(device);
            return;
        }
        if (!aoaPermissionRequested) {
            aoaPermissionRequested = true;
            log("REQUEST_AOA_USB_PERMISSION " + deviceSummary(device));
            usbManager.requestPermission(device, permissionIntent);
        }
    }

    private void openAoaLink(UsbDevice device) {
        if (linkStarted) return;
        linkStarted = true;
        executor.execute(() -> runRecovery(device));
    }

    private void runRecovery(UsbDevice device) {
        UsbDeviceConnection connection = usbManager.openDevice(device);
        if (connection == null) {
            log("RECOVERY_OVER_AOA_FAILED reason=AOA_OPEN noFinancialCommands=true");
            linkStarted = false;
            return;
        }

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
                if (ep.getDirection() == UsbConstants.USB_DIR_OUT) candidateOut = ep;
            }
            if (candidateIn != null && candidateOut != null) {
                selected = candidate;
                in = candidateIn;
                out = candidateOut;
                break;
            }
        }
        if (selected == null || in == null || out == null || !connection.claimInterface(selected, true)) {
            connection.close();
            log("RECOVERY_OVER_AOA_FAILED reason=ENDPOINT_OR_CLAIM noFinancialCommands=true");
            return;
        }
        linkConnection = connection;
        linkInterface = selected;
        log("AOA_RECOVERY_BULK_READY device=" + deviceSummary(device));
        append("AOA read-only канал открыт.");

        try {
            bulkWrite(connection, out, "PING 2001\n");
            String pong = waitForLine(connection, in, "PONG 2001", "role=kozen-read-only-recovery", 90000L);
            if (pong == null) throw new IllegalStateException("RECOVERY_PONG_TIMEOUT");
            append("RX: " + pong);

            bulkWrite(connection, out, "INFO 2002\n");
            String info = waitForLine(connection, in, "INFO 2002", "financialCommands=NONE", 15000L);
            if (info == null) throw new IllegalStateException("RECOVERY_INFO_TIMEOUT");
            append("RX: " + info);

            String state = requestUntilOk(connection, in, out, "GET_STATE 2003\n", "STATE 2003", 20);
            if (state == null) throw new IllegalStateException("RECOVERY_STATE_FAILED");
            append("RX: " + state);

            String last = requestUntilTransaction(connection, in, out,
                    "GET_LAST_TRANSACTION 2004 terminalId=" + terminalId + "\n",
                    "LAST_TRANSACTION 2004", 20);
            if (last == null) throw new IllegalStateException("RECOVERY_LAST_TRANSACTION_FAILED");
            append("ПОСЛЕДНЯЯ ТРАНЗАКЦИЯ:\n" + last);
            log("RECOVERY_LAST_TRANSACTION_RESULT " + safe(last));

            String receipt = tokenValue(last, "receipt");
            String targeted = null;
            if (receipt != null && !receipt.isEmpty() && !"-".equals(receipt)) {
                targeted = requestUntilTransaction(connection, in, out,
                        "GET_TRANSACTION 2005 terminalId=" + terminalId + " receiptNumber=" + receipt + "\n",
                        "TRANSACTION 2005", 12);
                if (targeted != null) {
                    append("ПРОВЕРКА ПО ЧЕКУ " + receipt + ":\n" + targeted);
                    log("RECOVERY_TARGET_TRANSACTION_RESULT " + safe(targeted));
                }
            }

            log("RECOVERY_OVER_AOA_OK terminalId=" + terminalId + " receipt=" + safe(receipt) +
                    " targeted=" + (targeted != null) + " noFinancialCommands=true");
            append("ГОТОВО: история транзакции прочитана. Финансовых команд не выполнялось.");
        } catch (Exception e) {
            append("Ошибка безопасного чтения: " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            log("RECOVERY_OVER_AOA_FAILED type=" + e.getClass().getSimpleName() +
                    " message=" + safe(e.getMessage()) + " noFinancialCommands=true");
        }
    }

    private String requestUntilOk(UsbDeviceConnection c, UsbEndpoint in, UsbEndpoint out,
                                  String request, String prefix, int attempts) throws InterruptedException {
        for (int i = 1; i <= attempts; i++) {
            bulkWrite(c, out, request);
            String response = waitForLine(c, in, prefix, null, 4000L);
            if (response != null && response.contains("code=0")) return response;
            Thread.sleep(400L);
        }
        return null;
    }

    private String requestUntilTransaction(UsbDeviceConnection c, UsbEndpoint in, UsbEndpoint out,
                                           String request, String prefix, int attempts) throws InterruptedException {
        for (int i = 1; i <= attempts; i++) {
            bulkWrite(c, out, request);
            String response = waitForLine(c, in, prefix, null, 5000L);
            if (response != null && !response.contains("code=EXCEPTION") &&
                    !response.contains("code=BAD_")) return response;
            Thread.sleep(500L);
        }
        return null;
    }

    private String waitForLine(UsbDeviceConnection c, UsbEndpoint in, String prefix,
                               String requiredToken, long totalMs) {
        long deadline = System.currentTimeMillis() + totalMs;
        while (!Thread.currentThread().isInterrupted() && System.currentTimeMillis() < deadline) {
            String response = bulkRead(c, in, 1000);
            if (response == null) continue;
            for (String line : response.split("\\r?\\n")) {
                String trimmed = line.trim();
                if (!trimmed.startsWith(prefix)) continue;
                if (requiredToken != null && !trimmed.contains(requiredToken)) {
                    log("RECOVERY_RX_IGNORED " + safe(trimmed));
                    continue;
                }
                return trimmed;
            }
        }
        return null;
    }

    private static int bulkWrite(UsbDeviceConnection c, UsbEndpoint out, String text) {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        return c.bulkTransfer(out, bytes, bytes.length, 2000);
    }

    private static String bulkRead(UsbDeviceConnection c, UsbEndpoint in, int timeoutMs) {
        byte[] buffer = new byte[4096];
        int count = c.bulkTransfer(in, buffer, buffer.length, timeoutMs);
        if (count <= 0) return null;
        return new String(buffer, 0, count, StandardCharsets.UTF_8).trim();
    }

    private UsbDevice findRawKozen() {
        for (UsbDevice d : usbManager.getDeviceList().values()) if (isRawKozen(d)) return d;
        return null;
    }

    private UsbDevice findAoaDevice() {
        for (UsbDevice d : usbManager.getDeviceList().values()) if (isAoaDevice(d)) return d;
        return null;
    }

    private static boolean isRawKozen(UsbDevice d) {
        return d != null && d.getVendorId() == KOZEN_VID && d.getProductId() == KOZEN_PID;
    }

    private static boolean isAoaDevice(UsbDevice d) {
        if (d == null || d.getVendorId() != GOOGLE_VID) return false;
        int pid = d.getProductId();
        return pid >= 0x2d00 && pid <= 0x2d05;
    }

    private static String tokenValue(String line, String name) {
        if (line == null) return null;
        String prefix = name + "=";
        for (String part : line.split("\\s+")) if (part.startsWith(prefix)) return part.substring(prefix.length());
        return null;
    }

    private void append(String text) {
        log("UI " + text.replace('\n', ' '));
        main.post(() -> { if (output != null) output.append((output.length() == 0 ? "" : "\n") + text); });
    }

    private static void log(String text) { Log.i(TAG, text); }

    private static String deviceSummary(UsbDevice d) {
        if (d == null) return "null";
        return String.format(Locale.US, "%04x:%04x name=%s", d.getVendorId(), d.getProductId(), d.getDeviceName());
    }

    private void closeLink() {
        UsbDeviceConnection c = linkConnection;
        UsbInterface i = linkInterface;
        linkConnection = null;
        linkInterface = null;
        if (c != null) {
            try { if (i != null) c.releaseInterface(i); } catch (Exception ignored) {}
            try { c.close(); } catch (Exception ignored) {}
        }
    }

    private static String safe(String value) {
        if (value == null) return "-";
        value = value.replace('\n', ' ').replace('\r', ' ');
        return value.length() <= 900 ? value : value.substring(0, 900);
    }
}
