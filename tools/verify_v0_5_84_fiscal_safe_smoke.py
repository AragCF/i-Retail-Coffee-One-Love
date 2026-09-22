from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
smoke=(ROOT/"MAIN_24_FISCAL_SAFE_INSTALL_SMOKE.bat").read_text(encoding="utf-8")
pub=(ROOT/"GIT_124_PUBLISH_FISCAL_SAFE_SMOKE.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)
checks={
    "versionCode at least 84": bool(m) and int(m.group(1))>=84,
    "correct branch guard": "v0.5.84-fiscal-safe-install-smoke" in smoke and "v0.5.84-fiscal-safe-install-smoke" in pub,
    "JL22 signature": "product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno" in smoke,
    "real POS disabled": "--ez real_pos_enabled false" in smoke,
    "kiosk safe mode": "--es machine_mode kiosk" in smoke,
    "fiscal draft reset only": "rm -f files/fiscalization_dry_run.json" in smoke,
    "no Kozen adb target": "KOZEN" not in smoke,
    "no payment invocation": "PAYMENT_TX_ONCE" not in smoke.split("set \"FINANCIAL_MARKER")[0],
    "no cloud fiscal call": "curl" not in smoke.lower() and "kassa.i-bonus.me" not in smoke,
    "no order sync call": "order/synchronize" not in smoke,
    "safe outcome": "SAFE_OK_NO_PAYMENT_NO_FISCAL_SEND" in smoke,
    "restore stock app": "com.jinuo.mhwang.jetinnocoffe" in smoke,
    "auto publish only after safe outcome": smoke.find("SAFE_OK_NO_PAYMENT_NO_FISCAL_SEND") < smoke.find("GIT_124_PUBLISH_FISCAL_SAFE_SMOKE.bat"),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.84 safe smoke guard failed: "+", ".join(failed))
print(f"[OK] v0.5.84 safe smoke guard: {len(checks)} checks passed")
