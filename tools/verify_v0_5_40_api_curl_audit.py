from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]

build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
audit_bat = (ROOT / "RAPI_01_FETCH_DOCS_AND_TEST_CATALOG.bat").read_text(encoding="utf-8")
publish_bat = (ROOT / "RAPI_02_PUBLISH_LATEST_API_AUDIT.bat").read_text(encoding="utf-8")
audit_ps = (ROOT / "tools/iRetailApiCurlAudit.ps1").read_text(encoding="utf-8")
safe_ps = (ROOT / "tools/Assert-RetailApiAuditSafe.ps1").read_text(encoding="utf-8")
syntax_ps = (ROOT / "tools/Verify-RetailApiAuditPowerShell.ps1").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
config = json.loads((ROOT / "app/src/main/assets/content/iretail-api.json").read_text(encoding="utf-8"))

joined = "\n".join([audit_bat, publish_bat, audit_ps, safe_ps, syntax_ps])

checks = {
    "versionCode 40": "versionCode 40" in build,
    "versionName 0.5.40": "versionName '0.5.40-api-curl-audit'" in build,
    "canonical API docs URL": "https://my.i-retail.com/api/apidoc/actual" in audit_ps,
    "docs index snapshot": '"index.html"' in audit_ps,
    "docs api_data snapshot": '"api_data.js"' in audit_ps,
    "docs api_project snapshot": '"api_project.js"' in audit_ps,
    "auth route matches Android": 'user/authentication' in audit_ps,
    "catalog route matches Android": 'iretail/catalog/download-actual-zip' in audit_ps,
    "form-urlencoded request": 'application/x-www-form-urlencoded' in audit_ps,
    "auth fields username/password/client": all(x in audit_ps for x in ["username=", "password=", "client_id=", "client_secret="]) or all(x in audit_ps for x in ["username=[string]$config.login", "password=[string]$config.password", "client_id=[string]$config.client_id", "client_secret=[string]$config.client_secret"]),
    "catalog fields token/channel": "access_token=$token" in audit_ps and "channel_id=[string]$config.channel_id" in audit_ps,
    "raw auth stays temporary": 'Join-Path $tmp "auth.json"' in audit_ps,
    "raw catalog response starts temporary": 'Join-Path $tmp "catalog.raw"' in audit_ps,
    "report is sanitized before zip": "Safety scan failed" in audit_ps,
    "publisher runs safety scanner": "Assert-RetailApiAuditSafe.ps1" in publish_bat,
    "one-command audit auto publishes": "RAPI_02_PUBLISH_LATEST_API_AUDIT.bat" in audit_bat,
    "unpacked audit ignored": "test_reports/retail_api_curl/RAPI_CURL_*/" in gitignore,
    "PowerShell syntax checker exists": "Parser]::ParseFile" in syntax_ps,
}

for key in ("login", "password", "client_secret"):
    value = str(config.get(key, ""))
    if value:
        checks[f"{key} value not hardcoded into new audit scripts"] = value not in joined

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.40 API curl audit guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.40 API curl audit guard: {len(checks)} checks passed")
