from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
smoke=(ROOT/"MAIN_24_FISCAL_SAFE_INSTALL_SMOKE.bat").read_text(encoding="utf-8")
pub=(ROOT/"GIT_124_PUBLISH_FISCAL_SAFE_SMOKE.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)
non_echo="\n".join(
    line for line in smoke.splitlines()
    if not line.lstrip().lower().startswith("echo ")
)

checks={
    "versionCode at least 85": bool(m) and int(m.group(1))>=85,
    "correct branch guard": "v0.5.85-fiscal-safe-smoke-guard-fix" in smoke and "v0.5.85-fiscal-safe-smoke-guard-fix" in pub,
    "JL22 signature": "product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno" in smoke,
    "real POS disabled": "--ez real_pos_enabled false" in smoke,
    "kiosk safe mode": "--es machine_mode kiosk" in smoke,
    "fiscal draft reset only": "rm -f files/fiscalization_dry_run.json" in smoke,
    "no Kozen adb target": "adb -s \"%KOZEN%\" " not in smoke,
    "no payment command path": all(x not in non_echo for x in [
        "MAIN_22_REAL_UI_PAYMENT_TEST.bat",
        "AOA_14_PAYMENT_1_RUB_TEST.bat",
        "SMARTSKYPOS_03_CONTROLLED_PAYMENT.bat",
    ]),
    "no cloud fiscal network command": "curl " not in non_echo.lower() and "https://kassa.i-bonus.me" not in non_echo,
    "no order sync invocation": "order/synchronize" not in non_echo,
    "safe outcome": "SAFE_OK_NO_PAYMENT_NO_FISCAL_SEND" in smoke,
    "restore stock app": "com.jinuo.mhwang.jetinnocoffe" in smoke,
    "auto publish only after safe outcome": smoke.rfind("SAFE_OK_NO_PAYMENT_NO_FISCAL_SEND") < smoke.find("GIT_124_PUBLISH_FISCAL_SAFE_SMOKE.bat"),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.85 safe smoke guard failed: "+", ".join(failed))
print(f"[OK] v0.5.85 safe smoke guard: {len(checks)} checks passed")
