@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "TID=12000679"
set "RECEIPT=2"

echo ============================================================
echo SmartSkyPOS READ-ONLY TRANSACTION LOOKUP
 echo ============================================================
echo TID:     %TID%
echo Receipt: %RECEIPT%
echo.
echo This script does NOT call payment(), cancel(), refund(), QR payment
 echo or any other financial operation. It only opens getTransaction().
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
adb shell am start -W -n com.coffeeonelove.iretail/.pos.SmartSkyPosTransactionLookupActivity --es terminal_id "%TID%" --es receipt_number "%RECEIPT%"
if errorlevel 1 (
    echo [ERROR] Could not start transaction lookup diagnostic.
    pause
    exit /b 4
)

echo.
echo Read the fields shown on Kozen P12, especially:
echo   code, rc, approved, message, amount, receipt, RRN, authCode.
echo.
echo IMPORTANT: code=0 only means the SmartSkyPOS call itself succeeded.
echo A financial payment is successful only when approved=true.
echo.
echo Then run SMARTSKYPOS_04_COLLECT_LOGS.bat and send the new ZIP/folder.
pause
exit /b 0
