from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
ps = (ROOT / "tools/iRetailOrderDocsAudit.ps1").read_text(encoding="utf-8")
run_bat = (ROOT / "S3_02_FETCH_ORDER_API_DOCS.bat").read_text(encoding="utf-8")
pub_bat = (ROOT / "S3_03_PUBLISH_ORDER_API_DOCS.bat").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

checks = {
    "canonical apiDoc base": 'https://my.i-retail.com/api/apidoc/actual' in ps,
    "PowerShell curl alias avoided": "function Curl(" not in ps and "Invoke-CurlToFile" in ps,
    "curl executable invoked explicitly": "& curl.exe" in ps,
    "index fetched first": 'index.html' in ps,
    "order controller discovery": 'ordercontroller' in ps.lower(),
    "reserve-order-id searched": '"reserve-order-id"' in ps,
    "synchronize searched": '"synchronize"' in ps,
    "employee_id searched": '"employee_id"' in ps,
    "pin searched": '"pin"' in ps,
    "offer_id searched": '"offer_id"' in ps,
    "idempotency searched": '"idempot"' in ps,
    "read-only declaration": 'order_send_allowed = $false' in ps.lower(),
    "summary says no order send": 'OrderSendAllowed=NO' in ps,
    "no curl POST request": '"--request"' not in ps and " -X " not in ps,
    "one-command audit publishes": "S3_03_PUBLISH_ORDER_API_DOCS.bat" in run_bat,
    "publisher only stages report": "s3_order_contract" in pub_bat and "git add --" in pub_bat,
    "unpacked report ignored": "test_reports/s3_order_contract/S3_ORDER_DOCS_*/" in gitignore,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("S3 order contract audit guard failed: " + ", ".join(failed))

print(f"[OK] S3 order contract audit guard: {len(checks)} checks passed")
