from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
probe = (ROOT / "tools/iRetailControlledExternalSystemRegisterProbe.ps1").read_text(encoding="utf-8")
assert_ps = (ROOT / "tools/Assert-S3ExternalSystemRegisterProbeSafe.ps1").read_text(encoding="utf-8")
run = (ROOT / "S3_19_RUN_EXTERNAL_SYSTEM_REGISTER_PROBE.bat").read_text(encoding="utf-8")
publish = (ROOT / "S3_20_PUBLISH_EXTERNAL_SYSTEM_REGISTER_PROBE.bat").read_text(encoding="utf-8")
recovery = (ROOT / "S3_21_COLLECT_EXTERNAL_REGISTER_STATE_ONLY.bat").read_text(encoding="utf-8")
contract = (ROOT / "docs/S3_EXTERNAL_SYSTEM_REGISTER_CONTROLLED_PROBE_CONTRACT_v1.0.0.md").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

m = re.search(r"versionCode\s+(\d+)", gradle)
needle = 'Invoke-CurlRequest ($baseUrl + "iretail/device/register-external-system")'
marker = 'Save-Marker "EXTERNAL_REGISTER_CALL_STARTED"'

checks = {
    "versionCode at least 70": bool(m) and int(m.group(1)) >= 70,
    "contract approved": "APPROVED_FOR_SINGLE_PROBE" in contract,
    "explicit user approval recorded": "Одобряю один пробный register-external-system" in contract,
    "exactly one external register invocation": probe.count(needle) == 1,
    "marker before external register": 0 <= probe.find(marker) < probe.find(needle),
    "source external code read from server": '"external_code"' in probe and "sourceDeviceId = 3476" in probe,
    "external code not saved": "source_external_code_saved=$false" in probe,
    "local persistent marker": "external_system_register_probe_contract_1_0_0.json" in probe,
    "repo marker": "EXTERNAL_SYSTEM_REGISTER_PROBE_1_0_0.marker.json" in probe,
    "curl retry disabled": '"--retry","0"' in probe,
    "automatic binding disabled": "automatic_device_binding=$false" in probe,
    "config update disabled": "config_update_allowed=$false" in probe,
    "order sending disabled": "order_send_allowed=$false" in probe,
    "recovery mode exists": "-ReadOnlyRecovery" in recovery,
    "run branch guard": "v0.5.70-s3-external-register-probe" in run,
    "publisher branch guard": "v0.5.70-s3-external-register-probe" in publish,
    "validator controlled mode": "CONTROLLED_EXTERNAL_REGISTER_PROBE" in assert_ps,
    "validator recovery mode": "READ_ONLY_RECOVERY" in assert_ps,
    "raw report ignored": "test_reports/s3_external_register/S3_EXTERNAL_REGISTER_*/" in gitignore,
    "repo marker ignored": "test_reports/s3_external_register/EXTERNAL_SYSTEM_REGISTER_PROBE_1_0_0.marker.json" in gitignore,
}

checks["ordinary register network call absent"] = 'Invoke-CurlRequest ($baseUrl + "iretail/device/register")' not in probe
forbidden = [
    "iretail/device/update-info",
    '"iretail/shift/get-current"',
    "iretail/shift/open-shift",
    "iretail/shift/close-shift",
    "iretail/employee/authorize",
    "iretail/payment-in/create",
    "iretail/order/synchronize",
]
checks["forbidden routes absent"] = all(x not in probe for x in forbidden)

failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("v0.5.70 external register probe guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.70 external register probe guard: {len(checks)} checks passed")
