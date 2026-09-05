@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo SmartSkyPOS SAFE PROBE
echo bind -^> StateCallback -^> getState() -^> getTerminalData()
echo payment() is DISABLED in this mode.
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

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "smartskypos_logs" mkdir "smartskypos_logs"
set "LOG=smartskypos_logs\safe_probe_%TS%.log"

echo [ADB] Clearing old logcat...
adb logcat -c

echo [ADB] Starting diagnostic Activity in SAFE mode...
adb shell am force-stop com.coffeeonelove.iretail
adb shell am start -W -n com.coffeeonelove.iretail/.pos.SmartSkyPosDiagnosticActivity --ez allow_payment false
if errorlevel 1 (
    echo [ERROR] Could not start SmartSkyPosDiagnosticActivity.
    pause
    exit /b 4
)

echo.
echo [WAIT] Collecting callback/state events for 10 seconds...
timeout /t 10 /nobreak >nul

echo [ADB] Saving filtered diagnostic log:
echo %CD%\%LOG%
adb logcat -d -v time SmartSkyPOSDiag:I *:S > "%LOG%"

echo.
type "%LOG%"
echo.
echo ============================================================
echo REQUIRED SAFE RESULT:
echo   BIND_OK
echo   CALLBACK_REGISTERED
echo   GET_STATE=0 (READY)
echo   TERMINAL_DATA code=0
echo   TERMINAL_DATA_OK
echo   PAYMENT_GATE=OPEN_FOR_EXPLICIT_DIAGNOSTIC_CALL
echo.
echo If state=2 / UNFINISHED_OPERATION appears, DO NOT run payment.
echo Send me this .log before moving the ordinary i-Retail card flow
echo to real SmartSkyPOS.
echo ============================================================
pause
exit /b 0
