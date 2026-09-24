from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
client = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java").read_text(encoding="utf-8")
main26 = (ROOT / "MAIN_26_FISCAL_POSITIVE_PAYMENT_1RUB_TEST.bat").read_text(encoding="utf-8")

pre_start = client.find("public void preflight(PreflightListener listener)")
pre_end = client.find("public void startPayment", pre_start)
preflight = client[pre_start:pre_end]

checks = {
    "versionCode 106+": bool(re.search(r"versionCode\s+(10[6-9]|1[1-9]\d|[2-9]\d{2,})", gradle)),
    "versionName present": bool(re.search(r"versionName\s+'[^']+'", gradle)),
    "runner version guard exists": 'EXPECTED_VERSION' in main26 and 'Wrong project version' in main26,
    "preflight retry loop": "attempt <= 6" in preflight,
    "preflight retry marker": "PREFLIGHT_WARMUP_RETRY attempt=" in preflight,
    "retry delay": "Thread.sleep(1200L)" in preflight,
    "write-incomplete ping retryable": 'code.startsWith("WRITE_INCOMPLETE_PING_")' in client,
    "ping timeout retryable": 'code.startsWith("TIMEOUT_PING")' in client,
    "bad pong retryable": 'code.startsWith("BAD_PONG")' in client,
    "no PAYMENT in preflight method": '"PAYMENT "' not in preflight and "PAYMENT_TX_ONCE" not in preflight,
    "payment path still separate": "public void startPayment(String amountRub, Listener listener)" in client,
    "Kozen log cleared before first BridgeActivity": main26.find('adb -s "%KOZEN%" logcat -c') < main26.find('shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity'),
    "warmup at poll 1": 'if "%%S"=="1"' in main26 and "Kozen bridge warm-up 1/3" in main26,
    "warmup at poll 3": 'if "%%S"=="3"' in main26 and "Kozen bridge warm-up 2/3" in main26,
    "warmup at poll 5": 'if "%%S"=="5"' in main26 and "Kozen bridge warm-up 3/3" in main26,
    "warmup before failure check": main26.find("Kozen bridge warm-up 1/3") < main26.find('findstr /C:"TEST_PREFLIGHT_FAILED"'),
    "financial attempt guard retained": "EXACTLY ONE PAYMENT ATTEMPT IS ALLOWED" in main26,
    "Windows does not send payment": not bool(re.search(r"adb[^\n\r]*\bPAYMENT\b", main26, re.I)),
}

failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.106 AOA preflight warmup guard failed: "+", ".join(failed))
print(f"[OK] v0.5.106 AOA preflight warmup guard: {len(checks)} checks passed")
