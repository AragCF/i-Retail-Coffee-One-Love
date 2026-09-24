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
import android.os.SystemClock;
import android.util.Log;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Kozen UI shell for the hardened production bridge. */
public class BridgeActivity extends Activity {
    private static final String TAG = "IretailKozenBridge";
    private static final String ACTION_USB_PERMISSION = "com.coffeeonelove.iretail.kozenbridge.USB_PERMISSION";
    private static final String PREFS = "iretail_payment_bridge_v1";
    private static final String PREF_ACTIVE_REQUEST = "active_request";
    private static final long BRIDGE_START_DEBOUNCE_MS = 2000L;

    private UsbManager usbManager;
    private TextView status;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private String lastSeenRequest = "";
    private String lastRendered = "";
    private long lastBridgeStartAt = 0L;

    private final Runnable paymentUiPoll = new Runnable() {
        @Override public void run() {
            try {
                SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
                String active = prefs.getString(PREF_ACTIVE_REQUEST, "");
                if (active != null && !active.isEmpty()) {
                    lastSeenRequest = active;
                    String response = prefs.getString("payment." + active + ".response", null);
                    if (response != null) showPaymentResult(active, response);
                    else showPaymentPrompt(active, prefs);
                } else if (lastSeenRequest != null && !lastSeenRequest.isEmpty()) {
                    String response = prefs.getString("payment." + lastSeenRequest + ".response", null);
                    if (response != null) showPaymentResult(lastSeenRequest, response);
                }
            } catch (Exception e) {
                Log.w(TAG, "PAYMENT_UI_POLL_ERROR " + e.getClass().getSimpleName());
            }
            ui.postDelayed(this, 250L);
        }
    };

    private final BroadcastReceiver permissionReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (!ACTION_USB_PERMISSION.equals(intent.getAction())) return;
            UsbAccessory accessory = intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY);
            boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
            Log.i(TAG, "ACCESSORY_PERMISSION granted=" + granted + " accessory=" + safeAccessory(accessory));
            if (granted && accessory != null) startBridgeService(accessory);
            else setStatus("Нет разрешения на USB accessory");
        }
    };

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        buildUi();
        registerReceiver(permissionReceiver, new IntentFilter(ACTION_USB_PERMISSION));
        handleIntent(getIntent());
        ui.post(paymentUiPoll);
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntent(intent);
    }

    @Override protected void onResume() {
        super.onResume();
        if (getIntent() == null || !UsbManager.ACTION_USB_ACCESSORY_ATTACHED.equals(getIntent().getAction())) {
            findCurrentAccessory();
        }
    }

    @Override protected void onDestroy() {
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
        title.setText("i-Retail Kozen Payment Bridge 0.5.6\nUSB/AOA → SmartSkyPOS");
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
            Log.i(TAG, "ACCESSORY_PERMISSION already_granted");
            startBridgeService(accessory);
            return;
        }

        int flags = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags |= PendingIntent.FLAG_IMMUTABLE;
        PendingIntent pi = PendingIntent.getBroadcast(
                this, 0, new Intent(ACTION_USB_PERMISSION).setPackage(getPackageName()), flags);
        Log.i(TAG, "REQUESTING_ACCESSORY_PERMISSION " + safeAccessory(accessory));
        usbManager.requestPermission(accessory, pi);
        setStatus("Запрошено разрешение на USB accessory…");
    }

    private void startBridgeService(UsbAccessory accessory) {
        long now = SystemClock.elapsedRealtime();
        long delta = now - lastBridgeStartAt;
        if (lastBridgeStartAt > 0L && delta >= 0L && delta < BRIDGE_START_DEBOUNCE_MS) {
            Log.i(TAG, "PRODUCTION_BRIDGE_SERVICE_START duplicate_ignored deltaMs=" + delta);
            return;
        }
        lastBridgeStartAt = now;

        Intent service = new Intent(this, ProductionBridgeService.class);
        service.putExtra(UsbManager.EXTRA_ACCESSORY, accessory);
        startService(service);
        setStatus("Соединение с JL22 установлено.\nОжидание команды.");
        Log.i(TAG, "PRODUCTION_BRIDGE_SERVICE_START requested");
    }

    private void showPaymentPrompt(String requestId, SharedPreferences prefs) {
        String amount = prefs.getString(ProductionBridgeService.paymentAmountKey(requestId), "-");
        String tid = prefs.getString(ProductionBridgeService.paymentTidKey(requestId), "-");
        String text = "ОПЛАТА " + money(amount) + "\n\nПРИЛОЖИТЕ КАРТУ\nК ТЕРМИНАЛУ\n\nTID " + tid + "\n" + requestId;
        renderLarge(text, 34f, "PAYMENT_UI_CARD_PROMPT requestId=" + requestId + " amount=" + amount);
    }

    private void showPaymentResult(String requestId, String response) {
        String amount = value(response, "amount");
        String text;
        if (response.contains("status=APPROVED")) {
            text = "ОПЛАТА ОДОБРЕНА\n" + money(amount) + "\n\n" + requestId;
        } else if (response.contains("status=DECLINED")) {
            text = "ОПЛАТА ОТКЛОНЕНА\n" + shortMessage(response) + "\n\n" + requestId;
        } else if (response.contains("status=FAILED")) {
            text = "ОПЛАТА НЕ ВЫПОЛНЕНА\n" + shortMessage(response) + "\n\n" + requestId;
        } else if (response.contains("status=UNCERTAIN")) {
            text = "РЕЗУЛЬТАТ НЕОПРЕДЕЛЁН\nНЕ ПОВТОРЯТЬ ОПЛАТУ\nНУЖНА СВЕРКА ИСТОРИИ\n\n" + requestId;
        } else {
            text = "ОПЕРАЦИЯ ЗАВЕРШЕНА\n" + shortMessage(response) + "\n\n" + requestId;
        }
        renderLarge(text, 24f, "PAYMENT_UI_RESULT requestId=" + requestId + " response=" + response);
    }

    private void renderLarge(String text, float size, String logLine) {
        if (status == null) return;
        if (text.equals(lastRendered)) return;
        lastRendered = text;
        status.setTextSize(size);
        status.setText(text);
        Log.i(TAG, logLine);
    }

    private void setStatus(String text) {
        if (status == null) return;
        if (text.equals(lastRendered)) return;
        lastRendered = text;
        status.setTextSize(18f);
        status.setText(text);
    }

    private static String shortMessage(String response) {
        String message = value(response, "message");
        if (message == null || message.isEmpty() || "-".equals(message)) return "Терминал завершил операцию";
        return message.replace('_', ' ');
    }

    private static String value(String response, String name) {
        if (response == null) return null;
        String prefix = name + "=";
        for (String part : response.split("\\s+")) {
            if (part.startsWith(prefix)) return part.substring(prefix.length());
        }
        return null;
    }

    private static String money(String amount) {
        if (amount == null || amount.isEmpty() || "-".equals(amount)) return "";
        return amount.replace('.', ',') + " ₽";
    }

    /**
     * Do not call UsbAccessory.getSerial() here before permission is granted.
     * Android 11 protects the serial and throws SecurityException for a new app UID.
     */
    private static String safeAccessory(UsbAccessory a) {
        if (a == null) return "null";
        return "manufacturer=" + a.getManufacturer() +
                ", model=" + a.getModel() +
                ", version=" + a.getVersion();
    }
}
