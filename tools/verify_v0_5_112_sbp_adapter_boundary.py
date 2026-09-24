from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
models=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/Models.kt").read_text(encoding="utf-8")
sbp=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpDryRun.kt").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
bridge=(ROOT/"kozenBridge/src/main/java/com/coffeeonelove/iretail/kozenbridge/ProductionBridgeService.java").read_text(encoding="utf-8")

checks={
    "versionCode 112+": bool(re.search(r"versionCode\s+(112|11[3-9]|1[2-9]\d|[2-9]\d{2,})",gradle)),
    "versionName v0.5.112": "versionName '0.5.112-sbp-adapter-boundary'" in gradle,
    "explicit SBP payment method": re.search(r"enum class PaymentMethod\s*\{[^}]*\bSBP\b",models,re.S) is not None,
    "generic SBP state machine": "enum class SbpPaymentState" in sbp,
    "adapter interface exists": "interface SbpPaymentAdapter" in sbp,
    "adapter exposes live flag": "val liveFinancialEnabled: Boolean" in sbp,
    "dry-run adapter implements boundary": "class DryRunSbpPaymentAdapter : SbpPaymentAdapter" in sbp,
    "dry-run live financial disabled": 'override val liveFinancialEnabled: Boolean = false' in sbp,
    "dry-run never sets real payment true": "realPaymentSent = true" not in sbp,
    "dry-run has no SmartSkyPOS dependency": "import com.skytech" not in sbp and "KozenAoaPaymentClient" not in sbp and ".qrPayment(" not in sbp,
    "main depends on interface": "private val sbpPaymentAdapter: SbpPaymentAdapter = DryRunSbpPaymentAdapter()" in main,
    "main no concrete session field": "private val sbpDryRunSession" not in main,
    "main renders SBP title": 'PaymentMethod.SBP -> "СБП / QR"' in main,
    "normal non-card flow still blocked": 'if (method != PaymentMethod.CARD)' in main,
    "dry-run logs adapter": "liveFinancialEnabled=" in main and "adapter=" in main,
    "existing route boundary remains read-only": 'findRoute(data, "42", "qrPayment"' in bridge and ".qrPayment(" not in bridge,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.112 SBP adapter guard failed: "+", ".join(failed))
print(f"[OK] v0.5.112 SBP adapter guard: {len(checks)} checks passed")
