from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
ps = (ROOT / "tools/iRetailLiveReferenceAudit.ps1").read_text(encoding="utf-8")
run_bat = (ROOT / "S3_06_FETCH_LIVE_REFERENCE_DATA.bat").read_text(encoding="utf-8")
pub_bat = (ROOT / "S3_07_PUBLISH_LIVE_REFERENCE_DATA.bat").read_text(encoding="utf-8")
safe_ps = (ROOT / "tools/Assert-S3LiveReferenceSafe.ps1").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

required_paths = [
    "reference/get-order-status",
    "reference/get-order-statuses",
    "reference/get-order-payment-status",
    "reference/get-statuses-operation",
    "reference/get-types-operation",
    "reference/get-statuses-shift",
    "reference/get-currencies",
    "reference/get-types-offer",
    "service-in/get-service-in",
    "service-in/get-service-in-list",
    "service-in/get-service-in-types",
    "iretail/shift/get-current-active-shift",
    "iretail/employee/get-by-channel",
    "iretail/device/get-device-info",
    "iretail/tax/get",
]

forbidden_request_literals = [
    'path="iretail/order/synchronize"',
    'path="iretail/device/register"',
    'path="iretail/shift/open-shift"',
    'path="iretail/shift/close-shift"',
    'path="iretail/employee/authorize"',
    'path="iretail/payment-in/create"',
]

checks = {
    "versionCode 50": "versionCode 50" in build,
    "versionName 0.5.50": "versionName '0.5.50-s3-live-reference-audit'" in build,
    "explicit curl.exe": "& curl.exe" in ps,
    "no PowerShell Curl alias function": "function Curl(" not in ps,
    "auth raw is temp only": 'Join-Path $tmp "auth.json"' in ps,
    "endpoint raw is temp only": 'Join-Path $tmp ($request.name + ".raw")' in ps,
    "access token kept out of report": "token_present" in ps and "access_token=$token" in ps,
    "sensitive key sanitizer": "Is-SensitiveKey" in ps and "device_code" in ps and "pin" in ps,
    "employee name sanitizer": 'employees_by_channel' in ps and "RedactPersonName" in ps,
    "secret scan before ZIP": "Safety scan failed" in ps,
    "order send disabled in summary": "order_send_allowed=$false" in ps,
    "one-command publisher": "S3_07_PUBLISH_LIVE_REFERENCE_DATA.bat" in run_bat,
    "publisher runs safety validator": "Assert-S3LiveReferenceSafe.ps1" in pub_bat,
    "safety validator rejects raw/form": r"\.form$" in safe_ps and r"\.raw$" in safe_ps,
    "unpacked report ignored": "test_reports/s3_live_reference/S3_LIVE_REF_*/" in gitignore,
}

for path in required_paths:
    checks[f"read-only endpoint {path}"] = f'path="{path}"' in ps

for literal in forbidden_request_literals:
    checks[f"forbidden request absent {literal}"] = literal not in ps

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.50 S3 live reference audit guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.50 S3 live reference audit guard: {len(checks)} checks passed")
