from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
analyzer = (ROOT / "tools/Analyze-FiscalPaymentMarkerAudit.ps1").read_text(encoding="utf-8")
runtime = (ROOT / "tools/Verify-FiscalPaymentMarkerAuditRuntime.ps1").read_text(encoding="utf-8")

checks = {
    "versionCode 103+": bool(re.search(r"versionCode\s+(10[3-9]|1[1-9]\d|[2-9]\d{2,})", gradle)),
    "versionName v0.5.103": "versionName '0.5.103-marker-audit-sanitizer'" in gradle,
    "summary sanitized before safety scan": 'Set-Content -LiteralPath (Join-Path $ReportDir "SUMMARY.txt") -Value (Redact $summaryText)' in analyzer,
    "fiscal draft safe copy": '07_fiscalization_dry_run_safe.txt' in analyzer,
    "fiscal draft raw removed": 'Remove-Item -LiteralPath $draftRaw' in analyzer,
    "long numeric redaction retained": r"\d{13,19}" in analyzer,
    "runtime fixture includes long IDs": "1760000000000" in runtime and "1234567890123456" in runtime,
    "runtime fixture checks no raw files": "Raw audit file survived sanitization" in runtime,
    "runtime fixture expects unresolved outcome": "UNRESOLVED_PAYMENT_PRESENT" in runtime,
}

failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("v0.5.103 marker audit sanitizer guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.103 marker audit sanitizer guard: {len(checks)} checks passed")
