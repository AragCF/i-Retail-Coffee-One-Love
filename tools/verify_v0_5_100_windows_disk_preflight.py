from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
build = (ROOT / "BUILD_WINDOWS_CLI.bat").read_text(encoding="utf-8")
main26 = (ROOT / "MAIN_26_FISCAL_POSITIVE_PAYMENT_1RUB_TEST.bat").read_text(encoding="utf-8")
pub = (ROOT / "GIT_126_PUBLISH_FISCAL_POSITIVE_PAYMENT_1RUB.bat").read_text(encoding="utf-8")

checks = {
    "versionCode 100+": bool(re.search(r"versionCode\s+(100|[1-9]\d{3,})", gradle)),
    "versionName v0.5.100": "versionName '0.5.100-windows-disk-preflight'" in gradle,
    "Windows build version synced": 'SCRIPT_VERSION=0.5.100-windows-disk-preflight' in build,
    "build cache disabled for app build": '--no-build-cache --stacktrace :app:assembleDebug' in build,
    "build cache disabled for app clean": '--no-build-cache --stacktrace :app:clean' in build,
    "disk cleanup threshold": 'DISK_CLEANUP_THRESHOLD_MB=2048' in build,
    "disk minimum": 'DISK_MINIMUM_MB=1024' in build,
    "free-space reader": ':ReadFreeSpace' in build and 'Get-PSDrive' in build,
    "project-only cleanup": ':LowDiskProjectCleanup' in build and 'for /d %%D in (*)' in build,
    "project .gradle cleanup": 'if exist ".gradle" rmdir /S /Q ".gradle"' in build,
    "global Gradle cache untouched": '%USERPROFILE%\\.gradle' not in build and 'GRADLE_USER_HOME' not in build,
    "delayed expansion remains disabled": 'DisableDelayedExpansion' in build,
    "controlled payment version synced": '0.5.100-windows-disk-preflight' in main26,
    "Kozen bridge build cache disabled": '--no-build-cache --stacktrace :kozenBridge:assembleDebug' in main26,
    "financial protections retained": 'EXACTLY ONE PAYMENT ATTEMPT IS ALLOWED' in main26 and 'windows_sends_payment=false' in main26,
    "publisher branch synced": 'v0.5.100-windows-disk-preflight' in pub,
}

failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("v0.5.100 Windows disk preflight guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.100 Windows disk preflight guard: {len(checks)} checks passed")
