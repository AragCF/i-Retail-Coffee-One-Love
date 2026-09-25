from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
bridge_gradle = (ROOT / "kozenBridge/build.gradle").read_text(encoding="utf-8")
bridge = (ROOT / "kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")
bridge_ui = (ROOT / "kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/BridgeActivity.java").read_text(encoding="utf-8")
client = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
contract = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpPaymentContract.kt").read_text(encoding="utf-8")

checks = {
    "app version 0.5.121": "versionCode 121" in gradle and "versionName '0.5.121-sbp-qr-source-probe'" in gradle,
    "bridge version 0.5.7": 'BRIDGE_VERSION = "0.5.7"' in bridge,
    "bridge APK metadata 0.5.7": "versionCode 11" in bridge_gradle and "versionName '0.5.7-sbp-qr-source-probe'" in bridge_gradle,
    "bridge UI version truthful": "Kozen Payment Bridge 0.5.7" in bridge_ui,
    "normal production QR remains disabled": "LIVE_QR_PAYMENT_ENABLED = false" in bridge and "LIVE_CALL_ENABLED = false" in contract,
    "probe is hardware locked in bridge": "LIVE_QR_GENERATION_PROBE_ENABLED = false" in bridge,
    "probe is locked in JL22 contract": "LIVE_QR_GENERATION_PROBE_ENABLED = false" in contract,
    "ordinary QR_PAYMENT remains blocked": '"QR_PAYMENT".equals(command)) return qrPaymentBlocked(id)' in bridge,
    "probe command has dedicated name": '"START_SBP_QR_PROBE".equals(command)' in bridge and '"GET_SBP_PROBE_STATUS".equals(command)' in bridge,
    "probe requires explicit token": 'LIVE_QR_PROBE_TOKEN = "LIVE_SBP_QR_1RUB"' in bridge and 'BAD_PROBE_TOKEN' in bridge,
    "probe amount fixed at 1 RUB": 'new BigDecimal("1.00")' in bridge and "PROBE_AMOUNT_MUST_BE_1_00" in bridge,
    "probe currency fixed at 643": 'SUPPORTED_CURRENCY.equals(arg(args, "currency"))' in bridge,
    "fresh route required": 'findRoute(fresh, "42", "qrPayment", null, SUPPORTED_CURRENCY)' in bridge,
    "probe state persisted before worker": '.putString(sbpProbeStatusKey(requestId), "STARTED")' in bridge and '.putString(PREF_ACTIVE_SBP_REQUEST, requestId)' in bridge,
    "Binder qrPayment exists only behind probe path": "binder.transact(TX_QR_PAYMENT" in bridge and "callSbpQrPayment" in bridge,
    "Binder call is moved off AOA thread": 'new Thread(' in bridge and "runSbpQrGenerationProbe" in bridge,
    "client persists unresolved probe": "PREF_SBP_PROBE_UNRESOLVED_ID" in client and "persistSbpProbeUnresolved" in client,
    "client sends probe once": "SBP_PROBE_TX_ONCE" in client and "START_SBP_QR_PROBE" in client,
    "client supports bridge 0.5.7": '"0.5.7".equals(version)' in client,
    "client requires SmartSky callback source": '"smartsky-callback".equals(candidate.source)' in client,
    "client keeps raw QR out of logs": "SBP_PROBE_QR_READY" in client and "rawPayloadLogged=false" in client,
    "UI has dedicated probe intent": "sbp_live_qr_generation_probe" in main,
    "UI requires real POS and locked contract": "!realPosEnabled" in main[main.find("private fun maybeRunSbpLiveQrGenerationProbe"):main.find("private fun maybeRunSbpDryRunSelfTest")],
    "UI never marks probe order paid": "runtimeOrderPaid=false fiscalCalled=false machineCalled=false" in main,
    "UI renders probe QR on JL22": "sbpLiveQrProbePayload" in main and "ЖИВОЙ QR • НЕ СКАНИРОВАТЬ" in main,
    "no automatic cancel/refund/retry command": "QR_CANCEL" not in client and "QR_REFUND" not in client,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.121 SBP QR source probe guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.121 SBP QR source probe guard: {len(checks)} checks passed")
