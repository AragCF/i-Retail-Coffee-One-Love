package com.coffeeonelove.iretail.aoahost;

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
 * JL22-side USB host probe.
 *
 * v0.3 proves the complete READ-ONLY chain:
 * JL22 -> AOA -> Kozen Bridge -> SmartSkyPOS getState()/getTerminalData().
 * No payment/refund/cancel/reconciliation command exists in this probe.
 */
public class AoaHostProbeActivity extends Activity {
    private static final String TAG = "IretailAoaHost";
    private static final String ACTION_USB_PERMISSION = "com.coffeeonelove.iretail.aoahost.USB_PERMISSION";

    private static final int KOZEN_VID = 0x0e8d;
    private static final int KOZEN_PID = 0x201c;
    private static final int GOOGLE_VID = 0x18d1;

    private static final int AOA_GET_PROTOCOL = 51;
    private static final int AOA_SEND_STRING = 52;
    private static final int AOA_START = 53;

    private static final String ACCESSORY_MANUFACTURER = "Coffee One Love";
    private static final String ACCESSORY_MODEL = "iRetail Kozen Payment Bridge";
    private static final String ACCESSORY_DESCRIPTION = "i-Retail USB payment bridge";
    private static final String ACCESSORY_VERSION = "0.3";
    private static final String ACCESSORY_URI = "https://thesystem.pro/";
    private static final String ACCESSORY_SERIAL = "iretail-kozen-p12";

    private UsbManager usbManager;
    private PendingIntent permissionIntent;
    private TextView output;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private volatile boolean rawPermissionRequested;
    private volatile boolean aoaPermissionRequested;
    private volatile boolean handshakeStarted;
    private volatile boolean linkStarted;

    private UsbDeviceConnection linkConnection;
    private UsbInterface linkInterface;

    private final BroadcastReceiver permissionReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (!ACTION_USB_PERMISSION.equals(intent.getAction())) return;
            UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
            log("USB_PERMISSION granted=" + granted + " device=" + deviceSummary(device));
            if (!granted || device == null) {
                append("USB-разрешение не выдано для " + deviceSummary(device));
                return;
            }
            if (isRawKozen(device)) startHandshake(device);
            else if (isAoaDevice(device)) openAoaLink(device);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        buildUi();

        int flags = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags |= PendingIntent.FLAG_IMMUTABLE;
        permissionIntent = PendingIntent.getBroadcast(
                this,
                0,
                new Intent(ACTION_USB_PERMISSION).setPackage(getPackageName()),
                flags
        );
        registerReceiver(permissionReceiver, new IntentFilter(ACTION_USB_PERMISSION));

        append("JL22 AOA + SmartSkyPOS terminal-data probe v0.3");
        append("Только чтение: getState() + getTerminalData(). Финансовые операции отсутствуют.");
        append("Ожидание Kozen…");
        main.postDelayed(this::discoverAndStart, 500);
    }

    @Override
    protected void onDestroy() {
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
        title.setText("i-Retail JL22 → Kozen → SmartSkyPOS");
        title.setTextSize(22f);
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
                append("Запрашиваю USB-разрешение для Kozen.");
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
            append("Не удалось открыть Kozen для AOA control transfer.");
            log("RAW_OPEN_FAILED");
            handshakeStarted = false;
            return;
        }
        try {
            byte[] protocol = new byte[2];
            int n = connection.controlTransfer(0xC0, AOA_GET_PROTOCOL, 0, 0, protocol, protocol.length, 1500);
            if (n != 2) {
                append("AOA GET_PROTOCOL вернул " + n + ".");
                log("AOA_GET_PROTOCOL_FAILED rc=" + n);
                handshakeStarted = false;
                return;
            }
            int version = (protocol[0] & 0xff) | ((protocol[1] & 0xff) << 8);
            append("AOA protocol version=" + version);
            log("AOA_PROTOCOL=" + version);
            if (version < 1) {
                handshakeStarted = false;
                return;
            }

            if (!sendString(connection, 0, ACCESSORY_MANUFACTURER) ||
                    !sendString(connection, 1, ACCESSORY_MODEL) ||
                    !sendString(connection, 2, ACCESSORY_DESCRIPTION) ||
                    !sendString(connection, 3, ACCESSORY_VERSION) ||
                    !sendString(connection, 4, ACCESSORY_URI) ||
                    !sendString(connection, 5, ACCESSORY_SERIAL)) {
                append("Ошибка передачи AOA identification strings.");
                handshakeStarted = false;
                return;
            }

            int start = connection.controlTransfer(0x40, AOA_START, 0, 0, null, 0, 1500);
            log("AOA_START rc=" + start);
            append("AOA START отправлен. Жду 18d1:2d0x…");
        } catch (Exception e) {
            log("AOA_HANDSHAKE_EXCEPTION " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            append("Ошибка AOA handshake: " + e.getClass().getSimpleName());
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
                    append("AOA устройство найдено: " + deviceSummary(aoa));
                    ensurePermissionForAoa(aoa);
                    return;
                }
                attempts++;
                if (attempts >= 60) {
                    append("Тайм-аут повторного перечисления AOA.");
                    log("AOA_REENUMERATION_TIMEOUT");
                    return;
                }
                main.postDelayed(this, 500);
            }
        }, 500);
    }

    private boolean sendString(UsbDeviceConnection connection, int index, String value) {
        byte[] raw = value.getBytes(StandardCharsets.UTF_8);
        byte[] zeroTerminated = new byte[raw.length + 1];
        System.arraycopy(raw, 0, zeroTerminated, 0, raw.length);
        int rc = connection.controlTransfer(0x40, AOA_SEND_STRING, 0, index, zeroTerminated, zeroTerminated.length, 1500);
        log("AOA_SEND_STRING index=" + index + " rc=" + rc + " value=" + value);
        return rc >= 0;
    }

    private void ensurePermissionForAoa(UsbDevice device) {
        if (usbManager.hasPermission(device)) {
            openAoaLink(device);
            return;
        }
        if (!aoaPermissionRequested) {
            aoaPermissionRequested = true;
            append("Запрашиваю разрешение для AOA устройства.");
            log("REQUEST_AOA_USB_PERMISSION " + deviceSummary(device));
            usbManager.requestPermission(device, permissionIntent);
        }
    }

    private void openAoaLink(UsbDevice device) {
        if (linkStarted) return;
        linkStarted = true;
        executor.execute(() -> runLink(device));
    }

    private void runLink(UsbDevice device) {
        UsbDeviceConnection connection = usbManager.openDevice(device);
        if (connection == null) {
            append("Не удалось открыть AOA устройство.");
            log("AOA_OPEN_FAILED");
            linkStarted = false;
            return;
        }

        UsbInterface selectedInterface = null;
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
                selectedInterface = candidate;
                in = candidateIn;
                out = candidateOut;
                break;
            }
        }

        if (selectedInterface == null || in == null || out == null) {
            append("Не найдены AOA BULK IN/OUT endpoints.");
            log("AOA_ENDPOINTS_MISSING interfaces=" + device.getInterfaceCount());
            connection.close();
            linkStarted = false;
            return;
        }

        if (!connection.claimInterface(selectedInterface, true)) {
            append("Не удалось захватить AOA интерфейс.");
            log("AOA_CLAIM_INTERFACE_FAILED id=" + selectedInterface.getId());
            connection.close();
            linkStarted = false;
            return;
        }

        linkConnection = connection;
        linkInterface = selectedInterface;
        append("AOA BULK канал открыт.");
        log("AOA_BULK_READY device=" + deviceSummary(device) +
                " interface=" + selectedInterface.getId() +
                " in=0x" + Integer.toHexString(in.getAddress()) +
                " out=0x" + Integer.toHexString(out.getAddress()));

        try {
            int pingTx = bulkWrite(connection, out, "PING 1001\n");
            log("PING_TX=" + pingTx);
            if (pingTx <= 0) {
                append("Не удалось отправить PING. tx=" + pingTx);
                log("AOA_PING_WRITE_FAILED tx=" + pingTx);
                return;
            }

            append("PING отправлен. Жду Kozen Bridge…");
            String pong = waitForPrefix(connection, in, "PONG 1001", 480000L, "PING");
            if (pong == null) {
                append("Тайм-аут ожидания PONG.");
                log("AOA_PING_TIMEOUT");
                return;
            }
            append("RX: " + pong);
            log("AOA_PING_OK " + safe(pong));

            int infoTx = bulkWrite(connection, out, "INFO 1002\n");
            log("INFO_TX=" + infoTx);
            String info = infoTx > 0 ? waitForPrefix(connection, in, "INFO 1002", 20000L, "INFO") : null;
            if (info == null) {
                append("PONG получен, но INFO не получен.");
                log("AOA_INFO_FAILED tx=" + infoTx);
                return;
            }
            append("RX: " + info);
            log("AOA_LINK_OK " + safe(info));

            append("Читаю SmartSkyPOS getState()…");
            String state = requestUntilCodeZero(connection, in, out, "GET_STATE 1003\n", "STATE 1003", "GET_STATE", 20);
            if (state == null) {
                append("AOA работает, но getState() не подтверждён.");
                log("SMARTSKY_STATE_OVER_AOA_FAILED");
                return;
            }
            append("RX: " + state);
            log("SMARTSKY_STATE_OVER_AOA_OK " + safe(state));

            append("Читаю конфигурацию терминала SmartSkyPOS…");
            String terminalData = requestUntilCodeZero(
                    connection, in, out,
                    "GET_TERMINAL_DATA 1004\n",
                    "TERMINAL_DATA 1004",
                    "GET_TERMINAL_DATA",
                    8
            );
            if (terminalData == null) {
                append("getState() работает, но getTerminalData() не подтверждён.");
                log("SMARTSKY_TERMINAL_DATA_OVER_AOA_FAILED");
                return;
            }

            append("RX: " + terminalData);
            log("SMARTSKY_TERMINAL_DATA_OVER_AOA_OK " + safe(terminalData));

            boolean paymentReady = terminalData.contains("payment=true") &&
                    terminalData.contains("currencies=643") &&
                    !terminalData.contains("paymentTid=-");
            if (paymentReady) {
                append("ГОТОВО: чтение терминала подтверждено; операция оплаты и RUB/643 объявлены SmartSkyPOS.");
                append("Платёж этим тестом НЕ выполнялся.");
                log("TERMINAL_DATA_READY_FOR_PAYMENT_TEST " + safe(terminalData));
            } else {
                append("Терминальные данные прочитаны, но готовность payment/RUB не подтверждена.");
                log("TERMINAL_DATA_NOT_PAYMENT_READY " + safe(terminalData));
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log("AOA_LINK_INTERRUPTED");
        } catch (Exception e) {
            append("Ошибка обмена AOA: " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            log("AOA_LINK_EXCEPTION " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
        }
    }

    private String requestUntilCodeZero(
            UsbDeviceConnection connection,
            UsbEndpoint in,
            UsbEndpoint out,
            String request,
            String responsePrefix,
            String phase,
            int attempts
    ) throws InterruptedException {
        for (int attempt = 1; attempt <= attempts; attempt++) {
            int tx = bulkWrite(connection, out, request);
            log(phase + "_TX attempt=" + attempt + " tx=" + tx);
            if (tx > 0) {
                String response = waitForPrefix(connection, in, responsePrefix, 5000L, phase);
                if (response != null) {
                    log(phase + "_RX attempt=" + attempt + " " + safe(response));
                    if (response.contains("code=0")) return response;
                    if (!response.contains("code=NOT_BOUND")) return null;
                }
            }
            Thread.sleep(500L);
        }
        return null;
    }

    private String waitForPrefix(UsbDeviceConnection connection, UsbEndpoint in, String prefix, long totalMs, String phase) {
        long deadline = System.currentTimeMillis() + totalMs;
        int reads = 0;
        while (!Thread.currentThread().isInterrupted() && System.currentTimeMillis() < deadline) {
            String response = bulkRead(connection, in, 1000);
            reads++;
            if (response == null) continue;
            String match = pickLineStartingWith(response, prefix);
            if (match != null) {
                log(phase + "_RX_MATCH reads=" + reads + " " + safe(match));
                return match;
            }
            log(phase + "_RX_IGNORED reads=" + reads + " " + safe(response));
        }
        return null;
    }

    private int bulkWrite(UsbDeviceConnection connection, UsbEndpoint out, String text) {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        return connection.bulkTransfer(out, bytes, bytes.length, 2000);
    }

    private String bulkRead(UsbDeviceConnection connection, UsbEndpoint in, int timeoutMs) {
        byte[] buffer = new byte[4096];
        int count = connection.bulkTransfer(in, buffer, buffer.length, timeoutMs);
        if (count <= 0) return null;
        return new String(buffer, 0, count, StandardCharsets.UTF_8).trim();
    }

    private static String pickLineStartingWith(String text, String prefix) {
        if (text == null) return null;
        String[] lines = text.split("\\r?\\n");
        for (String line : lines) {
            String trimmed = line.trim();
            if (trimmed.startsWith(prefix)) return trimmed;
        }
        return null;
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

    private void append(String text) {
        log("UI " + text);
        main.post(() -> {
            if (output != null) output.append((output.length() == 0 ? "" : "\n") + text);
        });
    }

    private static void log(String text) { Log.i(TAG, text); }

    private static String deviceSummary(UsbDevice d) {
        if (d == null) return "null";
        return String.format(Locale.US, "%04x:%04x name=%s", d.getVendorId(), d.getProductId(), d.getDeviceName());
    }

    private void closeLink() {
        UsbDeviceConnection connection = linkConnection;
        UsbInterface intf = linkInterface;
        linkConnection = null;
        linkInterface = null;
        if (connection != null) {
            try { if (intf != null) connection.releaseInterface(intf); } catch (Exception ignored) {}
            try { connection.close(); } catch (Exception ignored) {}
        }
    }

    private static String safe(String value) {
        if (value == null) return "-";
        value = value.replace('\n', ' ').replace('\r', ' ');
        return value.length() <= 600 ? value : value.substring(0, 600);
    }
}
