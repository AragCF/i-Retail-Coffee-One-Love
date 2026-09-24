from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
main26 = (ROOT / "MAIN_26_FISCAL_POSITIVE_PAYMENT_1RUB_TEST.bat").read_text(encoding="utf-8")
assert_ps = (ROOT / "tools/Assert-FiscalPositivePayment1Rub.ps1").read_text(encoding="utf-8")

checks = {
    "versionCode 105+": bool(re.search(r"versionCode\s+(10[5-9]|1[1-9]\d|[2-9]\d{2,})", gradle)),
    "versionName v0.5.105": "versionName '0.5.105-kozen-bridge-retrigger'" in gradle,
    "runner version synced": '0.5.105-kozen-bridge-retrigger' in main26,
    "read-only preflight retained": 'No PAYMENT is sent during this preflight.' in main26,
    "Kozen bridge retrigger exists": 'Re-triggering Kozen BridgeActivity after AOA re-enumeration' in main26,
    "retrigger occurs at fifth poll": 'if "%%S"=="5" if "%KOZEN_ADB_AVAILABLE%"=="1"' in main26,
    "retrigger starts only bridge activity": 'am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity' in main26,
    "Windows never sends PAYMENT": not bool(re.search(r"adb[^\n\r]*\bPAYMENT\b", main26, re.I)),
    "preflight failure stays unused": 'Authorized financial attempt remains UNUSED. No payment marker was created.' in main26,
    "assert handles preflight failure": '"TEST_PREFLIGHT_FAILED"' in assert_ps and '"TEST_PREFLIGHT_TIMEOUT"' in assert_ps,
    "missing marker error accepted for no-attempt": 'No such file or directory' in assert_ps,
    "safe no-attempt returns non-success": 'Positive acceptance is incomplete.' in assert_ps and 'exit 2' in assert_ps,
    "positive marker assertion retained": 'contract=S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1' in assert_ps,
}

failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("v0.5.105 Kozen retrigger guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.105 Kozen retrigger guard: {len(checks)} checks passed")
