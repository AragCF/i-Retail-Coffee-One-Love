from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
contract = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpPaymentContract.kt").read_text(encoding="utf-8")
store = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpSessionStore.kt").read_text(encoding="utf-8")
client = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java").read_text(encoding="utf-8")
bridge = (ROOT / "kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")
capture = (ROOT / "kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/SbpQrCapture.java").read_text(encoding="utf-8")
bridge_gradle = (ROOT / "kozenBridge/build.gradle").read_text(encoding="utf-8")
runner = (ROOT / "MAIN_34_SBP_EVENT_QUEUE_SYNTHETIC_TEST.bat").read_text(encoding="utf-8")

event_start = main.find("private fun maybeRunSbpEventQueueSyntheticTest")
wire_start = main.find("private fun maybeRunSbpWireSyntheticTest")
route_start = main.find("private fun maybeRunSbpRouteAudit")
event_section = main[event_start:wire_start]
wire_section = main[wire_start:route_start]

version_code_match = re.search(r"versionCode\s+(\d+)", gradle)
version_name_match = re.search(r"versionName\s+'([^']+)'", gradle)
version_code = int(version_code_match.group(1)) if version_code_match else 0
version_name = version_name_match.group(1) if version_name_match else ""

checks = {
    "app version 0.5.115+": version_code >= 115 and bool(version_name),
    "event contract constants": 'EVENT_BRIDGE_VERSION = "0.5.6"' in contract and 'EVENT_CONTRACT = "QR_EVENT_PEEK_ACK_V1"' in contract,
    "live call remains disabled": "LIVE_CALL_ENABLED = false" in contract and "LIVE_QR_PAYMENT_ENABLED = false" in bridge,
    "bridge source version 0.5.6": 'BRIDGE_VERSION = "0.5.6"' in bridge,
    "bridge APK metadata 0.5.6": "versionCode 10" in bridge_gradle and "versionName '0.5.6-sbp-event-queue'" in bridge_gradle,
    "bounded FIFO exists": "ArrayDeque<Event>" in capture and "MAX_EVENTS = 16" in capture and "removeFirst()" in capture,
    "monotonic event sequence": "nextSequence++" in capture,
    "idempotent ACK exists": "ALREADY_ACKED" in capture and "lastAckedSequence" in capture,
    "bridge exposes peek command": '"GET_SBP_QR_EVENT".equals(command)' in bridge,
    "bridge exposes ack command": '"ACK_SBP_QR_EVENT".equals(command)' in bridge,
    "bridge reports event contract": "sbpEventContract=QR_EVENT_PEEK_ACK_V1" in bridge,
    "bridge keeps wire logging sanitized": "payloadB64=" in bridge and "BridgeProtocolSanitizer.safeLogLine(response)" in bridge,
    "SmartSky callback enqueues event": 'capture(qrId, qrPayload, "smartsky-callback")' in bridge,
    "synthetic echo enqueues event": 'capture(qrId, payload, "synthetic")' in bridge,
    "client reads event": "readNextSbpQrEvent" in client and "GET_SBP_QR_EVENT" in client,
    "client ACKs exact sequence": "ACK_SBP_QR_EVENT" in client and '" sequence=" + sequence' in client,
    "client accepts idempotent ACK": "ALREADY_ACKED" in client,
    "client verifies payload integrity": "SBP_EVENT_INTEGRITY" in client and "WireProtocolSanitizer.shortHash(payload)" in client,
    "event test method boundaries found": event_start >= 0 and wire_start > event_start and route_start > wire_start,
    "event test requires safe mode": "!debuggable || !persisted.standalone || realPosEnabled" in event_section,
    "event test does not persist raw": "sbpSessionStore.save" not in event_section and "storedRaw=false" in event_section,
    "wire test no longer persists raw": "sbpSessionStore.save(record)" not in wire_section and "storedRaw=false" in wire_section,
    "store purges old non-dryrun raw": '!oldSessionId.startsWith("sbp-dryrun-")' in store and ".remove(KEY_QR_PAYLOAD)" in store,
    "store raw limited to synthetic dryrun": 'record.sessionId.startsWith("sbp-dryrun-") && !record.realPaymentSent' in store,
    "live QR command remains blocked": '"QR_PAYMENT".equals(command)) return qrPaymentBlocked(id)' in bridge,
    "no live Binder QR transact": "binder.transact(TX_QR_PAYMENT" not in bridge,
    "runner current app version": bool(version_name) and version_name in runner,
    "runner requests event test": "--ez sbp_event_queue_synthetic_test true" in runner,
    "runner keeps real POS false": "--ez real_pos_enabled true" not in runner,
    "runner sends no financial adb command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QR_PAYMENT|QRPAYMENT|REFUND|RECONCILIATION)\b", runner, re.I)),
    "runner scans for raw marker": "SBP-EVENT-QUEUE" in runner and "RAW QR PAYLOAD LEAK" in runner,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
if failed:
    raise SystemExit("v0.5.115 SBP event queue guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.115 SBP event queue guard: {len(checks)} checks passed")
