@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo SmartSkyPOS CONTROLLED TEST PAYMENT v0.5.9
echo ============================================================
echo This script DOES NOT call payment() automatically.
echo It opens the diagnostic screen with payment mode enabled.
echo On Kozen P12 select one of the fixed amounts: 1 / 10 / 100 RUB.
echo Then press the explicit payment button and confirm the dialog.
echo.
echo Required before payment:
echo   READY(0) + TerminalData code=0 + advertised payment route
echo ============================================================
echo.

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
adb shell am start -W -n com.coffeeonelove.iretail/.pos.SmartSkyPosDiagnosticActivity --ez allow_payment true
if errorlevel 1 (
    echo [ERROR] Could not start diagnostic payment mode.
    pause
    exit /b 5
)

echo.
echo The Activity is open on Kozen P12.
echo No keyboard input is required in v0.5.9.
echo Select 1 / 10 / 100 RUB on screen, then press the payment button once.
echo After the operation finishes, run SMARTSKYPOS_04_COLLECT_LOGS.bat.
pause
exit /b 0
