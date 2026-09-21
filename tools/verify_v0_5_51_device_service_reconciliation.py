from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
ps = (ROOT / "tools/iRetailDeviceServiceReconciliation.ps1").read_text(encoding="utf-8")
run_bat = (ROOT / "S3_08_RECONCILE_DEVICE_SERVICE.bat").read_text(encoding="utf-8")
pub_bat = (ROOT / "S3_09_PUBLISH_DEVICE_SERVICE_RECONCILIATION.bat").read_text(encoding="utf-8")
safe_ps = (ROOT / "tools/Assert-S3DeviceServiceSafe.ps1").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

required_paths = [
    "iretail/channel/get",
    "iretail/device/get-by-channel-id",
    "service-in/get-service-in",
    "service-in/get-used",
    "service-in/get-service-in-types",
    "iretail/device/get-device-info",
    "iretail/shift/get-current-active-shift",
]

forbidden_request_literals = [
    '"iretail/device/register"',
    '"iretail/device/register-external-system"',
    '"iretail/shift/open-shift"',
    '"iretail/shift/close-shift"',
    '"iretail/employee/authorize"',
    '"iretail/payment-in/create"',
    '"iretail/order/synchronize"',
]

checks = {
    "versionCode 51": "versionCode 51" in build,
    "versionName 0.5.51": "versionName '0.5.51-s3-device-service-reconciliation'" in build,
    "explicit curl.exe": "& curl.exe" in ps,
    "no PowerShell Curl alias function": "function Curl(" not in ps,
    "auth raw is temp only": 'Join-Path $tmp "auth.json"' in ps,
    "device raw is temp only": 'Join-Path $tmp ($Name + ".raw")' in ps,
    "secret sanitizer": "Is-SensitiveKey" in ps and "device_code" in ps and "pin" in ps,
    "secret scan before ZIP": "Safety scan failed" in ps,
    "max 20 devices": "Select-Object -First 20" in ps,
    "configured device only compared": "configured_device_found" in ps.lower(),
    "no automatic device selection": "automatic_device_selection=$false" in ps.lower(),
    "order send disabled": "order_send_allowed=$false" in ps.lower(),
    "one-command publisher": "S3_09_PUBLISH_DEVICE_SERVICE_RECONCILIATION.bat" in run_bat,
    "publisher safety validator": "Assert-S3DeviceServiceSafe.ps1" in pub_bat,
    "validator rejects raw/form": r"\.form$" in safe_ps and r"\.raw$" in safe_ps,
    "validator forbids auto selection": "automatic_device_selection" in safe_ps,
    "unpacked reports ignored": "test_reports/s3_device_service/S3_DEVICE_SERVICE_*/" in gitignore,
}

for path in required_paths:
    checks[f"read-only path {path}"] = path in ps

for literal in forbidden_request_literals:
    checks[f"forbidden request absent {literal}"] = literal not in ps

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.51 device/service reconciliation guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.51 device/service reconciliation guard: {len(checks)} checks passed")
