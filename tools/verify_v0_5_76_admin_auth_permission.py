from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
ps=(ROOT/"tools/iRetailAdminAuthPermissionAudit.ps1").read_text(encoding="utf-8")
run=(ROOT/"S3_24_AUDIT_ADMIN_AUTH_PERMISSION.bat").read_text(encoding="utf-8")
pub=(ROOT/"S3_25_PUBLISH_ADMIN_AUTH_PERMISSION.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
gitignore=(ROOT/".gitignore").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)

checks={
    "versionCode at least 76": bool(m) and int(m.group(1)) >= 76,
    "ordinary auth": "user/authentication" in ps,
    "admin auth": "user/admin-authentication" in ps,
    "permissions read": "user/get-permissions" in ps,
    "profile list read": "user/get-profile-list" in ps,
    "conditional admin find": "admin/device/find" in ps and "admin.token" in ps,
    "mutating calls zero": "mutating_calls=0" in ps,
    "admin create disabled": "admin_device_create_allowed=$false" in ps,
    "admin update disabled": "admin_device_update_allowed=$false" in ps,
    "repeat activation disabled": "repeat_activation_allowed=$false" in ps,
    "register disabled": "device_register_allowed=$false" in ps,
    "order disabled": "order_send_allowed=$false" in ps,
    "run branch": "v0.5.76-s3-admin-auth-permission-audit" in run,
    "publish branch": "v0.5.76-s3-admin-auth-permission-audit" in pub,
    "raw reports ignored": "test_reports/s3_admin_auth_permission/S3_ADMIN_AUTH_PERMISSION_*/" in gitignore,
}

forbidden=[
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
checks["forbidden routes absent"]=all(x not in ps for x in forbidden)

failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("admin-auth permission guard failed: " + ", ".join(failed))
print(f"[OK] admin-auth permission guard: {len(checks)} checks passed")
