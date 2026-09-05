@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo SmartSkyPOS CONTROLLED TEST PAYMENT
echo ============================================================
echo This script DOES NOT call payment() automatically.
echo It only opens the diagnostic screen with payment mode enabled.
echo The screen still requires:
echo   READY(0) + TerminalData code=0 + verified Terminal ID/currency
echo and a MANUAL confirmation dialog.
echo.
echo Run SMARTSKYPOS_02_SAFE_PROBE.bat successfully first.
echo ============================================================
echo.

set /p "AMOUNT=Enter TEST amount exactly as it should be sent (example 1 or 1000): "
if not defined AMOUNT (
    echo [ERROR] Amount is required.
    pause
    exit /b 2
)

where adb >nul 2>nul
if errorlevel 1 (
    echo [ERROR] adb was not found in PATH.
    pause
    exit /b 3
)

adb wait-for-device
if errorlevel 1 (
    echo [ERROR] Device is not available over adb.
    pause
    exit /b 4
)

adb logcat -c
adb shell am force-stop com.coffeeonelove.iretail
adb shell am start -W -n com.coffeeonelove.iretail/.pos.SmartSkyPosDiagnosticActivity --ez allow_payment true --es amount "%AMOUNT%"
if errorlevel 1 (
    echo [ERROR] Could not start diagnostic payment mode.
    pause
    exit /b 5
)

echo.
echo The Activity is open on Kozen P12.
echo Verify the auto-filled Terminal ID and currency against TerminalData.
echo payment() will run ONLY after you press the button and confirm the dialog.
echo.
echo After the operation finishes, run SMARTSKYPOS_04_COLLECT_LOGS.bat.
pause
exit /b 0
