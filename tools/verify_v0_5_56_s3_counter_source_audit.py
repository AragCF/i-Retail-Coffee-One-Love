from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ps = (ROOT / "tools/iRetailCounterSourceDocsAudit.ps1").read_text(encoding="utf-8")
run = (ROOT / "S3_12_AUDIT_COUNTER_SOURCES.bat").read_text(encoding="utf-8")
publish = (ROOT / "S3_13_PUBLISH_COUNTER_SOURCE_AUDIT.bat").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

version_code_match = re.search(r"versionCode\s+(\d+)", gradle)
version_name_match = re.search(r"versionName\s+'([^']+)'", gradle)
run_branch_match = re.search(r'EXPECTED_BRANCH=([^"\r\n]+)', run)
publish_branch_match = re.search(r'EXPECTED_BRANCH=([^"\r\n]+)', publish)

version_code = int(version_code_match.group(1)) if version_code_match else 0
version_name = version_name_match.group(1) if version_name_match else ""
run_branch = run_branch_match.group(1) if run_branch_match else ""
publish_branch = publish_branch_match.group(1) if publish_branch_match else ""

patch_match = re.match(r"0\.5\.(\d+)", version_name)
patch_number = int(patch_match.group(1)) if patch_match else -1

checks = {
    "versionCode is not older than v0.5.56": version_code >= 56,
    "versionName is not older than v0.5.56": patch_number >= 56,
    "run/publish branch guards match": bool(run_branch) and run_branch == publish_branch,
    "branch guard remains counter-source audit": "s3-counter-source-audit" in run_branch,
    "documentation base only": "https://my.i-retail.com/api/apidoc/actual" in ps,
    "dynamic iretail controller discovery": "app-controllers-iretail-" in ps and "controller" in ps,
    "all counter terms": all(x in ps for x in ["order_counter","operation_counter","refund_counter","check_counter","counters"]),
    "no authentication": "user/authentication" not in ps and "access_token" not in ps and "client_secret" not in ps,
    "no curl mutation flags": all(x not in ps.lower() for x in ["--request","--data","--form","--upload-file"]),
    "summary states no working API calls": 'working_api_calls=0' in ps,
    "summary states register not called": 'device_register_called=$false' in ps,
    "summary states synchronize not called": 'order_synchronize_called=$false' in ps,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
if failed:
    raise SystemExit("S3 counter-source audit guard failed: " + ", ".join(failed))
print(f"[OK] S3 counter-source audit guard: {len(checks)} checks passed")
