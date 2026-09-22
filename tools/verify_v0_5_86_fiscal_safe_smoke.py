from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
smoke=(ROOT/"MAIN_24_FISCAL_SAFE_INSTALL_SMOKE.bat").read_text(encoding="utf-8")
pub=(ROOT/"GIT_124_PUBLISH_FISCAL_SAFE_SMOKE.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)
non_echo="\n".join(line for line in smoke.splitlines() if not line.lstrip().lower().startswith("echo "))

checks={
    "versionCode at least 86": bool(m) and int(m.group(1))>=86,
    "branch guard": "v0.5.86-jl22-live-adb-autoselect" in smoke and "v0.5.86-jl22-live-adb-autoselect" in pub,
    "expected version current": 'EXPECTED_VERSION=0.5.86-jl22-live-adb-autoselect' in smoke,
    "JL22 signature": "product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno" in smoke,
    "live state filter": "$live=@($m" in smoke and "device\\s+" in smoke,
    "real POS disabled": "--ez real_pos_enabled false" in smoke,
    "no cloud fiscal network command": "curl " not in non_echo.lower() and "https://kassa.i-bonus.me" not in non_echo,
    "no order sync invocation": "order/synchronize" not in non_echo,
    "restore stock app": "com.jinuo.mhwang.jetinnocoffe" in smoke,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.86 guard failed: "+", ".join(failed))
print(f"[OK] v0.5.86 guard: {len(checks)} checks passed")
