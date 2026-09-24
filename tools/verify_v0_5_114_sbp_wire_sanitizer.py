from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
contract=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpPaymentContract.kt").read_text(encoding="utf-8")
client=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java").read_text(encoding="utf-8")
client_codec=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/pos/SbpWireCodec.java").read_text(encoding="utf-8")
client_sanitizer=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/pos/WireProtocolSanitizer.java").read_text(encoding="utf-8")
bridge=(ROOT/"kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")
bridge_codec=(ROOT/"kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/SbpWireCodec.java").read_text(encoding="utf-8")
bridge_sanitizer=(ROOT/"kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/BridgeProtocolSanitizer.java").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_33_SBP_WIRE_SYNTHETIC_TEST.bat").read_text(encoding="utf-8")
publisher=(ROOT/"GIT_131_PUBLISH_SBP_WIRE_TEST.bat").read_text(encoding="utf-8")
ps=(ROOT/"tools/Sanitize-SbpWireReport.ps1").read_text(encoding="utf-8")

checks={
    "versionCode 114+": bool(re.search(r"versionCode\s+(114|11[5-9]|1[2-9]\d|[2-9]\d{2,})",gradle)),
    "versionName v0.5.114+": bool(re.search(r"versionName '0\\.5\\.(114|11[5-9]|1[2-9]\\d|[2-9]\\d{2,})[^']*'", gradle)),
    "wire contract recorded": 'WIRE_BRIDGE_VERSION = "0.5.5"' in contract and 'WIRE_CONTRACT = "BASE64URL_REDACTED_V1"' in contract,
    "bridge version 0.5.5+": ('BRIDGE_VERSION = "0.5.5"' in bridge or 'BRIDGE_VERSION = "0.5.6"' in bridge),
    "both sides use URL_SAFE Base64": "Base64.URL_SAFE" in bridge_codec and "Base64.URL_SAFE" in client_codec,
    "both sides cap raw payload": "MAX_RAW_LENGTH = 4096" in bridge_codec and "MAX_RAW_LENGTH = 4096" in client_codec,
    "bridge sanitizer covers payload fields": all(x in bridge_sanitizer for x in ["payloadB64","qrPayload","payload","qrIdB64","qrId"]),
    "client sanitizer covers payload fields": all(x in client_sanitizer for x in ["payloadB64","qrPayload","payload","qrIdB64","qrId"]),
    "bridge RX log sanitized": 'BridgeProtocolSanitizer.safeLogLine(request)' in bridge,
    "bridge TX log sanitized": 'BridgeProtocolSanitizer.safeLogLine(response)' in bridge,
    "JL22 stale RX log sanitized": 'WireProtocolSanitizer.safeLogLine(line)' in client,
    "bridge synthetic command exists": '"SBP_ECHO_QR".equals(command)' in bridge,
    "synthetic command returns payload only on wire": '" payloadB64=" + payloadB64' in bridge and "SBP_QR " in bridge,
    "wire command explicitly synthetic": "synthetic=true" in bridge and "wireContract=BASE64URL_REDACTED_V1" in bridge,
    "client roundtrip method exists": "runSyntheticSbpWireRoundTrip" in client,
    "client accepts wire bridge 0.5.5+": '"0.5.5".equals(bridgeVersion)' in client and '"0.5.6".equals(bridgeVersion)' in client,
    "client compares exact payload": "payload.equals(returnedPayload)" in client,
    "client logs hash not raw": "SBP_WIRE_OK" in client and "rawPayloadLogged=false noFinancialCommands=true" in client,
    "main diagnostic intent exists": "sbp_wire_synthetic_test" in main,
    "main wire test requires real POS false": "!debuggable || !persisted.standalone || realPosEnabled" in main,
    "main does not persist wire raw": "sbpSessionStore.save(record)" not in main[main.find("private fun maybeRunSbpWireSyntheticTest"):main.find("private fun maybeRunSbpRouteAudit")],
    "main logs no raw payload": "rawPayloadLogged=false" in main,
    "wire test cannot mark paid": "maybeRunSbpWireSyntheticTest" in main and "markPaymentConfirmed" not in main[main.find("private fun maybeRunSbpWireSyntheticTest"):main.find("private fun maybeRunSbpRouteAudit")],
    "live qrPayment still hard-disabled": "LIVE_CALL_ENABLED = false" in contract and "LIVE_QR_PAYMENT_ENABLED = false" in bridge,
    "no Binder transact QR slot": "binder.transact(TX_QR_PAYMENT" not in bridge,
    "runner exact version": "0.5.114-sbp-wire-sanitizer" in runner,
    "runner keeps real POS false": "--ez real_pos_enabled true" not in runner,
    "runner optionally upgrades Kozen": ":kozenBridge:assembleDebug" in runner and "bridge 0.5.5" in runner,
    "runner starts only synthetic wire intent": "--ez sbp_wire_synthetic_test true" in runner,
    "runner removes raw session before report sanitize": runner.find("Remove-Item -Force -LiteralPath $p") < runner.find("Sanitize-SbpWireReport.ps1"),
    "runner requires no raw synthetic marker in report": "SBP-SYNTHETIC-WIRE" in runner and "Raw synthetic payload leaked" in runner,
    "runner sends no financial adb command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QR_PAYMENT|QRPAYMENT|REFUND|CANCEL|RECONCILIATION)\b",runner,re.I)),
    "PowerShell sanitizer rejects raw payloadB64": "payloadB64" in ps and "SBP-SYNTHETIC-WIRE" in ps and "SAFETY_SCAN_OK" in ps,
    "publisher branch guard": "v0.5.114-sbp-wire-sanitizer" in publisher,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.114 SBP wire sanitizer guard failed: "+", ".join(failed))
print(f"[OK] v0.5.114 SBP wire sanitizer guard: {len(checks)} checks passed")
