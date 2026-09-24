from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
client=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
contract=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpPaymentContract.kt").read_text(encoding="utf-8")
bridge=(ROOT/"kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_32_SBP_ROUTE_READONLY_AUDIT.bat").read_text(encoding="utf-8")
publisher=(ROOT/"GIT_130_PUBLISH_SBP_ROUTE_AUDIT.bat").read_text(encoding="utf-8")

checks={
    "versionCode 112+": bool(re.search(r"versionCode\s+(112|11[3-9]|1[2-9]\d|[2-9]\d{2,})",gradle)),
    "versionName present": bool(re.search(r"versionName\s+'[^']+'",gradle)),
    "bridge version supports route audit": any(x in bridge for x in ['BRIDGE_VERSION = "0.5.3"','BRIDGE_VERSION = "0.5.4"','BRIDGE_VERSION = "0.5.5"']),
    "bridge documents QR binder slot 19": "TX_QR_PAYMENT = 19" in bridge,
    "bridge hard-disables live QR": "LIVE_QR_PAYMENT_ENABLED = false" in bridge,
    "bridge exposes read-only GET_SBP_ROUTE": '"GET_SBP_ROUTE".equals(command)' in bridge and "getSbpRouteResponse" in bridge,
    "SBP route is exact 42/qrPayment": 'findRoute(data, "42", "qrPayment"' in bridge,
    "SBP route requires currency 643": "SUPPORTED_CURRENCY" in bridge and 'sbpCurrency=' in bridge,
    "bridge route response omits raw TID": "tidPresent=" in bridge and 'sbpTidPresent=' in bridge,
    "QR_PAYMENT AOA command is hard-blocked": '"QR_PAYMENT".equals(command)' in bridge and "LIVE_QR_PAYMENT_NOT_APPROVED" in bridge,
    "no Binder transact on QR slot": "binder.transact(TX_QR_PAYMENT" not in bridge,
    "client supports bridge 0.5.2 and 0.5.3": '"0.5.2".equals(version) || "0.5.3".equals(version)' in client,
    "client has SBP route result": "class SbpRouteResult" in client and "interface SbpRouteListener" in client,
    "client returns upgrade required on old bridge": "BRIDGE_UPGRADE_REQUIRED" in client,
    "client sends only GET_SBP_ROUTE for route audit": '"GET_SBP_ROUTE " + routeId' in client,
    "main exposes route audit intent": "sbp_route_readonly_audit" in main,
    "main route audit rejects real POS": "!debuggable || !persisted.standalone || realPosEnabled" in main,
    "main route result is safe": "ROUTE_RESULT ok=" in main and "noFinancialCommands=true" in main,
    "production contract live flag false": "LIVE_CALL_ENABLED = false" in contract,
    "runner exact version": "0.5.112-sbp-route-audit" in runner,
    "runner optionally builds bridge": ":kozenBridge:assembleDebug" in runner,
    "runner tolerates missing Kozen ADB": "KOZEN ADB] unavailable - allowed." in runner,
    "runner keeps real POS false": "--ez real_pos_enabled true" not in runner,
    "runner starts only read-only route intent": "--ez sbp_route_readonly_audit true" in runner,
    "runner recognizes bridge upgrade": "BRIDGE_UPGRADE_REQUIRED" in runner,
    "runner sends no financial adb command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QR_PAYMENT|QRPAYMENT|REFUND|CANCEL|RECONCILIATION)\b",runner,re.I)),
    "publisher branch guard": "v0.5.112-sbp-route-audit" in publisher,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.112 SBP route audit guard failed: "+", ".join(failed))
print(f"[OK] v0.5.112 SBP route audit guard: {len(checks)} checks passed")
