from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
ps = (ROOT / "tools/iRetailOrderDependencyDocsAudit.ps1").read_text(encoding="utf-8")
run_bat = (ROOT / "S3_04_FETCH_ORDER_DEPENDENCY_DOCS.bat").read_text(encoding="utf-8")
pub_bat = (ROOT / "S3_05_PUBLISH_ORDER_DEPENDENCY_DOCS.bat").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

checks = {
    "explicit curl.exe": "& curl.exe" in ps,
    "no Curl alias function": "function Curl(" not in ps,
    "device docs": "iretail-devicecontroller" in ps,
    "shift docs": "iretail-shiftcontroller" in ps,
    "employee docs": "iretail-employeecontroller" in ps,
    "operation docs": "iretail-operationcontroller" in ps,
    "payment docs": "iretail-paymentincontroller" in ps,
    "offer docs": "iretail-offercontroller" in ps,
    "reference docs": "referencecontroller" in ps,
    "service-in docs": "serviceincontroller" in ps,
    "employee_id searched": '"employee_id"' in ps,
    "shift_id searched": '"shift_id"' in ps,
    "service_in_slug searched": '"service_in_slug"' in ps,
    "order statuses searched": '"order_status_id"' in ps and '"payment_status_id"' in ps,
    "order numbering searched": '"order_number"' in ps and '"short_number"' in ps and '"number_to_day"' in ps,
    "product tax fields searched": '"tax_rate"' in ps and '"tax_included_in_price"' in ps,
    "read-only summary": 'order_send_allowed = $false' in ps.lower(),
    "no POST curl": '"--request"' not in ps and " -X " not in ps,
    "one-command publisher": "S3_05_PUBLISH_ORDER_DEPENDENCY_DOCS.bat" in run_bat,
    "publisher stages dependency report": "s3_order_dependencies" in pub_bat and "git add --" in pub_bat,
    "unpacked report ignored": "test_reports/s3_order_dependencies/S3_ORDER_DEPS_*/" in gitignore,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("S3 dependency audit guard failed: " + ", ".join(failed))

print(f"[OK] S3 dependency audit guard: {len(checks)} checks passed")
