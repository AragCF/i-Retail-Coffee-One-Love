from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
sbp=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpDryRun.kt").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_30_SBP_DRYRUN_UI_TEST.bat").read_text(encoding="utf-8")
gateway=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/pos/SmartSkyPosGateway.kt").read_text(encoding="utf-8")
bridge=(ROOT/"kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")

checks={
    "versionCode 110+": bool(re.search(r"versionCode\s+(110|11\d|1[2-9]\d|[2-9]\d{2,})",gradle)),
    "versionName present": bool(re.search(r"versionName\s+'[^']+'",gradle)),
    "SBP state machine exists": "enum class SbpDryRunState" in sbp,
    "synthetic payload explicit": "SBP-DRY-RUN" in sbp,
    "realPaymentSent always false": "realPaymentSent: Boolean = false" in sbp and "realPaymentSent = false" in sbp,
    "diagnostic intent exists": "sbp_dry_run_self_test" in main,
    "diagnostic requires real POS false": "!debuggable || !persisted.standalone || realPosEnabled" in main,
    "QR ready log exists": "DRY_RUN_QR_READY" in main,
    "scan transition exists": "DRY_RUN_QR_SCANNED" in main,
    "synthetic confirmation exists": "DRY_RUN_CONFIRMED" in main,
    "synthetic confirm never marks paid": "runtimeOrderPaid=false fiscalCalled=false machineCalled=false realQrPaymentSent=false" in main,
    "normal online payment still blocked": 'if (method != PaymentMethod.CARD)' in main,
    "no qrPayment call in main UI": ".qrPayment(" not in main,
    "no qrPayment call in SmartSkyPosGateway": ".qrPayment(" not in gateway,
    "production QR path remains blocked by default": (
        "LIVE_QR_PAYMENT_ENABLED = false" in bridge and
        "LIVE_QR_GENERATION_PROBE_ENABLED = false" in bridge and
        '"QR_PAYMENT".equals(command)) return qrPaymentBlocked(id)' in bridge and
        "LIVE_QR_PAYMENT_NOT_APPROVED" in bridge
    ),
    "runner keeps real POS false": "--ez real_pos_enabled true" not in runner,
    "runner starts dry-run intent": "--ez sbp_dry_run_self_test true" in runner,
    "runner sends no financial adb command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QRPAYMENT|QR_PAYMENT|REFUND|CANCEL)\b",runner,re.I)),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.110 SBP dry-run guard failed: "+", ".join(failed))
print(f"[OK] v0.5.110 SBP dry-run guard: {len(checks)} checks passed")
