package com.coffeeonelove.iretail.kozenbridge;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.hardware.usb.UsbAccessory;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.LinearLayout;
import android.widget.TextView;

public class BridgeActivity extends Activity {
    private static final String TAG = "IretailKozenBridge";
    private static final String ACTION_USB_PERMISSION = "com.coffeeonelove.iretail.kozenbridge.USB_PERMISSION";
    private static final String PREFS = "iretail_payment_bridge_v1";
    private static final String PREF_ACTIVE_REQUEST = "active_request";

    private UsbManager usbManager;
    private TextView status;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private String lastSeenRequest = "";

    private final Runnable paymentUiPoll = new Runnable() {
        @Override
        public void run() {
            try {
                SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
                String active = prefs.getString(PREF_ACTIVE_REQUEST, "");
                if (active != null && !active.isEmpty()) {
                    lastSeenRequest = active;
                    showPaymentPrompt(active);
                } else if (lastSeenRequest != null && !lastSeenRequest.isEmpty()) {
                    String response = prefs.getString("payment." + lastSeenRequest + ".response", null);
                    if (response != null) {
                        showPaymentResult(lastSeenRequest, response);
                    }
                }
            } catch (Exception e) {
                Log.w(TAG, "PAYMENT_UI_POLL_ERROR " + e.getClass().getSimpleName());
            }
            ui.postDelayed(this, 250L);
        }
    };

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
        ui.post(paymentUiPoll);
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
        ui.removeCallbacks(paymentUiPoll);
        try { unregisterReceiver(permissionReceiver); } catch (Exception ignored) {}
        super.onDestroy();
    }

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (16 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("i-Retail Kozen Payment Bridge\nUSB/AOA → SmartSkyPOS");
        title.setTextSize(22f);
        root.addView(title);

        status = new TextView(this);
        status.setTextSize(18f);
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags |= PendingIntent.FLAG_IMMUTABLE;
        PendingIntent pi = PendingIntent.getBroadcast(this, 0, new Intent(ACTION_USB_PERMISSION).setPackage(getPackageName()), flags);
        Log.i(TAG, "REQUESTING_ACCESSORY_PERMISSION " + safeAccessory(accessory));
        usbManager.requestPermission(accessory, pi);
        setStatus("Запрошено разрешение на USB accessory…");
    }

    private void startBridgeService(UsbAccessory accessory) {
        Intent service = new Intent(this, BridgeService.class);
        service.putExtra(UsbManager.EXTRA_ACCESSORY, accessory);
        startService(service);
        setStatus("Соединение с JL22 установлено.\nОжидание команды оплаты.");
        Log.i(TAG, "BRIDGE_SERVICE_START requested");
    }

    private void showPaymentPrompt(String requestId) {
        if (status == null) return;
        status.setTextSize(34f);
        status.setText("ОПЛАТА 1,00 ₽\n\nПРИЛОЖИТЕ КАРТУ\nК ТЕРМИНАЛУ\n\n" + requestId);
        Log.i(TAG, "PAYMENT_UI_CARD_PROMPT requestId=" + requestId);
    }

    private void showPaymentResult(String requestId, String response) {
        if (status == null) return;
        status.setTextSize(24f);
        if (response.contains("approved=true") && response.contains("code=0")) {
            status.setText("ОПЛАТА ОДОБРЕНА\n1,00 ₽\n\n" + requestId);
        } else if (response.contains("status=UNCERTAIN")) {
            status.setText("РЕЗУЛЬТАТ НЕОПРЕДЕЛЁН\nНЕ ПОВТОРЯТЬ ОПЛАТУ\n\n" + requestId);
        } else {
            status.setText("ОПЛАТА НЕ ПРОШЛА\n\n" + shortMessage(response) + "\n\n" + requestId);
        }
    }

    private void setStatus(String text) {
        if (status != null) {
            status.setTextSize(18f);
            status.setText(text);
        }
    }

    private static String shortMessage(String response) {
        if (response == null) return "Нет ответа";
        String key = "message=";
        int p = response.indexOf(key);
        if (p < 0) return "Терминал отклонил операцию";
        String value = response.substring(p + key.length());
        int end = value.indexOf(' ');
        if (end >= 0) value = value.substring(0, end);
        return value.replace('_', ' ');
    }

    private static String safeAccessory(UsbAccessory a) {
        if (a == null) return "null";
        return "manufacturer=" + a.getManufacturer() +
                ", model=" + a.getModel() +
                ", version=" + a.getVersion() +
                ", serial=" + a.getSerial();
    }
}
