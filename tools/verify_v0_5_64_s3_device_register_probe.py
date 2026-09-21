from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
probe = (ROOT / "tools/iRetailControlledDeviceRegisterProbe.ps1").read_text(encoding="utf-8")
assert_ps = (ROOT / "tools/Assert-S3DeviceRegisterProbeSafe.ps1").read_text(encoding="utf-8")
run = (ROOT / "S3_14_RUN_DEVICE_REGISTER_PROBE.bat").read_text(encoding="utf-8")
publish = (ROOT / "S3_15_PUBLISH_DEVICE_REGISTER_PROBE.bat").read_text(encoding="utf-8")
recovery = (ROOT / "S3_16_COLLECT_DEVICE_REGISTER_STATE_ONLY.bat").read_text(encoding="utf-8")
contract = (ROOT / "docs/S3_DEVICE_REGISTER_CONTROLLED_PROBE_CONTRACT_v1.0.1.md").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

version_match = re.search(r"versionCode\s+(\d+)", gradle)
register_call = 'Invoke-CurlRequest ($baseUrl + "iretail/device/register")'

checks = {
    "versionCode at least 64": bool(version_match) and int(version_match.group(1)) >= 64,
    "contract approved for single probe": "APPROVED_FOR_SINGLE_PROBE" in contract,
    "approval scope one call": "один `device/register(device_code)`" in contract,
    "one register invocation": probe.count(register_call) == 1,
    "marker before register": 0 <= probe.find('Save-Marker "REGISTER_CALL_STARTED"') < probe.find(register_call),
    "local persistent marker": "LocalApplicationData" in probe and "device_register_probe_contract_1_0_1.json" in probe,
    "repo marker": "DEVICE_REGISTER_PROBE_1_0_1.marker.json" in probe,
    "curl retry disabled": '"--retry","0"' in probe,
    "automatic device binding disabled": "automatic_device_binding=$false" in probe,
    "config update disabled": "config_update_allowed=$false" in probe,
    "order sending disabled": "order_send_allowed=$false" in probe,
    "recovery mode": "-ReadOnlyRecovery" in recovery,
    "run branch guard": "v0.5.64-s3-device-register-probe" in run,
    "publisher branch guard": "v0.5.64-s3-device-register-probe" in publish,
    "validator controlled mode": "CONTROLLED_REGISTER_PROBE" in assert_ps,
    "validator recovery mode": "READ_ONLY_RECOVERY" in assert_ps,
    "raw report ignored": "test_reports/s3_device_register/S3_DEVICE_REGISTER_*/" in gitignore,
    "repo marker ignored": "test_reports/s3_device_register/DEVICE_REGISTER_PROBE_1_0_1.marker.json" in gitignore,
}

forbidden = [
    "iretail/device/register-external-system",
    "iretail/device/update-info",
    "iretail/shift/open-shift",
    "iretail/shift/close-shift",
    "iretail/employee/authorize",
    "iretail/payment-in/create",
    "iretail/order/synchronize",
]
checks["forbidden routes absent"] = all(x not in probe for x in forbidden)
checks["mutating shift/get-current absent"] = '"iretail/shift/get-current"' not in probe

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
if failed:
    raise SystemExit("v0.5.64 device/register probe guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.64 device/register probe guard: {len(checks)} checks passed")
