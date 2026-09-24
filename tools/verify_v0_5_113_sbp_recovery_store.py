from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
store=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpSessionStore.kt").read_text(encoding="utf-8")
sbp=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpDryRun.kt").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_32_SBP_RESTART_RECOVERY_SMOKE.bat").read_text(encoding="utf-8")

checks={
    "versionCode 113+": bool(re.search(r"versionCode\s+(113|11[4-9]|1[2-9]\d|[2-9]\d{2,})",gradle)),
    "versionName present": bool(re.search(r"versionName\s+'[^']+'",gradle)),
    "durable store exists": 'getSharedPreferences(PREFS, Context.MODE_PRIVATE)' in store,
    "store keeps session id": 'KEY_SESSION_ID' in store,
    "store keeps state and amount": 'KEY_STATE' in store and 'KEY_AMOUNT_MINOR' in store,
    "store keeps generation": 'KEY_GENERATION' in store,
    "store has no QR payload key": 'KEY_QR' not in store and 'putString("qr' not in store.lower(),
    "store unresolved includes financial flag": 'get() = realPaymentSent || state in setOf(' in store,
    "adapter can recover": 'override fun recover(): SbpPaymentSnapshot?' in sbp,
    "active persisted session becomes uncertain": 'if (stored.unresolved) SbpPaymentState.UNCERTAIN' in sbp,
    "recovered QR id absent": 'qrId = null' in sbp,
    "recovered QR payload absent": 'qrPayload = null' in sbp,
    "new QR blocked while uncertain": 'recovered.state == SbpPaymentState.UNCERTAIN' in sbp,
    "adapter persists state": sbp.count('store?.save') >= 2,
    "adapter reset clears dry-run store": 'store?.clear()' in sbp,
    "main injects store": 'DryRunSbpPaymentAdapter(SbpSessionStore(this))' in main,
    "main probes recovery": 'sbp_recovery_probe' in main and 'RECOVERY_RESULT source=' in main,
    "main blocks unresolved dry-run": 'DRY_RUN_BLOCKED_UNRESOLVED' in main,
    "main clear restricted to dry-run": 'sbpPaymentAdapter.adapterId == "dry-run"' in main and '!sbpPaymentAdapter.liveFinancialEnabled' in main,
    "runner simulates process loss": 'am force-stop com.coffeeonelove.iretail' in runner,
    "runner requires uncertain": 'state=UNCERTAIN' in runner,
    "runner requires no QR id": 'qrIdPresent=false' in runner,
    "runner requires no QR payload": 'qrPayloadPresent=false' in runner,
    "runner rejects new QR after restart": 'NEW_QR_AFTER_RESTART' in runner,
    "runner never enables real POS": '--ez real_pos_enabled true' not in runner,
    "runner has no financial ADB command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QRPAYMENT|QR_PAYMENT|REFUND|CANCEL)\b",runner,re.I)),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.113 SBP recovery guard failed: "+", ".join(failed))
print(f"[OK] v0.5.113 SBP recovery guard: {len(checks)} checks passed")
