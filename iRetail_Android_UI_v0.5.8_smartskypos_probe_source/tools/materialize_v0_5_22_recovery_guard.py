from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / 'kozenRecoveryBridge/src/main/java/com/coffeeonelove/iretail/kozenrecovery/RecoveryBridgeService.java'
GRADLE = ROOT / 'kozenRecoveryBridge/build.gradle'
SCRIPT = ROOT / 'AOA_16_LAST_TRANSACTION_RECOVERY.bat'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)

service = SERVICE.read_text(encoding='utf-8')
service = replace_once(service,
    '    private static final String BRIDGE_VERSION = "0.1.0";\n',
    '    private static final String BRIDGE_VERSION = "0.1.2";\n',
    'bridge version')
service = replace_once(service,
    '    private volatile IBinder smartSkyBinder;\n    private volatile boolean smartSkyBound;\n',
    '    private volatile IBinder smartSkyBinder;\n    private volatile boolean smartSkyBound;\n    private volatile boolean smartSkyBindingRequested;\n',
    'binding flag field')
service = replace_once(service,
    '            smartSkyBinder = service;\n            smartSkyBound = true;\n',
    '            smartSkyBinder = service;\n            smartSkyBound = true;\n            smartSkyBindingRequested = false;\n',
    'connected flag')
service = replace_once(service,
    '            smartSkyBinder = null;\n            smartSkyBound = false;\n            Log.w(TAG, "SMARTSKY_DISCONNECTED component=" + name);\n',
    '            smartSkyBinder = null;\n            smartSkyBound = false;\n            smartSkyBindingRequested = false;\n            Log.w(TAG, "SMARTSKY_DISCONNECTED component=" + name);\n',
    'disconnected flag')
service = replace_once(service,
    '            smartSkyBinder = null;\n            smartSkyBound = false;\n            Log.w(TAG, "SMARTSKY_BINDING_DIED component=" + name);\n',
    '            smartSkyBinder = null;\n            smartSkyBound = false;\n            smartSkyBindingRequested = false;\n            Log.w(TAG, "SMARTSKY_BINDING_DIED component=" + name);\n',
    'binding died flag')
service = replace_once(service,
    '            smartSkyBinder = null;\n            smartSkyBound = false;\n            Log.e(TAG, "SMARTSKY_NULL_BINDING component=" + name);\n',
    '            smartSkyBinder = null;\n            smartSkyBound = false;\n            smartSkyBindingRequested = false;\n            Log.e(TAG, "SMARTSKY_NULL_BINDING component=" + name);\n',
    'null binding flag')
service = replace_once(service,
    '''        final UsbAccessory selected = accessory;\n        synchronized (lock) {\n            closeAccessoryLocked();\n            ioThread = new Thread(() -> runBridge(selected), "iretail-kozen-recovery-aoa");\n            ioThread.start();\n        }\n''',
    '''        final UsbAccessory selected = accessory;\n        synchronized (lock) {\n            if (ioThread != null && ioThread.isAlive()) {\n                Log.i(TAG, "RECOVERY_SERVICE_START_DUPLICATE_IGNORED activeThread=true bridge=" + BRIDGE_VERSION);\n                return START_NOT_STICKY;\n            }\n            closeAccessoryLocked();\n            ioThread = new Thread(() -> runBridge(selected), "iretail-kozen-recovery-aoa");\n            ioThread.start();\n        }\n''',
    'service start guard')
service = replace_once(service,
    '''        smartSkyBinder = null;\n        smartSkyBound = false;\n        super.onDestroy();\n''',
    '''        smartSkyBinder = null;\n        smartSkyBound = false;\n        smartSkyBindingRequested = false;\n        super.onDestroy();\n''',
    'destroy binding flag')
service = replace_once(service,
    '''    private void bindSmartSky() {\n        if (smartSkyBound && smartSkyBinder != null && smartSkyBinder.isBinderAlive()) return;\n        try {\n''',
    '''    private void bindSmartSky() {\n        if (smartSkyBound && smartSkyBinder != null && smartSkyBinder.isBinderAlive()) return;\n        if (smartSkyBindingRequested) return;\n        smartSkyBindingRequested = true;\n        try {\n''',
    'bind request guard')
service = replace_once(service,
    '''            if (!ok) {\n                smartSkyBound = false;\n                smartSkyBinder = null;\n            }\n        } catch (Exception e) {\n            smartSkyBound = false;\n''',
    '''            if (!ok) {\n                smartSkyBindingRequested = false;\n                smartSkyBound = false;\n                smartSkyBinder = null;\n            }\n        } catch (Exception e) {\n            smartSkyBindingRequested = false;\n            smartSkyBound = false;\n''',
    'bind failure reset')
SERVICE.write_text(service, encoding='utf-8')

gradle = GRADLE.read_text(encoding='utf-8')
gradle = replace_once(gradle,
    "        versionCode 2\n        versionName '0.1.1-read-only-recovery-permission-fix'\n",
    "        versionCode 3\n        versionName '0.1.2-read-only-recovery-double-start-guard'\n",
    'recovery app version')
GRADLE.write_text(gradle, encoding='utf-8')

script = SCRIPT.read_text(encoding='utf-8')
script = replace_once(script,
    '  if "%%S"=="5" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenrecovery/.RecoveryBridgeActivity >nul 2>nul\n',
    '  rem v0.5.22: do not relaunch RecoveryBridgeActivity; duplicate starts can interrupt the live AOA reader.\n',
    'remove recovery relaunch')
SCRIPT.write_text(script, encoding='utf-8')

print('v0.5.22 recovery double-start guard materialized successfully')
