from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ps = (ROOT / "tools/iRetailCounterSourceDocsAudit.ps1").read_text(encoding="utf-8")
run = (ROOT / "S3_12_AUDIT_COUNTER_SOURCES.bat").read_text(encoding="utf-8")
publish = (ROOT / "S3_13_PUBLISH_COUNTER_SOURCE_AUDIT.bat").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

checks = {
    "versionCode 56": "versionCode 56" in gradle,
    "versionName 0.5.56": "0.5.56-s3-counter-source-audit" in gradle,
    "run branch guard": "v0.5.56-s3-counter-source-audit" in run,
    "publish branch guard": "v0.5.56-s3-counter-source-audit" in publish,
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
    raise SystemExit("v0.5.56 counter-source audit guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.56 counter-source audit guard: {len(checks)} checks passed")
