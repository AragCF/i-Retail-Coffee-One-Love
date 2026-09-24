from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
build = (ROOT / "BUILD_WINDOWS_CLI.bat").read_text(encoding="utf-8")
main26 = (ROOT / "MAIN_26_FISCAL_POSITIVE_PAYMENT_1RUB_TEST.bat").read_text(encoding="utf-8")
pub = (ROOT / "GIT_126_PUBLISH_FISCAL_POSITIVE_PAYMENT_1RUB.bat").read_text(encoding="utf-8")

checks = {
    "versionCode 101+": bool(re.search(r"versionCode\s+(101|10[2-9]|1[1-9]\d|[2-9]\d{2,})", gradle)),
    "versionName present": bool(re.search(r"versionName\s+'[^']+'", gradle)),
    "Windows build version present": 'SCRIPT_VERSION=0.5.' in build,
    "cleanup threshold 2GB": 'DISK_CLEANUP_THRESHOLD_MB=2048' in build,
    "cleanup only below threshold": 'if %FREE_MB% LSS %DISK_CLEANUP_THRESHOLD_MB%' in build,
    "normal cache above threshold": 'At least 2 GB is free. No cache cleanup; Gradle cache remains enabled.' in build,
    "no-build-cache only low disk": 'set "GRADLE_CACHE_ARG=--no-build-cache"' in build and '%GRADLE_CACHE_ARG% --stacktrace :app:assembleDebug' in build,
    "project caches cleaned": 'if exist ".gradle" rmdir /S /Q ".gradle"' in build and 'if exist "%%D\\build" rmdir /S /Q' in build,
    "Gradle transient caches cleaned": 'build-cache-*' in build and 'transforms-*' in build and 'jars-*' in build,
    "Gradle dependency cache fallback": 'caches\\modules-2' in build,
    "Kotlin caches cleaned": '.kotlin\\daemon' in build and '%LOCALAPPDATA%\\kotlin\\daemon' in build,
    "Android cache cleaned": '.android\\cache' in build,
    "temp development caches cleaned": '%TEMP%\\gradle*' in build and '%TEMP%\\kotlin*' in build and '%TEMP%\\android*' in build,
    "SDK packages untouched": 'Android SDK packages were not touched' in build,
    "DelayedExpansion disabled": 'DisableDelayedExpansion' in build,
    "controlled runner version guard exists": 'EXPECTED_VERSION' in main26 and 'Wrong project version' in main26,
    "Kozen APK defined before IF": main26.find('set "KOZEN_APK=') < main26.find('echo [2/10] Preparing Kozen bridge'),
    "Kozen APK not assigned inside build block": '  set "KOZEN_APK=kozenBridge' not in main26,
    "step 3 remains after step 2": main26.find('echo [3/10] Installing i-Retail APK on JL22...') > main26.find('echo [2/10] Preparing Kozen bridge...'),
    "Kozen cache conditional": 'set "KOZEN_CACHE_ARG="' in main26 and 'if %FREE_MB% LSS 2048 set "KOZEN_CACHE_ARG=--no-build-cache"' in main26,
    "financial protections retained": 'EXACTLY ONE PAYMENT ATTEMPT IS ALLOWED' in main26 and 'windows_sends_payment=false' in main26,
    "publisher branch guard exists": 'Wrong branch for controlled payment evidence' in pub,
}

failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("[OK] " if v else "[FAIL] ") + k)
if failed:
    raise SystemExit("v0.5.101 script/cache guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.101 script/cache guard: {len(checks)} checks passed")
