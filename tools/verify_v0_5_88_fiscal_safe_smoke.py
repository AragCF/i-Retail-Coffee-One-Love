from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
smoke=(ROOT/"MAIN_24_FISCAL_SAFE_INSTALL_SMOKE.bat").read_text(encoding="utf-8")
pub=(ROOT/"GIT_124_PUBLISH_FISCAL_SAFE_SMOKE.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)
non_echo="\n".join(line for line in smoke.splitlines() if not line.lstrip().lower().startswith("echo "))

checks={
    "versionCode at least 88": bool(m) and int(m.group(1))>=88,
    "branch guard": "v0.5.88-jl22-simple-cmd-autoselect" in smoke and "v0.5.88-jl22-simple-cmd-autoselect" in pub,
    "expected version current": 'EXPECTED_VERSION=0.5.88-jl22-simple-cmd-autoselect' in smoke,
    "JL22 signature exact": "product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno" in smoke,
    "plain cmd selection": 'for /f "tokens=1,2,*" %%A in (\'adb devices -l ^| findstr' in smoke,
    "live state token checked": 'if /I "%%B"=="device"' in smoke,
    "first match accepted": 'if not defined JL22 set "JL22=%%A"' in smoke,
    "no powershell selection": "Select-String" not in smoke and "Where-Object" not in smoke,
    "model normalization": 'MODEL_NORM=%MODEL:_=%' in smoke and 'MODEL_NORM=%MODEL_NORM: =%' in smoke and 'UniWinM190' in smoke,
    "real POS disabled": "--ez real_pos_enabled false" in smoke,
    "no cloud fiscal network command": "curl " not in non_echo.lower() and "https://kassa.i-bonus.me" not in non_echo,
    "no order sync invocation": "order/synchronize" not in non_echo,
    "restore stock app": "com.jinuo.mhwang.jetinnocoffe" in smoke,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.88 guard failed: "+", ".join(failed))
print(f"[OK] v0.5.88 guard: {len(checks)} checks passed")
