from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
client=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_29_ACQUIRER_READONLY_SNAPSHOT.bat").read_text(encoding="utf-8")
publisher=(ROOT/"GIT_129_PUBLISH_ACQUIRER_SNAPSHOT.bat").read_text(encoding="utf-8")

start=client.find("public void readAcquirerSnapshot")
end=client.find("public void readLastTransaction",start)
snapshot=client[start:end] if start>=0 and end>start else ""

checks={
    "versionCode 108+": bool(re.search(r"versionCode\s+(108|10[9]|1[1-9]\d|[2-9]\d{2,})",gradle)),
    "versionName v0.5.108": "versionName '0.5.108-acquirer-readonly-diagnostics'" in gradle,
    "snapshot method exists": bool(snapshot),
    "snapshot only read commands": all(x in snapshot for x in ['"PING "', '"INFO "', '"GET_STATE "', '"GET_TERMINAL_DATA "']),
    "snapshot has no PAYMENT command": '"PAYMENT "' not in snapshot and "PAYMENT_TX_ONCE" not in snapshot,
    "snapshot reports beta profile": "betaProfile" in snapshot and "profileMessage" in snapshot,
    "snapshot reports no-financial marker": "noFinancialCommands=true" in snapshot,
    "main intent exists": "acquirer_readonly_snapshot" in main,
    "main rejects real POS": "!debuggable || !persisted.standalone || realPosEnabled" in main,
    "runner exact version": "0.5.108-acquirer-readonly-diagnostics" in runner,
    "runner never enables real POS": "--ez real_pos_enabled true" not in runner,
    "runner starts snapshot intent": "--ez acquirer_readonly_snapshot true" in runner,
    "runner no financial adb command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|CANCEL|REFUND|RECONCILIATION)\b",runner,re.I)),
    "runner collects verbose client logs": "IretailKozenClient:V" in runner,
    "summary uses sanitized JL22 log": 'findstr /I "SNAPSHOT_RESULT ACQUIRER_SNAPSHOT_OK ACQUIRER_SNAPSHOT_FAILED" "%OUT%\\05_jl22_logcat.txt"' in runner,
    "publisher current branch": "v0.5.108-acquirer-readonly-diagnostics" in publisher,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.108 acquirer snapshot guard failed: "+", ".join(failed))
print(f"[OK] v0.5.108 acquirer snapshot guard: {len(checks)} checks passed")
