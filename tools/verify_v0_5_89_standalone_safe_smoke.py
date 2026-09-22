from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
smoke=(ROOT/"MAIN_24_FISCAL_SAFE_INSTALL_SMOKE.bat").read_text(encoding="utf-8")
pub=(ROOT/"GIT_124_PUBLISH_FISCAL_SAFE_SMOKE.bat").read_text(encoding="utf-8")
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")

m=re.search(r"versionCode\s+(\d+)",gradle)
non_echo="\n".join(line for line in smoke.splitlines() if not line.lstrip().lower().startswith("echo "))

checks={
    "versionCode at least 89": bool(m) and int(m.group(1))>=89,
    "branch guard": "v0.5.89-standalone-safe-smoke" in smoke and "v0.5.89-standalone-safe-smoke" in pub,
    "expected version current": 'EXPECTED_VERSION=0.5.89-standalone-safe-smoke' in smoke,
    "JL22 simple selection retained": 'adb devices -l ^| findstr' in smoke and 'if /I "%%B"=="device"' in smoke,
    "standalone persisted": "--es machine_mode standalone" in smoke and "--ez persist_machine_mode true" in smoke,
    "safe POS disabled": "--ez real_pos_enabled false" in smoke,
    "configure-only used": "--ez configure_only true" in smoke,
    "mode evidence collected": "iretail_machine_mode_v1.xml" in smoke and "06_machine_mode.txt" in smoke,
    "standalone mode checked": '>standalone<' in smoke and 'real_pos_enabled' in smoke,
    "Jetinno not foregrounded": "com.jinuo.mhwang.jetinnocoffe" not in smoke,
    "i-Retail not force-stopped at end": 'Restoring stock Jetinno UI' not in smoke,
    "no cloud fiscal network command": "curl " not in non_echo.lower() and "https://kassa.i-bonus.me" not in non_echo,
    "no order sync invocation": "order/synchronize" not in non_echo,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+k)
if failed: raise SystemExit("v0.5.89 guard failed: "+", ".join(failed))
print(f"[OK] v0.5.89 guard: {len(checks)} checks passed")
