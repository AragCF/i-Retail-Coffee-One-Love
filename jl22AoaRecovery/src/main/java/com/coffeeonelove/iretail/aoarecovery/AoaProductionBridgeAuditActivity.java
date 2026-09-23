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
 * Read-only JL22 audit client for the production Kozen payment bridge.
 *
 * The client deliberately contains no PAYMENT/CANCEL/REFUND/RECONCILIATION command.
 * It proves the production bridge can expose state, terminal route and durable transaction
 * recovery before the main i-Retail UI is allowed to use financial commands.
 */
public class AoaProductionBridgeAuditActivity extends Activity {
    public static final String TAG = "IretailProdAudit";
    private static final String ACTION_USB_PERMISSION = "com.coffeeonelove.iretail.aoarecovery.PROD_USB_PERMISSION";

    private static final int KOZEN_VID = 0x0e8d;
    private static final int KOZEN_PID = 0x201c;
    private static final int GOOGLE_VID = 0x18d1;
    private static final int AOA_GET_PROTOCOL = 51;
    private static final int AOA_SEND_STRING = 52;
    private static final int AOA_START = 53;

    private static final String ACCESSORY_MANUFACTURER = "Coffee One Love";
    private static final String ACCESSORY_MODEL = "iRetail Kozen Payment Bridge";
    private static final String ACCESSORY_DESCRIPTION = "i-Retail production bridge read-only audit";
    private static final String ACCESSORY_VERSION = "0.5";
    private static final String ACCESSORY_URI = "https://thesystem.pro/";
    private static final String ACCESSORY_SERIAL = "iretail-kozen-production-audit";

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
    private boolean routeOnly;
    private UsbDeviceConnection linkConnection;
    private UsbInterface linkInterface;

    private final BroadcastReceiver permissionReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (!ACTION_USB_PERMISSION.equals(intent.getAction())) return;
            UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
            log("USB_PERMISSION granted=" + granted + " device=" + deviceSummary(device));
            if (!granted || device == null) {
                fail("USB_PERMISSION");
                return;
            }
            if (isRawKozen(device)) startHandshake(device);
            else if (isAoaDevice(device)) openAoaLink(device);
        }
    };

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        terminalId = getIntent() == null ? null : getIntent().getStringExtra("terminal_id");
        if (terminalId == null || terminalId.trim().isEmpty()) terminalId = "12000679";
        terminalId = terminalId.trim();
        routeOnly = getIntent() != null && getIntent().getBooleanExtra("route_only", false);
        buildUi();

        int flags = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags |= PendingIntent.FLAG_IMMUTABLE;
        permissionIntent = PendingIntent.getBroadcast(
                this, 0, new Intent(ACTION_USB_PERMISSION).setPackage(getPackageName()), flags);
        registerReceiver(permissionReceiver, new IntentFilter(ACTION_USB_PERMISSION));

        append("i-Retail PRODUCTION BRIDGE SAFE AUDIT");
        append(routeOnly ? "Режим: только проверка платёжного маршрута" : "TID=" + terminalId);
        append("Команды оплаты, отмены, возврата и сверки в этом клиенте отсутствуют.");
        append("Ожидание Kozen…");
        main.postDelayed(this::discoverAndStart, 400L);
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
        title.setText("JL22 → AOA → Kozen\nАудит production bridge");
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
            main.postDelayed(this::discoverAndStart, 1000L);
            return;
        }
        append("Kozen найден: " + deviceSummary(raw));
        if (!usbManager.hasPermission(raw)) {
            if (!rawPermissionRequested) {
                rawPermissionRequested = true;
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
            fail("RAW_OPEN");
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
            append("AOA START отправлен. Жду production bridge…");
        } catch (Exception e) {
            fail("HANDSHAKE_" + e.getClass().getSimpleName() + "_" + safe(e.getMessage()));
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
                    fail("REENUMERATION_TIMEOUT");
                    return;
                }
                main.postDelayed(this, 500L);
            }
        }, 500L);
    }

    private boolean sendString(UsbDeviceConnection c, int index, String value) {
        byte[] raw = value.getBytes(StandardCharsets.UTF_8);
        byte[] zero = new byte[raw.length + 1];
        System.arraycopy(raw, 0, zero, 0, raw.length);
        return c.controlTransfer(0x40, AOA_SEND_STRING, 0, index, zero, zero.length, 1500) >= 0;
    }

    private void ensurePermissionForAoa(UsbDevice device) {
        if (usbManager.hasPermission(device)) {
            openAoaLink(device);
            return;
        }
        if (!aoaPermissionRequested) {
            aoaPermissionRequested = true;
            usbManager.requestPermission(device, permissionIntent);
        }
    }

    private void openAoaLink(UsbDevice device) {
        if (linkStarted) return;
        linkStarted = true;
        executor.execute(() -> runAudit(device));
    }

    private void runAudit(UsbDevice device) {
        UsbDeviceConnection connection = usbManager.openDevice(device);
        if (connection == null) {
            fail("AOA_OPEN");
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
            fail("ENDPOINT_OR_CLAIM");
            return;
        }

        linkConnection = connection;
        linkInterface = selected;
        log("PROD_AUDIT_BULK_READY device=" + deviceSummary(device));
        append("AOA read-only audit channel открыт.");

        try {
            bulkWrite(connection, out, "PING 3001\n");
            String pong = waitForLine(connection, in, "PONG 3001", "role=kozen-payment-bridge", 90000L);
            if (pong == null) throw new IllegalStateException("PONG_TIMEOUT");
            append("RX: " + pong);

            bulkWrite(connection, out, "INFO 3002\n");
            String info = waitForLine(connection, in, "INFO 3002", "paymentPolicy=EXPLICIT_SINGLE_NO_AUTO_RETRY", 15000L);
            if (info == null ||
                    !info.contains("protocol=4") ||
                    !info.contains("bridge=0.5.2") ||
                    !info.contains("role=kozen-payment-bridge")) {
                throw new IllegalStateException("INFO_INCOMPATIBLE_BRIDGE");
            }
            append("RX: " + info);

            String state = requestUntil(connection, in, out, "GET_STATE 3003\n", "STATE 3003", 20);
            if (state == null || !state.contains("code=0") || !state.contains("state=0")) {
                throw new IllegalStateException("STATE_NOT_READY");
            }
            append("RX: " + state);

            String terminalData = requestUntil(connection, in, out, "GET_TERMINAL_DATA 3004\n", "TERMINAL_DATA 3004", 20);
            if (terminalData == null || !terminalData.contains("code=0") ||
                    !terminalData.contains("payment=true") || !terminalData.contains("currencies=643")) {
                throw new IllegalStateException("TERMINAL_DATA_NOT_READY");
            }
            append("RX: " + terminalData);
            log("PROD_AUDIT_TERMINAL_DATA " + safe(terminalData));

            if (routeOnly) {
                log("PROD_BRIDGE_PREFLIGHT_OK bridge=0.5.2 protocol=4 paymentPolicy=EXPLICIT_SINGLE_NO_AUTO_RETRY financialCommandsSent=false transactionQueriesSent=false");
                append("ГОТОВО: платёжный маршрут Kozen / SmartSkyPOS готов. Финансовых команд не отправлялось.");
                return;
            }

            String last = requestUntil(connection, in, out,
                    "GET_LAST_TRANSACTION 3005 terminalId=" + terminalId + "\n",
                    "LAST_TRANSACTION 3005", 20);
            if (last == null || last.contains("code=EXCEPTION") || last.contains("code=BAD_")) {
                throw new IllegalStateException("LAST_TRANSACTION_FAILED");
            }
            append("ПОСЛЕДНЯЯ ТРАНЗАКЦИЯ:\n" + last);
            log("PROD_AUDIT_LAST_TRANSACTION " + safe(last));

            String receipt = tokenValue(last, "receipt");
            String targeted = null;
            if (receipt != null && !receipt.isEmpty() && !"-".equals(receipt)) {
                targeted = requestUntil(connection, in, out,
                        "GET_TRANSACTION 3006 terminalId=" + terminalId + " receiptNumber=" + receipt + "\n",
                        "TRANSACTION 3006", 12);
                if (targeted == null || targeted.contains("code=EXCEPTION") || targeted.contains("code=BAD_")) {
                    throw new IllegalStateException("TARGET_TRANSACTION_FAILED");
                }
                append("ПРОВЕРКА ПО ЧЕКУ " + receipt + ":\n" + targeted);
                log("PROD_AUDIT_TARGET_TRANSACTION " + safe(targeted));
            }

            log("PROD_BRIDGE_AUDIT_OK terminalId=" + terminalId + " receipt=" + safe(receipt) +
                    " targeted=" + (targeted != null) + " financialCommandsSent=false");
            append("ГОТОВО: production bridge прошёл безопасный аудит. Финансовых команд не отправлялось.");
        } catch (Exception e) {
            append("Ошибка аудита: " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            fail(e.getClass().getSimpleName() + "_" + safe(e.getMessage()));
        }
    }

    private String requestUntil(UsbDeviceConnection c, UsbEndpoint in, UsbEndpoint out,
                                String request, String prefix, int attempts) throws InterruptedException {
        for (int i = 1; i <= attempts; i++) {
            bulkWrite(c, out, request);
            String response = waitForLine(c, in, prefix, null, 5000L);
            if (response != null) return response;
            Thread.sleep(400L);
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
                    log("PROD_AUDIT_RX_IGNORED " + safe(trimmed));
                    continue;
                }
                return trimmed;
            }
        }
        return null;
    }

    private int bulkWrite(UsbDeviceConnection c, UsbEndpoint out, String text) {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        int rc = c.bulkTransfer(out, bytes, bytes.length, 3000);
        log("PROD_AUDIT_TX bytes=" + rc + " text=" + safe(text.trim()));
        return rc;
    }

    private String bulkRead(UsbDeviceConnection c, UsbEndpoint in, int timeout) {
        byte[] buffer = new byte[4096];
        int n = c.bulkTransfer(in, buffer, buffer.length, timeout);
        if (n <= 0) return null;
        String s = new String(buffer, 0, n, StandardCharsets.UTF_8);
        log("PROD_AUDIT_RX bytes=" + n + " text=" + safe(s.trim()));
        return s;
    }

    private UsbDevice findRawKozen() {
        for (UsbDevice device : usbManager.getDeviceList().values()) if (isRawKozen(device)) return device;
        return null;
    }

    private UsbDevice findAoaDevice() {
        for (UsbDevice device : usbManager.getDeviceList().values()) if (isAoaDevice(device)) return device;
        return null;
    }

    private static boolean isRawKozen(UsbDevice d) {
        return d != null && d.getVendorId() == KOZEN_VID && d.getProductId() == KOZEN_PID;
    }

    private static boolean isAoaDevice(UsbDevice d) {
        if (d == null || d.getVendorId() != GOOGLE_VID) return false;
        int p = d.getProductId();
        return p >= 0x2d00 && p <= 0x2d05;
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

    private void fail(String reason) {
        log("PROD_BRIDGE_AUDIT_FAILED reason=" + safe(reason) + " financialCommandsSent=false");
    }

    private void append(String text) {
        log("UI " + text.replace('\n', ' '));
        main.post(() -> {
            if (output == null) return;
            String current = output.getText() == null ? "" : output.getText().toString();
            output.setText(current.isEmpty() ? text : current + "\n\n" + text);
        });
    }

    private static String tokenValue(String line, String key) {
        if (line == null) return null;
        String prefix = key + "=";
        for (String part : line.split("\\s+")) if (part.startsWith(prefix)) return part.substring(prefix.length());
        return null;
    }

    private static String deviceSummary(UsbDevice device) {
        if (device == null) return "null";
        return String.format(Locale.ROOT, "%04x:%04x name=%s", device.getVendorId(), device.getProductId(), safe(device.getDeviceName()));
    }

    private static String safe(String value) {
        if (value == null) return "-";
        value = value.replace('\n', ' ').replace('\r', ' ');
        return value.length() <= 900 ? value : value.substring(0, 900);
    }

    private static void log(String message) { Log.i(TAG, message); }
}
