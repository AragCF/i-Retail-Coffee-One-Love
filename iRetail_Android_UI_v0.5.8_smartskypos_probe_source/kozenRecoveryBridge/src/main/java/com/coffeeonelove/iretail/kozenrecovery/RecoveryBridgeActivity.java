package com.coffeeonelove.iretail.kozenrecovery;

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

/** Read-only AOA recovery entry point. It exposes no payment/cancel/refund action. */
public class RecoveryBridgeActivity extends Activity {
    private static final String TAG = "IretailKozenRecovery";
    private static final String ACTION_USB_PERMISSION = "com.coffeeonelove.iretail.kozenrecovery.USB_PERMISSION";

    private UsbManager usbManager;
    private TextView status;

    private final BroadcastReceiver permissionReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (!ACTION_USB_PERMISSION.equals(intent.getAction())) return;
            UsbAccessory accessory = intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY);
            boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
            Log.i(TAG, "ACCESSORY_PERMISSION granted=" + granted + " accessory=" + safeAccessory(accessory));
            if (granted && accessory != null) startRecoveryService(accessory);
            else setStatus("Нет разрешения на USB accessory. Финансовых команд приложение не содержит.");
        }
    };

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        buildUi();
        registerReceiver(permissionReceiver, new IntentFilter(ACTION_USB_PERMISSION));
        handleIntent(getIntent());
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntent(intent);
    }

    @Override protected void onResume() {
        super.onResume();
        findCurrentAccessory();
    }

    @Override protected void onDestroy() {
        try { unregisterReceiver(permissionReceiver); } catch (Exception ignored) {}
        super.onDestroy();
    }

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (18 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("i-Retail Kozen Recovery Bridge");
        title.setTextSize(23f);
        root.addView(title);

        TextView safety = new TextView(this);
        safety.setText("ТОЛЬКО ЧТЕНИЕ\npayment / cancel / refund / reconciliation отсутствуют");
        safety.setTextSize(17f);
        safety.setPadding(0, pad, 0, pad);
        root.addView(safety);

        status = new TextView(this);
        status.setTextSize(16f);
        status.setText("Ожидание AOA-подключения от JL22…");
        root.addView(status);
        setContentView(root);
    }

    private void handleIntent(Intent intent) {
        if (intent != null && UsbManager.ACTION_USB_ACCESSORY_ATTACHED.equals(intent.getAction())) {
            UsbAccessory accessory = intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY);
            Log.i(TAG, "ACCESSORY_ATTACHED " + safeAccessory(accessory));
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
        if (usbManager.hasPermission(accessory)) {
            startRecoveryService(accessory);
            return;
        }
        int flags = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags |= PendingIntent.FLAG_IMMUTABLE;
        PendingIntent pi = PendingIntent.getBroadcast(
                this, 0, new Intent(ACTION_USB_PERMISSION).setPackage(getPackageName()), flags);
        Log.i(TAG, "REQUESTING_ACCESSORY_PERMISSION " + safeAccessory(accessory));
        usbManager.requestPermission(accessory, pi);
        setStatus("Разрешите доступ к USB accessory. Это только чтение истории транзакций.");
    }

    private void startRecoveryService(UsbAccessory accessory) {
        Intent service = new Intent(this, RecoveryBridgeService.class);
        service.putExtra(UsbManager.EXTRA_ACCESSORY, accessory);
        startService(service);
        setStatus("AOA открыт. Готово к безопасному чтению последней транзакции.");
        Log.i(TAG, "RECOVERY_SERVICE_START requested");
    }

    private void setStatus(String text) { if (status != null) status.setText(text); }

    private static String safeAccessory(UsbAccessory a) {
        if (a == null) return "null";
        return "manufacturer=" + a.getManufacturer() + ", model=" + a.getModel() +
                ", version=" + a.getVersion() + ", serial=" + a.getSerial();
    }
}
