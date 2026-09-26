from pathlib import Path
import json, re
R = Path(__file__).resolve().parents[1]
U = R / 'app/src/main/java/com/coffeeonelove/iretail/ui'
core = (U/'DeviceBindingCore.kt').read_text()
store = (U/'DeviceBindingStore.kt').read_text()
ui = (U/'DeviceBindingActivity.kt').read_text()
main = (U/'MainActivity.kt').read_text()
data = (U/'IntegrationGateways.kt').read_text()
transport = (U/'DeviceBindingRuntime.kt').read_text()
manifest = (R/'app/src/main/AndroidManifest.xml').read_text()
config = json.loads((R/'app/src/main/assets/content/iretail-api.json').read_text())
script = (R/'tools/Run-DeviceBindingSafeTest.ps1').read_text()
checks = {
    'no embedded account, token, PIN or target IDs': not any(k in config for k in ('login','password','client_secret','access_token','device_code','device_id','channel_id','profile_id')),
    'binding mandatory': config.get('binding_required') is True,
    'activation written before send': core.index('storage.write(record)') < core.index('val response = transport.post("iretail/device/register"'),
    'reply persisted before identity validation': core.index('record.put("registration", response)') < core.index('val identity = BindingRecordPolicy.identity(record)'),
    'ambiguous activation cannot repeat': 'record == null || record.optString("stage") == "REJECTED"' in core,
    'transport denies redirects': 'instanceFollowRedirects = false' in transport,
    'transport errors have no raw body': 'throw BindingFailure("HTTP_$status")' in transport,
    'encrypted durable storage': all(x in store for x in ('AES/GCM/NoPadding','AndroidKeyStore','stream.fd.sync()','atomic.finishWrite(stream)','noBackupFilesDir')),
    'missing key does not clear existing binding': 'BINDING_KEY_MISSING' in store and 'file.delete()' not in store and 'atomic.delete()' not in store,
    'credentials screen avoids state snapshots': 'FLAG_SECURE' in ui and 'isSaveEnabled = false' in ui,
    'onboarding not exported': bool(re.search(r'android:name=".ui.DeviceBindingActivity"\s+android:exported="false"',manifest)),
    'customer paths require binding': main.count('requireDeviceBinding()') >= 10,
    'repository configured from binding only': 'DeviceBindingStore.get(context).configuredRecord()' in data and 'readAsset("content/iretail-api.json")' not in data,
    'new binding cannot reuse old global catalog': 'BindingRecordPolicy.cacheScope(record)' in data and 'File(context.filesDir, "iretail_catalog_cache.zip")' not in data,
    'nested payment flag': 'service.optJSONObject("settings")?.optBooleanNullable("enable") == true' in data,
    'financial operations disabled': 'const val FINANCIAL_OPERATIONS_ENABLED = false' in core,
    'no new payment or order server endpoint': not any(p in transport for p in ('order/synchronize','payment-in/create','shift/open','device/ping')),
    'Windows exact hardware signature': all(x in script for x in ('product:octopus_jetinno','model:UniWin_M190','device:octopus-jetinno')),
    'Windows never submits activation': 'activation_sent_by_script = $false' in script and 'device/register' not in script,
    'Windows preserves app data': ' install -r ' in script and 'pm clear' not in script and not re.search(r'& adb[^\n]*\buninstall\b',script),
    'report is constructed, not raw export': 'raw_logs_in_report = $false' in script and 'ConvertTo-Json -Depth 5' in script and 'Get-Content' not in script.split('foreach ($line in $lines)',1)[-1],
}
for name, ok in checks.items(): print(('[OK] ' if ok else '[FAIL] ') + name)
assert all(checks.values()), [name for name, ok in checks.items() if not ok]
print('BINDING_STATIC_OK', len(checks))
