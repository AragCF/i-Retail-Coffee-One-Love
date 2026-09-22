from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
smoke=(ROOT/"MAIN_24_FISCAL_SAFE_INSTALL_SMOKE.bat").read_text(encoding="utf-8")
pub=(ROOT/"GIT_124_PUBLISH_FISCAL_SAFE_SMOKE.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)
non_echo="\n".join(line for line in smoke.splitlines() if not line.lstrip().lower().startswith("echo "))

checks={
    "versionCode at least 87": bool(m) and int(m.group(1))>=87,
    "branch guard": "v0.5.87-jl22-any-live-interface" in smoke and "v0.5.87-jl22-any-live-interface" in pub,
    "expected version current": 'EXPECTED_VERSION=0.5.87-jl22-any-live-interface' in smoke,
    "JL22 signature exact": "product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno" in smoke,
    "only live adb rows": "-match '^\\S+\\s+device\\s+'" in smoke,
    "first live match accepted": "$m.Count -gt 0" in smoke and "$m[0]" in smoke,
    "model accepts space or underscore": 'MODEL_NORM=%MODEL:_=%' in smoke and 'MODEL_NORM=%MODEL_NORM: =%' in smoke and 'UniWinM190' in smoke,
    "device identity checked": 'octopus-jetinno' in smoke,
    "real POS disabled": "--ez real_pos_enabled false" in smoke,
    "no cloud fiscal network command": "curl " not in non_echo.lower() and "https://kassa.i-bonus.me" not in non_echo,
    "no order sync invocation": "order/synchronize" not in non_echo,
    "restore stock app": "com.jinuo.mhwang.jetinnocoffe" in smoke,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.87 guard failed: "+", ".join(failed))
print(f"[OK] v0.5.87 guard: {len(checks)} checks passed")
