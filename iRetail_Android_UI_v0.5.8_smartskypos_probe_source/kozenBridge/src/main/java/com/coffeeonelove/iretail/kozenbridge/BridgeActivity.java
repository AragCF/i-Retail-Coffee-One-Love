package com.coffeeonelove.iretail.kozenbridge;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbAccessory;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.widget.LinearLayout;
import android.widget.TextView;

public class BridgeActivity extends Activity {
    private static final String TAG = "IretailKozenBridge";
    private static final String ACTION_USB_PERMISSION = "com.coffeeonelove.iretail.kozenbridge.USB_PERMISSION";

    private UsbManager usbManager;
    private TextView status;

    private final BroadcastReceiver permissionReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (!ACTION_USB_PERMISSION.equals(intent.getAction())) return;
            UsbAccessory accessory = intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY);
            boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
            Log.i(TAG, "ACCESSORY_PERMISSION granted=" + granted + " accessory=" + safeAccessory(accessory));
            if (granted && accessory != null) {
                startBridgeService(accessory);
            } else {
                setStatus("Нет разрешения на USB accessory");
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        buildUi();
        registerReceiver(permissionReceiver, new IntentFilter(ACTION_USB_PERMISSION));
        handleIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntent(intent);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (getIntent() == null || !UsbManager.ACTION_USB_ACCESSORY_ATTACHED.equals(getIntent().getAction())) {
            findCurrentAccessory();
        }
    }

    @Override
    protected void onDestroy() {
        try { unregisterReceiver(permissionReceiver); } catch (Exception ignored) {}
        super.onDestroy();
    }

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (16 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("i-Retail Kozen Payment Bridge\nAOA transport probe v0.1");
        title.setTextSize(22f);
        root.addView(title);

        status = new TextView(this);
        status.setTextSize(16f);
        status.setPadding(0, pad, 0, 0);
        status.setText("Ожидание USB accessory…");
        root.addView(status);
        setContentView(root);
    }

    private void handleIntent(Intent intent) {
        if (intent != null && UsbManager.ACTION_USB_ACCESSORY_ATTACHED.equals(intent.getAction())) {
            UsbAccessory accessory = intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY);
            Log.i(TAG, "ACCESSORY_ATTACHED intent accessory=" + safeAccessory(accessory));
            if (accessory != null) {
                ensurePermissionAndStart(accessory);
                return;
            }
        }
        findCurrentAccessory();
    }

    private void findCurrentAccessory() {
        UsbAccessory[] list = usbManager.getAccessoryList();
        if (list == null || list.length == 0) {
            setStatus("Ожидание AOA-подключения от JL22…");
            Log.i(TAG, "WAITING_FOR_ACCESSORY");
            return;
        }
        ensurePermissionAndStart(list[0]);
    }

    private void ensurePermissionAndStart(UsbAccessory accessory) {
        setStatus("Accessory найден: " + safeAccessory(accessory));
        if (usbManager.hasPermission(accessory)) {
            Log.i(TAG, "ACCESSORY_PERMISSION already granted");
            startBridgeService(accessory);
            return;
        }

        int flags = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        PendingIntent pi = PendingIntent.getBroadcast(this, 0, new Intent(ACTION_USB_PERMISSION).setPackage(getPackageName()), flags);
        Log.i(TAG, "REQUESTING_ACCESSORY_PERMISSION " + safeAccessory(accessory));
        usbManager.requestPermission(accessory, pi);
        setStatus("Запрошено разрешение на USB accessory…");
    }

    private void startBridgeService(UsbAccessory accessory) {
        Intent service = new Intent(this, BridgeService.class);
        service.putExtra(UsbManager.EXTRA_ACCESSORY, accessory);
        startService(service);
        setStatus("AOA accessory открыт. Мост ожидает PING/INFO от JL22.");
        Log.i(TAG, "BRIDGE_SERVICE_START requested");
    }

    private void setStatus(String text) {
        if (status != null) status.setText(text);
    }

    private static String safeAccessory(UsbAccessory a) {
        if (a == null) return "null";
        return "manufacturer=" + a.getManufacturer() +
                ", model=" + a.getModel() +
                ", version=" + a.getVersion() +
                ", serial=" + a.getSerial();
    }
}
