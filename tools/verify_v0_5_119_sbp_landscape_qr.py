from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
contract = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpPaymentContract.kt").read_text(encoding="utf-8")
bridge = (ROOT / "kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")
runner = (ROOT / "MAIN_30_SBP_DRYRUN_UI_TEST.bat").read_text(encoding="utf-8")

version_code_match = re.search(r"versionCode\s+(\d+)", gradle)
version_name_match = re.search(r"versionName\s+'([^']+)'", gradle)
version_code = int(version_code_match.group(1)) if version_code_match else 0
version_name = version_name_match.group(1) if version_name_match else ""

render_start = main.find("private fun renderLandscapePaymentProgress")
render_end = main.find("private fun renderLandscapePaymentCompleted", render_start)
render_section = main[render_start:render_end]

hotspots_start = main.find("private fun landscapeHotspotsFor")
hotspots_end = main.find("private fun landscapeCatalogHotspots", hotspots_start)
hotspots_section = main[hotspots_start:hotspots_end]

checks = {
    "app version 0.5.119+": version_code >= 119 and bool(version_name),
    "landscape renderer section found": render_start >= 0 and render_end > render_start,
    "landscape hotspot section found": hotspots_start >= 0 and hotspots_end > hotspots_start,
    "landscape QR uses real renderer": "SbpQrRenderer.render(payload, 640)" in render_section,
    "landscape QR uses current DRY RUN payload": "val payload = sbp?.qrPayload.orEmpty()" in render_section,
    "landscape QR has explicit DRY RUN label": "СБП DRY RUN" in render_section and "Синтетический QR" in render_section,
    "landscape confirm view exists": "QR ОТСКАНИРОВАН" in render_section and "синтетического подтверждения" in render_section,
    "landscape QR tap marks waiting": "DRY_RUN_QR_SCANNED" in hotspots_section and "sbpDryRunSession.markWaiting()" in hotspots_section,
    "landscape confirm tap marks confirmed": "DRY_RUN_CONFIRMED" in hotspots_section and "sbpDryRunSession.confirmSynthetic()" in hotspots_section,
    "landscape QR no longer shares generic finishPayment": 'screenId == "PAYMENT_CASH" || screenId == "PAYMENT_ONLINE_QR"' not in hotspots_section,
    "landscape dry-run keeps cancellation": "DRY_RUN_CANCELLED" in hotspots_section,
    "Android 6 restore fix preserved": "generationCounter.compareAndSet" in (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpDryRun.kt").read_text(encoding="utf-8"),
    "live QR remains disabled": "LIVE_CALL_ENABLED = false" in contract and "LIVE_QR_PAYMENT_ENABLED = false" in bridge,
    "no live Binder QR transact": "binder.transact(TX_QR_PAYMENT" not in bridge,
    "runner targets current version": bool(version_name) and version_name in runner,
    "runner asks user to scan and tap QR": "Scan it with any QR scanner/camera" in runner and "Tap the large QR area once" in runner,
    "runner real POS false": "--ez real_pos_enabled true" not in runner,
    "runner sends no financial command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QR_PAYMENT|QRPAYMENT|REFUND|RECONCILIATION)\b", runner, re.I)),
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.119 landscape SBP QR guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.119 landscape SBP QR guard: {len(checks)} checks passed")
