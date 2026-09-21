from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ps = (ROOT / "tools/iRetailAdminDeviceInventoryAudit.ps1").read_text(encoding="utf-8")
run = (ROOT / "S3_22_AUDIT_ADMIN_DEVICE_INVENTORY.bat").read_text(encoding="utf-8")
pub = (ROOT / "S3_23_PUBLISH_ADMIN_DEVICE_INVENTORY.bat").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

m = re.search(r"versionCode\s+(\d+)", gradle)

checks = {
    "versionCode at least 73": bool(m) and int(m.group(1)) >= 73,
    "admin find": "admin/device/find" in ps,
    "admin count": "admin/device/get-count-device-in-channel" in ps,
    "admin device info": "admin/device/get-device-info" in ps,
    "admin devices involved in orders": "admin/device/get-list-device-involved-in-orders" in ps,
    "mutating calls zero": "mutating_calls=0" in ps,
    "create disabled": "device_create_allowed=$false" in ps,
    "update disabled": "device_update_allowed=$false" in ps,
    "repeat activation disabled": "repeat_activation_allowed=$false" in ps,
    "remove disabled": "device_remove_allowed=$false" in ps,
    "order sending disabled": "order_send_allowed=$false" in ps,
    "run branch": "v0.5.73-s3-admin-device-inventory-audit" in run,
    "publish branch": "v0.5.73-s3-admin-device-inventory-audit" in pub,
    "raw reports ignored": "test_reports/s3_admin_device_inventory/S3_ADMIN_DEVICE_INVENTORY_*/" in gitignore,
}

forbidden = [
    "admin/device/create",
    "admin/device/update",
    "admin/device/remove",
    "admin/device/repeat-activation",
    "admin/device/restore",
    "admin/device/block",
    "admin/device/unlock",
    "iretail/device/register",
    "iretail/device/register-external-system",
    "iretail/order/synchronize",
    "iretail/payment-in/create",
    "iretail/shift/open-shift",
    "iretail/shift/close-shift",
]
checks["forbidden routes absent"] = all(x not in ps for x in forbidden)

failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("admin-device inventory guard failed: " + ", ".join(failed))
print(f"[OK] admin-device inventory guard: {len(checks)} checks passed")
