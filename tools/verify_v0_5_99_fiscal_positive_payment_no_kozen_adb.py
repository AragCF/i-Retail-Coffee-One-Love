from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
client = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
bat = (ROOT / "MAIN_26_FISCAL_POSITIVE_PAYMENT_1RUB_TEST.bat").read_text(encoding="utf-8")
pub = (ROOT / "GIT_126_PUBLISH_FISCAL_POSITIVE_PAYMENT_1RUB.bat").read_text(encoding="utf-8")

start = client.find("public void preflight(PreflightListener listener)")
end = client.find("public void startPayment", start)
preflight = client[start:end] if start >= 0 and end > start else ""

checks = {
    "versionCode 99+": bool(re.search(r"versionCode\s+(99|[1-9]\d{2,})", gradle)),
    "versionName v0.5.99": "versionName '0.5.99-fiscal-positive-payment-no-kozen-adb'" in gradle,
    "preflight listener exists": "public interface PreflightListener" in client,
    "preflight sends no PAYMENT": bool(preflight) and '"PAYMENT "' not in preflight and "PAYMENT_TX_ONCE" not in preflight,
    "preflight commands": all(x in preflight for x in ["GET_STATE ", "GET_TERMINAL_DATA ", "verifyBridge()"]),
    "bridge 0.5.2 required": '!"0.5.2".equals(value(info, "bridge"))' in client,
    "preflight keeps link": "linkKeptOpen=true" in client,
    "main gates on preflight": "fiscalPositivePaymentPreflightReady" in main and "TEST_PREFLIGHT_START" in main,
    "ready marker": "bridgeReady=true noPaymentSent=true" in main,
    "preflight failure no payment": "TEST_PREFLIGHT_FAILED" in main and "Финансовая попытка не начиналась" in main,
    "Kozen Windows ADB optional": "[KOZEN ADB] not available - this is allowed." in bat,
    "no mandatory Kozen ADB error": "Kozen P12 ADB target not found" not in bat,
    "Windows waits for in-app ready": "bridgeReady=true noPaymentSent=true" in bat,
    "failed preflight preserves attempt": "Authorized financial attempt remains UNUSED" in bat,
    "optional Kozen log collection": "KOZEN_ADB_NOT_AVAILABLE" in bat,
    "Windows never sends PAYMENT": not bool(re.search(r"adb[^\n\r]*\bPAYMENT\b", bat, re.I)),
    "real POS not persisted true": "--ez persist_machine_mode true --ez real_pos_enabled true" not in bat,
    "real POS persisted false": bat.count("--ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true") >= 2,
    "publisher current branch": "v0.5.99-fiscal-positive-payment-no-kozen-adb" in pub,
    "one-ruble protections retained": "fiscal_positive_payment_test_v1_0_1.attempt" in main and "amountMinor=100" in main,
}

failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("v0.5.99 no-Kozen-ADB guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.99 no-Kozen-ADB guard: {len(checks)} checks passed")
