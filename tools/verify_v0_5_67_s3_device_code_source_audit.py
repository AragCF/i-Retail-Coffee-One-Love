from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ps = (ROOT / "tools/iRetailDeviceCodeSourceAudit.ps1").read_text(encoding="utf-8")
run = (ROOT / "S3_17_AUDIT_DEVICE_CODE_SOURCE.bat").read_text(encoding="utf-8")
pub = (ROOT / "S3_18_PUBLISH_DEVICE_CODE_SOURCE_AUDIT.bat").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

m = re.search(r"versionCode\s+(\d+)", gradle)

checks = {
    "versionCode at least 67": bool(m) and int(m.group(1)) >= 67,
    "read-only device list": "iretail/device/get-by-channel-id" in ps,
    "read-only device info": "iretail/device/get-device-info" in ps,
    "register calls are zero in report": "register_calls=0" in ps,
    "config update disabled": "config_update_allowed=$false" in ps,
    "order sending disabled": "order_send_allowed=$false" in ps,
    "no raw server code persisted": "server_code=" not in ps,
    "run branch": "v0.5.67-s3-device-code-source-audit-fix" in run,
    "publish branch": "v0.5.67-s3-device-code-source-audit-fix" in pub,
    "raw report directory ignored": "test_reports/s3_device_code_source/S3_DEVICE_CODE_SOURCE_*/" in gitignore,
}

forbidden = [
    "iretail/device/register",
    "iretail/device/update-info",
    "iretail/device/register-external-system",
    "iretail/shift/get-current",
    "iretail/shift/open-shift",
    "iretail/shift/close-shift",
    "iretail/order/synchronize",
    "iretail/payment-in/create",
]
checks["forbidden routes absent"] = all(x not in ps for x in forbidden)

failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("device-code source guard failed: " + ", ".join(failed))
print(f"[OK] device-code source guard: {len(checks)} checks passed")
