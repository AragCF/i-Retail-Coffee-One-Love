from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
contract = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpPaymentContract.kt").read_text(encoding="utf-8")
renderer = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpQrRenderer.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
bridge = (ROOT / "kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")
bridge_ui = (ROOT / "kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/BridgeActivity.java").read_text(encoding="utf-8")
upgrade = (ROOT / "MAIN_35_KOZEN_BRIDGE_UPGRADE_AND_SBP_QUEUE_TEST.bat").read_text(encoding="utf-8")
dual_contract = (ROOT / "docs/SBP_DUAL_MODE_CONTRACT_v1.0.0.md").read_text(encoding="utf-8")
runner = (ROOT / "MAIN_34_SBP_EVENT_QUEUE_SYNTHETIC_TEST.bat").read_text(encoding="utf-8")
qr_runner = (ROOT / "MAIN_30_SBP_DRYRUN_UI_TEST.bat").read_text(encoding="utf-8")

checks = {
    "app version 0.5.116+": (("versionCode 116" in gradle and "versionName '0.5.116-sbp-dual-mode-bridge-upgrade'" in gradle) or ("versionCode 117" in gradle and "versionName '0.5.117-jl22-wait-loop'" in gradle)),
    "ZXing core pinned": "com.google.zxing:core:3.5.4" in gradle,
    "both mandatory modes in code": "KOZEN_TERMINAL" in contract and "JL22_SCREEN_QR" in contract,
    "live QR remains disabled": "LIVE_CALL_ENABLED = false" in contract and "LIVE_QR_PAYMENT_ENABLED = false" in bridge,
    "no Binder qrPayment transact": "binder.transact(TX_QR_PAYMENT" not in bridge,
    "local QR renderer": "QRCodeWriter" in renderer and "BarcodeFormat.QR_CODE" in renderer and "Bitmap.createBitmap" in renderer,
    "renderer is network-independent": "HttpURLConnection" not in renderer and "URL(" not in renderer,
    "JL22 screen renders current SBP payload": "SbpQrRenderer.render(payload, 640)" in main and "val payload = sbp?.qrPayload.orEmpty()" in main,
    "screen still labels DRY RUN": "DRY RUN: реальный qrPayment не вызывался" in main,
    "bridge UI version truthful": "Kozen Payment Bridge 0.5.6" in bridge_ui,
    "upgrade installs bridge": 'install -r "%KOZEN_APK%"' in upgrade,
    "upgrade verifies installed version": "versionName=%EXPECTED_BRIDGE_VERSION%" in upgrade,
    "upgrade restores Kozen to JL22 step": "Return Kozen to JL22" in upgrade,
    "upgrade calls safe queue test": "MAIN_34_SBP_EVENT_QUEUE_SYNTHETIC_TEST.bat" in upgrade,
    "upgrade does not enable real POS": "--ez real_pos_enabled true" not in upgrade,
    "upgrade does not send financial adb command": not bool(re.search(r"adb[^\n\r]*\b(?:QR_PAYMENT|PAYMENT|REFUND|RECONCILIATION)\b", upgrade, re.I)),
    "dual-mode contract approved": "APPROVED_BY_USER" in dual_contract,
    "dual-mode contract requires both": "KOZEN_TERMINAL" in dual_contract and "JL22_SCREEN_QR" in dual_contract and "Наличие одного режима не считается заменой второго." in dual_contract,
    "screen QR uses callback payload contract": "onQrReading(qrId, payload)" in dual_contract,
    "event runner targets current version": ("0.5.116-sbp-dual-mode-bridge-upgrade" in runner or "0.5.117-jl22-wait-loop" in runner),
    "QR screen runner targets current version": ("0.5.116-sbp-dual-mode-bridge-upgrade" in qr_runner or "0.5.117-jl22-wait-loop" in qr_runner),
    "QR screen runner asks for actual scan": "Scan it with any QR scanner/camera" in qr_runner and "SBP-DRY-RUN" in qr_runner,
    "upgrade chains QR screen test": "MAIN_30_SBP_DRYRUN_UI_TEST.bat" in upgrade and "JL22_SCREEN_QR_DRYRUN_OK" in upgrade,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.116 dual-mode SBP guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.116 dual-mode SBP guard: {len(checks)} checks passed")
