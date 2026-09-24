from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
contract=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpPaymentContract.kt").read_text(encoding="utf-8")
store=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpSessionStore.kt").read_text(encoding="utf-8")
dry=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpDryRun.kt").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_31_SBP_SESSION_RECOVERY_TEST.bat").read_text(encoding="utf-8")
gateway=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/pos/SmartSkyPosGateway.kt").read_text(encoding="utf-8")
bridge=(ROOT/"kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")

checks={
    "versionCode 111+": bool(re.search(r"versionCode\s+(111|11[2-9]|1[2-9]\d|[2-9]\d{2,})",gradle)),
    "versionName present": bool(re.search(r"versionName\s+'[^']+'",gradle)),
    "SBP operation type 42": 'OPERATION_TYPE = "42"' in contract,
    "SBP transaction type qrPayment": 'TRANSACTION_TYPE = "qrPayment"' in contract,
    "SBP currency 643": 'CURRENCY = "643"' in contract,
    "Binder slot 19 documented": "BINDER_TRANSACTION = 19" in contract,
    "live call hard-disabled": "LIVE_CALL_ENABLED = false" in contract,
    "production states include uncertainty": all(x in contract for x in ["QR_READY","WAITING","PAID","DECLINED","EXPIRED","CANCELLED","UNCERTAIN","ERROR"]),
    "private SBP session prefs": 'iretail_sbp_session_v1' in store and "Context.MODE_PRIVATE" in store,
    "payload retained privately for recovery": "KEY_QR_PAYLOAD" in store and ".putString(KEY_QR_PAYLOAD" in store,
    "safe summary hashes QR": "qrIdHash = digest(record.qrId)" in store and "qrPayloadHash = digest(record.qrPayload)" in store,
    "safe summary does not expose raw payload": "SbpSafeSummary(" in store and "qrPayloadLength" in store,
    "dry-run converts to durable record": "fun toSessionRecord(): SbpSessionRecord" in dry,
    "dry-run can restore": "fun restore(record: SbpSessionRecord)" in dry,
    "main loads active session first": "val active = sbpSessionStore.loadActive()" in main,
    "main restores rather than regenerates": "DRY_RUN_RECOVERED" in main and "sbpDryRunSession.restore(recovered)" in main,
    "main persists safe hashes": "qrPayloadHash=" in main and "qrPayloadLength=" in main,
    "synthetic confirmation never pays": "runtimeOrderPaid=false fiscalCalled=false machineCalled=false realQrPaymentSent=false" in main,
    "normal online payment still blocked": 'if (method != PaymentMethod.CARD)' in main,
    "no qrPayment call in main": ".qrPayment(" not in main,
    "no qrPayment call in gateway": ".qrPayment(" not in gateway,
    "bridge cannot execute live QR payment": (
        "binder.transact(TX_QR_PAYMENT" not in bridge and
        "LIVE_QR_PAYMENT_ENABLED = false" in bridge and
        "LIVE_QR_PAYMENT_NOT_APPROVED" in bridge
    ),
    "recovery runner exact version": "0.5.111-sbp-session-contract" in runner,
    "recovery runner keeps POS false": "--ez real_pos_enabled true" not in runner,
    "runner simulates restart": "am force-stop com.coffeeonelove.iretail" in runner and "DRY_RUN_RECOVERED" in runner,
    "runner requires same session": 'if /I not "%SESSION_BEFORE%"=="%SESSION_AFTER%"' in runner,
    "runner requires exactly one QR_READY": "Exactly one QR_READY across restart" in runner,
    "runner sends no financial adb command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QRPAYMENT|QR_PAYMENT|REFUND|CANCEL)\b",runner,re.I)),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.111 SBP session contract guard failed: "+", ".join(failed))
print(f"[OK] v0.5.111 SBP session contract guard: {len(checks)} checks passed")
