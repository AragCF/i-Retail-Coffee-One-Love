from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
contract_code = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/SbpPaymentContract.kt").read_text(encoding="utf-8")
contract_v1 = (ROOT / "docs/SBP_DUAL_MODE_CONTRACT_v1.0.0.md").read_text(encoding="utf-8")
contract_v2 = (ROOT / "docs/SBP_DUAL_MODE_CONTRACT_v2.0.0.md").read_text(encoding="utf-8")
evidence = (ROOT / "docs/SBP_DIRECT_SERVER_EVIDENCE_v0.5.122.md").read_text(encoding="utf-8")
tso = (ROOT / "docs/TSO_REFERENCE_NOTES_v0.4.md").read_text(encoding="utf-8")
pay_methods = (ROOT / "app/src/main/assets/content/pay-methods.xml").read_text(encoding="utf-8")
audit = (ROOT / "tools/iRetailDirectSbpReadonlyAudit.ps1").read_text(encoding="utf-8")
runner = (ROOT / "MAIN_37_SBP_DIRECT_SERVER_READONLY_AUDIT.bat").read_text(encoding="utf-8")

version_code_match = re.search(r"versionCode\s+(\d+)", gradle)
version_name_match = re.search(r"versionName\s+'([^']+)'", gradle)
version_code = int(version_code_match.group(1)) if version_code_match else 0
version_name = version_name_match.group(1) if version_name_match else ""

checks = {
    "app version 0.5.122+": version_code >= 122 and bool(version_name),
    "old dual-mode contract is explicitly superseded": contract_v1.startswith("# УСТАРЕЛ") and "SBP_DUAL_MODE_CONTRACT_v2.0.0.md" in contract_v1,
    "v2 requires two independent contours": "SBP_KOZEN" in contract_v2 and "SBP_DIRECT_JL22" in contract_v2 and "Kozen может быть" in contract_v2,
    "direct source is explicit in code contract": "enum class SbpPaymentSource" in contract_code and "KOZEN_SMARTSKY" in contract_code and "DIRECT_SERVER" in contract_code,
    "presentation remains orthogonal": "enum class SbpPresentationMode" in contract_code and "KOZEN_TERMINAL" in contract_code and "JL22_SCREEN_QR" in contract_code,
    "TSO evidence has server online-payment routes": "iretail/channel/get-available-services-in" in tso and "iretail/order/create-payment-for-order" in tso,
    "legacy pay methods has enabled payin_payout RUB": 'slug="payin_payout" enabled="true"' in pay_methods and "<currency>RUB</currency>" in pay_methods,
    "evidence records current SBP service slugs": all(x in evidence for x in ["sbp", "sbp_low_risk", "payin_payout"]),
    "audit downloads order/payment/channel/service docs": all(x in audit for x in [
        "app-controllers-iretail-ordercontroller.html",
        "app-controllers-iretail-paymentincontroller.html",
        "app-controllers-iretail-channelcontroller.html",
        "app-controllers-serviceincontroller.html",
    ]),
    "audit reads only service/channel metadata": all(x in audit for x in [
        'Invoke-ReadOnlyApi "10_service_in_list" "service-in/get-service-in-list"',
        'Invoke-ReadOnlyApi "11_service_in_profile" "service-in/get-service-in"',
        'Invoke-ReadOnlyApi "12_service_in_used" "service-in/get-used"',
        'Invoke-ReadOnlyApi "13_service_in_types" "service-in/get-service-in-types"',
        'Invoke-ReadOnlyApi "14_channel" "iretail/channel/get"',
    ]),
    "audit does not execute payment create": 'Invoke-ReadOnlyApi "iretail/order/create-payment-for-order"' not in audit and 'Invoke-ReadOnlyApi "iretail/payment-in/create"' not in audit,
    "audit has no Android bridge transport": "adb " not in audit.lower() and "kozenaoapaymentclient" not in audit.lower() and "com.skytech" not in audit.lower(),
    "runner has no ADB": "adb " not in runner.lower(),
    "runner explicitly requires no Kozen": "Kozen is NOT required" in runner and "SmartSkyPOS is NOT used" in runner and "USB/AOA is NOT used" in runner,
    "runner only invokes direct server audit": "iRetailDirectSbpReadonlyAudit.ps1" in runner and "MAIN_36" not in runner,
    "runner requires correct branch": "v0.5.122-sbp-direct-server-audit" in runner,
    "no financial mutation is enabled": "No order/payment/payment-in is created" in runner and "Financial mutation: NO" in runner,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.122 direct server SBP audit guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.122 direct server SBP audit guard: {len(checks)} checks passed")
