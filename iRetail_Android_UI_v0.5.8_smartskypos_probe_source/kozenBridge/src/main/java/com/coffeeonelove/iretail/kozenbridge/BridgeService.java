package com.coffeeonelove.iretail.kozenbridge;

import android.app.Service;
import android.content.Intent;
import android.hardware.usb.UsbAccessory;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.IBinder;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;

public class BridgeService extends Service {
    private static final String TAG = "IretailKozenBridge";
    private static final String BRIDGE_VERSION = "0.1.0";

    private final Object lock = new Object();
    private Thread ioThread;
    private ParcelFileDescriptor parcelFd;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
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
            closeLocked();
            ioThread = new Thread(() -> runBridge(selected), "iretail-kozen-aoa-bridge");
            ioThread.start();
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        synchronized (lock) {
            closeLocked();
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
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

            Log.i(TAG, "BRIDGE_READY transport=AOA bridge=" + BRIDGE_VERSION);
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
                closeLocked();
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
                    " protocol=1" +
                    " transport=AOA" +
                    " role=kozen-payment-bridge" +
                    " bridge=" + BRIDGE_VERSION +
                    " smartsky=not-yet-bound";
        }
        return "ERROR " + id + " code=UNKNOWN_COMMAND command=" + token(command);
    }

    private void closeLocked() {
        if (ioThread != null && ioThread != Thread.currentThread()) {
            ioThread.interrupt();
        }
        ioThread = null;
        if (parcelFd != null) {
            try { parcelFd.close(); } catch (Exception ignored) {}
            parcelFd = null;
        }
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
