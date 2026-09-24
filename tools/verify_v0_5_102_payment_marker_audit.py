from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
audit = (ROOT / "MAIN_27_FISCAL_PAYMENT_MARKER_AUDIT.bat").read_text(encoding="utf-8")
analyzer = (ROOT / "tools/Analyze-FiscalPaymentMarkerAudit.ps1").read_text(encoding="utf-8")

checks = {
    "versionCode 102+": bool(re.search(r"versionCode\s+(10[2-9]|1[1-9]\d|[2-9]\d{2,})", gradle)),
    "versionName present": bool(re.search(r"versionName\s+'[^']+'", gradle)),
    "audit explicitly read only": "PAYMENT MARKER AUDIT - READ ONLY" in audit and "sends NO PAYMENT" in audit,
    "audit sends no financial adb command": not bool(re.search(r"adb[^\n\r]*\bPAYMENT\b", audit, re.I)),
    "audit never enables real POS": "--ez real_pos_enabled true" not in audit,
    "audit restores persisted safe mode": "--ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true" in audit,
    "audit restores foreground UI": "--es machine_mode standalone --ez real_pos_enabled false" in audit,
    "audit reads Android marker": "fiscal_positive_payment_test_v1_0_1.attempt" in audit,
    "audit does not delete Android marker": "rm -f files/fiscal_positive_payment_test_v1_0_1.attempt" not in audit,
    "audit reads JL22 durable payment prefs": "iretail_jl22_kozen_payment_v1.xml" in audit,
    "audit reads Kozen durable bridge prefs": "iretail_payment_bridge_v1.xml" in audit,
    "audit preserves logs": "logcat -c" not in audit,
    "audit collects both logcats": "IretailKozenClient" in audit and "IretailKozenBridge" in audit,
    "analyzer checks unresolved state": "unresolved_request_id" in analyzer and "active_request" in analyzer,
    "analyzer counts direct payment evidence": "PAYMENT_TX_ONCE" in analyzer and "PAYMENT_CALL_BEGIN" in analyzer,
    "analyzer does not authorize repeat": "does not authorize another payment" in analyzer,
    "analyzer sanitizes payment identifiers": all(x in analyzer for x in ["rrn", "authCode", "receipt", "terminalId", "transactionId", "paymentTid"]),
    "analyzer removes only raw report files": 'Remove-Item -LiteralPath $src' in analyzer and "fiscal_positive_payment_test_v1_0_1.attempt" not in analyzer,
    "audit creates zip": "Compress-Archive" in audit,
}

failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("v0.5.102 marker audit guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.102 marker audit guard: {len(checks)} checks passed")
