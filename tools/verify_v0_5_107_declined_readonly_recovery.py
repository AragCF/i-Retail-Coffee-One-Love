from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
client=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_28_DECLINED_PAYMENT_READONLY_RECOVERY.bat").read_text(encoding="utf-8")
publisher=(ROOT/"GIT_128_PUBLISH_DECLINED_READONLY_RECOVERY.bat").read_text(encoding="utf-8")
main26=(ROOT/"MAIN_26_FISCAL_POSITIVE_PAYMENT_1RUB_TEST.bat").read_text(encoding="utf-8")

start=client.find("public void readLastTransaction")
end=client.find("public void startPayment",start)
recovery=client[start:end] if start>=0 and end>start else ""

checks={
    "versionCode 107+": bool(re.search(r"versionCode\s+(10[7-9]|1[1-9]\d|[2-9]\d{2,})",gradle)),
    "versionName v0.5.107": "versionName '0.5.107-declined-readonly-recovery'" in gradle,
    "read-only client method exists": bool(recovery),
    "recovery reads last transaction": "GET_LAST_TRANSACTION " in recovery,
    "recovery may target receipt": "GET_TRANSACTION " in recovery,
    "recovery has no PAYMENT command literal": '"PAYMENT "' not in recovery,
    "recovery result omits rrn/auth/tid": "READ_ONLY_RECOVERY_OK" in recovery and "rrn=" not in recovery and "authCode=" not in recovery and "terminalId=" not in recovery,
    "main intent exists": "fiscal_declined_payment_recovery" in main,
    "main recovery rejects real POS": "!debuggable || !persisted.standalone || realPosEnabled" in main,
    "main logs no-financial marker": "noFinancialCommands=true" in main,
    "runner exact version": "0.5.107-declined-readonly-recovery" in runner,
    "runner never enables real POS": "--ez real_pos_enabled true" not in runner,
    "runner starts only recovery intent": "--ez fiscal_declined_payment_recovery true" in runner,
    "runner no adb financial command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|CANCEL|REFUND)\b",runner,re.I)),
    "runner collects safe client logs": "IretailKozenClient:V" in runner,
    "runner preserves attempt marker": "rm -f files/fiscal_positive_payment_test_v1_0_1.attempt" not in runner,
    "publisher branch guard": "v0.5.107-declined-readonly-recovery" in publisher,
    "future payment report keeps warning logs": "IretailKozenClient:V" in main26 and "IretailKozenClient:I IretailKozenClient:W IretailKozenClient:E" not in main26,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.107 declined recovery guard failed: "+", ".join(failed))
print(f"[OK] v0.5.107 declined recovery guard: {len(checks)} checks passed")
