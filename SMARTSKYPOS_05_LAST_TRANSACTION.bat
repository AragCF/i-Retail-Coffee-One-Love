@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo SmartSkyPOS READ-ONLY LAST TRANSACTION CHECK
echo ============================================================
echo This script does NOT call payment(), cancel(), refund() or any
 echo other financial operation. It only opens getLastTransaction().
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 (
    echo [ERROR] adb was not found in PATH.
    pause
    exit /b 2
)

adb wait-for-device
if errorlevel 1 (
    echo [ERROR] Device is not available over adb.
    pause
    exit /b 3
)

adb logcat -c
adb shell am start -W -n com.coffeeonelove.iretail/.pos.SmartSkyPosLastTransactionActivity
if errorlevel 1 (
    echo [ERROR] Could not start last transaction diagnostic.
    pause
    exit /b 4
)

echo.
echo Read the fields shown on Kozen P12, especially:
echo   code, rc, approved, message, amount, receipt, RRN, authCode.
echo.
echo Then run SMARTSKYPOS_04_COLLECT_LOGS.bat.
pause
exit /b 0
