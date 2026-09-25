from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
runner = (ROOT / "MAIN_30_SBP_DRYRUN_UI_TEST.bat").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
contract = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpPaymentContract.kt").read_text(encoding="utf-8")
bridge = (ROOT / "kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")

version_code_match = re.search(r"versionCode\s+(\d+)", gradle)
version_name_match = re.search(r"versionName\s+'([^']+)'", gradle)
version_code = int(version_code_match.group(1)) if version_code_match else 0
version_name = version_name_match.group(1) if version_name_match else ""

checks = {
    "app version 0.5.120+": version_code >= 120 and bool(version_name),
    "runner current version": bool(version_name) and version_name in runner,
    "phase 1 timeout exists": 'set "OUTCOME=DRY_RUN_QR_TIMEOUT"' in runner,
    "phase 2 timeout exists": 'set "OUTCOME=DRY_RUN_CONFIRM_TIMEOUT"' in runner,
    "phase 1 has own 180 second window": "[WAIT 1/2]" in runner and runner.count("for /l %%S in (1,1,180)") >= 2,
    "phase 2 has fresh 180 second window": "[WAIT 2/2]" in runner and "fresh 180 seconds" in runner,
    "QR scan event advances phase": 'findstr /C:"DRY_RUN_QR_SCANNED"' in runner and "goto WAIT_CONFIRM" in runner,
    "recovered WAITING skips phase 1": "DRY_RUN_RECOVERED" in runner and "state=WAITING" in runner,
    "confirmation event ends successfully": 'findstr /C:"DRY_RUN_CONFIRMED"' in runner and 'set "OUTCOME=DRY_RUN_OK"' in runner,
    "crash fail-fast preserved": 'findstr /C:"FATAL EXCEPTION:"' in runner and "DRY_RUN_CRASH" in runner,
    "Android 6 restore fix preserved": "generationCounter.compareAndSet" in (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpDryRun.kt").read_text(encoding="utf-8"),
    "landscape QR flow preserved": "DRY_RUN_QR_SCANNED" in main and "DRY_RUN_CONFIRMED" in main and "SbpQrRenderer.render(payload, 640)" in main,
    "live QR still disabled": "LIVE_CALL_ENABLED = false" in contract and "LIVE_QR_PAYMENT_ENABLED = false" in bridge,
    "live QR probe remains locked": "LIVE_QR_GENERATION_PROBE_ENABLED = false" in bridge and '"QR_PAYMENT".equals(command)) return qrPaymentBlocked(id)' in bridge,
    "real POS remains false": "--ez real_pos_enabled true" not in runner,
    "no financial adb command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QR_PAYMENT|QRPAYMENT|REFUND|RECONCILIATION)\b", runner, re.I)),
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.120 phase-aware SBP dry-run guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.120 phase-aware SBP dry-run guard: {len(checks)} checks passed")
