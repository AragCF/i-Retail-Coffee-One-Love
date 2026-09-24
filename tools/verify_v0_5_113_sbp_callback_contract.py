from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
contract=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpPaymentContract.kt").read_text(encoding="utf-8")
capture=(ROOT/"kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/SbpQrCapture.java").read_text(encoding="utf-8")
bridge=(ROOT/"kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")
client=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java").read_text(encoding="utf-8")

checks={
    "versionCode 113+": bool(re.search(r"versionCode\s+(113|11[4-9]|1[2-9]\d|[2-9]\d{2,})",gradle)),
    "versionName present": bool(re.search(r"versionName\s+'[^']+'",gradle)),
    "bridge version supports callback contract": any(x in bridge for x in ['BRIDGE_VERSION = "0.5.4"','BRIDGE_VERSION = "0.5.5"','BRIDGE_VERSION = "0.5.6"']),
    "client accepts bridge 0.5.4": '"0.5.4".equals(version)' in client,
    "production contract callback version": 'CALLBACK_BRIDGE_VERSION = "0.5.4"' in contract,
    "production contract callback name": 'CALLBACK_CONTRACT = "CAPTURE_HASHED_V1"' in contract,
    "live QR call remains disabled": "LIVE_CALL_ENABLED = false" in contract and "LIVE_QR_PAYMENT_ENABLED = false" in bridge,
    "capture stores raw only in memory": all(x in capture for x in ["final String qrId","final String payload","synchronized Event capture"]),
    "capture hashes QR id": "shortHash(qrId)" in capture,
    "capture hashes payload": "shortHash(payload)" in capture,
    "capture records payload length": "payload == null ? 0 : payload.length()" in capture,
    "bridge has SBP transaction callback": "class SbpTransactionCallback extends Binder" in bridge,
    "SBP callback captures on slot 2": 'SbpQrCapture.Event event = sbpQrCapture.capture(qrId, qrPayload, "smartsky-callback")' in bridge,
    "SBP callback logs hashes only": all(x in bridge for x in ["SBP_CALLBACK_QR sequence=","qrIdHash=","payloadHash=","payloadLength=","rawPayloadLogged=false"]),
    "legacy payment callback no longer logs raw qrId": "PAYMENT_CALLBACK_QR id=" not in bridge and "PAYMENT_CALLBACK_QR qrIdHash=" in bridge,
    "bridge advertises callback contract": "sbpCallbackContract=CAPTURE_HASHED_V1" in bridge,
    "route response advertises callback contract": "callbackContract=CAPTURE_HASHED_V1" in bridge,
    "blocked response advertises callback contract": "LIVE_QR_PAYMENT_NOT_APPROVED" in bridge and "callbackContract=CAPTURE_HASHED_V1" in bridge,
    "no live QR Binder transact": "binder.transact(TX_QR_PAYMENT" not in bridge,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.113 SBP callback contract guard failed: "+", ".join(failed))
print(f"[OK] v0.5.113 SBP callback contract guard: {len(checks)} checks passed")
