from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
bridge_gradle=(ROOT/"kozenBridge/build.gradle").read_text(encoding="utf-8")
bridge=(ROOT/"kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")
client=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_31_SBP_ROUTE_READONLY_AUDIT.bat").read_text(encoding="utf-8")

start=client.find("public void readSbpRouteSnapshot")
end=client.find("public void readAcquirerSnapshot",start)
snapshot=client[start:end] if start>=0 and end>start else ""

checks={
    "versionCode 111+": bool(re.search(r"versionCode\s+(111|11[2-9]|1[2-9]\d|[2-9]\d{2,})",gradle)),
    "versionName v0.5.111": "versionName '0.5.111-sbp-route-readonly-contract'" in gradle,
    "bridge version 0.5.3": "versionName '0.5.3-sbp-route-readonly'" in bridge_gradle and 'BRIDGE_VERSION = "0.5.3"' in bridge,
    "generic route finder": "private PaymentRoute findRoute" in bridge,
    "card route retained": 'findRoute(data, "00", "payment"' in bridge,
    "SBP route exact": 'findRoute(data, "42", "qrPayment"' in bridge,
    "terminal data exposes SBP fields": all(x in bridge for x in ["qrPayment=", "qrPaymentTid=", "qrPaymentType=", "qrTransactionType=", "qrCurrencies="]),
    "bridge contains no qrPayment invocation": ".qrPayment(" not in bridge and "TX_QR_PAYMENT" not in bridge,
    "client supports bridge 0.5.2 and 0.5.3": '"0.5.2".equals(version) || "0.5.3".equals(version)' in client,
    "read-only SBP snapshot exists": bool(snapshot),
    "snapshot sends only read commands": all(x in snapshot for x in ['"PING "', '"INFO "', '"GET_STATE "', '"GET_TERMINAL_DATA "']),
    "snapshot has no financial command": '"PAYMENT "' not in snapshot and '"QR_PAYMENT "' not in snapshot,
    "legacy bridge truthfully reported": "LEGACY_BRIDGE_NO_SBP_ROUTE_FIELDS" in snapshot,
    "main requires exact 42/qrPayment": 'result.routeType == "42"' in main and 'equals("qrPayment", ignoreCase = true)' in main,
    "main keeps realPos false": "ROUTE_START" in main and "realPos=false noFinancialCommands=true" in main,
    "runner exact version": "0.5.111-sbp-route-readonly-contract" in runner,
    "runner updates Kozen only when ADB available": 'if "%KOZEN_ADB_AVAILABLE%"=="1" (' in runner and ':kozenBridge:assembleDebug' in runner,
    "runner skips Kozen update safely": "Kozen bridge update skipped: Windows ADB unavailable." in runner,
    "runner never enables real POS": "--ez real_pos_enabled true" not in runner,
    "runner no financial ADB command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QRPAYMENT|QR_PAYMENT|REFUND|CANCEL)\b",runner,re.I)),
    "cmd block expansion guard": runner.find('set "GRADLE_EXE="') < runner.find("echo [2/6] Building and installing Kozen bridge 0.5.3") and runner.find('set "KOZEN_APK=') < runner.find("echo [2/6] Building and installing Kozen bridge 0.5.3"),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.111 SBP route guard failed: "+", ".join(failed))
print(f"[OK] v0.5.111 SBP route guard: {len(checks)} checks passed")
