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
    private static final String ACCESSORY_VERSION = "0.1";
    private static final String ACCESSORY_URI = "https://thesystem.pro/";
    private static final String ACCESSORY_SERIAL = "iretail-kozen-p12";

    private UsbManager usbManager;
    private PendingIntent permissionIntent;
    private TextView output;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private volatile boolean rawPermissionRequested = false;
    private volatile boolean aoaPermissionRequested = false;
    private volatile boolean handshakeStarted = false;
    private volatile boolean linkStarted = false;

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
            if (isRawKozen(device)) {
                startHandshake(device);
            } else if (isAoaDevice(device)) {
                openAoaLink(device);
            }
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

        append("JL22 AOA host probe v0.1");
        append("Ожидание Kozen VID=0e8d PID=201c…");
        main.postDelayed(this::discoverAndStart, 600);
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
        title.setText("i-Retail JL22 → Kozen AOA probe");
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
            append("Kozen 0e8d:201c пока не найден. Повтор через 1 с…");
            main.postDelayed(this::discoverAndStart, 1000);
            return;
        }

        append("Kozen найден: " + deviceSummary(raw));
        if (!usbManager.hasPermission(raw)) {
            if (!rawPermissionRequested) {
                rawPermissionRequested = true;
                append("Запрашиваю USB-разрешение для Kozen. Подтвердите его на JL22, если появится окно.");
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
                append("AOA GET_PROTOCOL не поддержан или вернул " + n + ".");
                log("AOA_GET_PROTOCOL_FAILED rc=" + n);
                handshakeStarted = false;
                return;
            }
            int version = (protocol[0] & 0xff) | ((protocol[1] & 0xff) << 8);
            append("AOA protocol version=" + version);
            log("AOA_PROTOCOL=" + version);
            if (version < 1) {
                append("Некорректная версия AOA: " + version);
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
            append("AOA START отправлен. Жду переподключения Kozen в режиме accessory…");
        } catch (Exception e) {
            log("AOA_HANDSHAKE_EXCEPTION " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            append("Ошибка AOA handshake: " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            handshakeStarted = false;
            return;
        } finally {
            connection.close();
        }

        main.postDelayed(new Runnable() {
            private int attempts = 0;
            @Override
            public void run() {
                UsbDevice aoa = findAoaDevice();
                if (aoa != null) {
                    append("AOA устройство найдено: " + deviceSummary(aoa));
                    ensurePermissionForAoa(aoa);
                    return;
                }
                attempts++;
                if (attempts >= 30) {
                    append("Тайм-аут: Kozen не появился как 18d1:2d0x за 15 секунд.");
                    log("AOA_REENUMERATION_TIMEOUT");
                    return;
                }
                main.postDelayed(this, 500);
            }
        }, 700);
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
            append("Запрашиваю разрешение для AOA 18d1:2d0x. Подтвердите его на JL22, если появится окно.");
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
            append("У AOA устройства не найдены BULK IN/OUT endpoints.");
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
        append("AOA BULK канал открыт. Проверяю PING/INFO…");
        log("AOA_BULK_READY device=" + deviceSummary(device) +
                " interface=" + selectedInterface.getId() +
                " in=0x" + Integer.toHexString(in.getAddress()) +
                " out=0x" + Integer.toHexString(out.getAddress()));

        try {
            String pong = null;
            for (int attempt = 1; attempt <= 12 && pong == null; attempt++) {
                String request = "PING 1001\n";
                int tx = bulkWrite(connection, out, request);
                log("PING_ATTEMPT=" + attempt + " tx=" + tx);
                if (tx > 0) {
                    String response = bulkRead(connection, in, 1800);
                    if (response != null && response.startsWith("PONG 1001")) pong = response;
                }
                if (pong == null) Thread.sleep(700);
            }

            if (pong == null) {
                append("AOA transport открыт, но PONG от Kozen Bridge не получен.");
                log("AOA_PING_TIMEOUT");
                return;
            }
            append("RX: " + pong);
            log("AOA_PING_OK " + safe(pong));

            int infoTx = bulkWrite(connection, out, "INFO 1002\n");
            String info = infoTx > 0 ? bulkRead(connection, in, 2500) : null;
            if (info != null && info.startsWith("INFO 1002")) {
                append("RX: " + info);
                append("ГОТОВО: JL22 ↔ AOA ↔ Kozen Bridge работает.");
                log("AOA_LINK_OK " + safe(info));
            } else {
                append("PONG получен, но INFO не получен. tx=" + infoTx + " response=" + safe(info));
                log("AOA_INFO_FAILED tx=" + infoTx + " response=" + safe(info));
            }
        } catch (Exception e) {
            append("Ошибка обмена по AOA: " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
            log("AOA_LINK_EXCEPTION " + e.getClass().getSimpleName() + ": " + safe(e.getMessage()));
        }
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

    private UsbDevice findRawKozen() {
        for (UsbDevice d : usbManager.getDeviceList().values()) {
            if (isRawKozen(d)) return d;
        }
        return null;
    }

    private UsbDevice findAoaDevice() {
        for (UsbDevice d : usbManager.getDeviceList().values()) {
            if (isAoaDevice(d)) return d;
        }
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

    private void append(String text) {
        log("UI " + safe(text));
        main.post(() -> output.append(text + "\n"));
    }

    private static void log(String text) {
        Log.i(TAG, text);
    }

    private static String deviceSummary(UsbDevice d) {
        if (d == null) return "null";
        return String.format(Locale.US, "%04x:%04x name=%s", d.getVendorId(), d.getProductId(), d.getDeviceName());
    }

    private static String safe(String value) {
        if (value == null) return "-";
        value = value.replace('\n', ' ').replace('\r', ' ');
        return value.length() <= 300 ? value : value.substring(0, 300);
    }
}
