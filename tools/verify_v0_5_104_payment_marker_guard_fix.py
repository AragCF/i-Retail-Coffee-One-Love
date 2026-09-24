from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
main26 = (ROOT / "MAIN_26_FISCAL_POSITIVE_PAYMENT_1RUB_TEST.bat").read_text(encoding="utf-8")

marker_path = "files/fiscal_positive_payment_test_v1_0_1.attempt"
contract = "contract=S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1"

idx_pre = main26.find("Checking durable payment state before build/install")
idx_build = main26.find("echo [1/10] Building current debug APK")
idx_install = main26.find("echo [3/10] Installing i-Retail APK on JL22...")
idx_post = main26.find("Re-checking durable payment state after install")

checks = {
    "versionCode 104+": bool(re.search(r"versionCode\s+(10[4-9]|1[1-9]\d|[2-9]\d{2,})", gradle)),
    "versionName present": bool(re.search(r"versionName\s+'[^']+'", gradle)),
    "runner version guard exists": 'EXPECTED_VERSION' in main26 and 'Wrong project version' in main26,
    "exact marker contract variable": f"MARKER_CONTRACT={contract}" in main26,
    "marker checked by cat for guards": main26.count(f"cat {marker_path}") >= 2,
    "no ls marker check": f"ls {marker_path}" not in main26,
    "exact contract findstr twice": main26.count('findstr /X /C:"%MARKER_CONTRACT%"') == 2,
    "precheck before build": 0 <= idx_pre < idx_build,
    "postcheck after install": 0 <= idx_install < idx_post,
    "unresolved checked twice": main26.count("unresolved_request_id") >= 2,
    "Windows consumed marker checked before build": main26.find("if exist \"%LOCAL_CONSUMED%\"") < idx_build,
    "marker never deleted": f"rm -f {marker_path}" not in main26,
    "post-install marker failure restores safe UI": "Genuine Android one-attempt marker exists after install." in main26 and "--ez real_pos_enabled false" in main26,
    "Windows never sends payment": not bool(re.search(r"adb[^\n\r]*\bPAYMENT\b", main26, re.I)),
    "one-attempt financial guard retained": "EXACTLY ONE PAYMENT ATTEMPT IS ALLOWED" in main26,
}

failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("v0.5.104 marker guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.104 marker guard: {len(checks)} checks passed")
