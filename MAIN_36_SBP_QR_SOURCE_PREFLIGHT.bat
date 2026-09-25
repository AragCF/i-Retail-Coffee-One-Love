@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_VERSION=0.5.121-sbp-qr-source-probe"
set "EXPECTED_BRIDGE=0.5.7-sbp-qr-source-probe"
set "OUT_DIR=sbp_route_logs"
set "JL22="
set "KOZEN="

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - SBP QR SOURCE READ-ONLY PREFLIGHT
echo ============================================================
echo SAFETY:
echo   real POS remains FALSE
echo   normal qrPayment remains blocked
echo   controlled QR-generation probe remains DISABLED
echo   only PING / INFO / GET_STATE / GET_TERMINAL_DATA / GET_SBP_ROUTE are used
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found.
  pause
  exit /b 10
)

call "%~dp0tools\WAIT_FOR_JL22.bat" JL22
if errorlevel 1 exit /b 11
call "%~dp0tools\WAIT_FOR_KOZEN.bat" KOZEN
if errorlevel 1 exit /b 12

echo [JL22] %JL22%
echo [KOZEN] %KOZEN%

set "GRADLE_CMD="
if exist "gradlew.bat" set "GRADLE_CMD=%CD%\gradlew.bat"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD (
  echo [ERROR] Gradle was not found.
  pause
  exit /b 13
)

echo [1/7] Building Kozen Bridge 0.5.7...
call "%GRADLE_CMD%" --no-daemon --stacktrace :kozenBridge:assembleDebug
if errorlevel 1 exit /b 20

set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
if not exist "%KOZEN_APK%" exit /b 21

echo [2/7] Installing Kozen Bridge 0.5.7...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 exit /b 22
adb -s "%KOZEN%" shell dumpsys package com.coffeeonelove.iretail.kozenbridge > "%TEMP%\iretail_sbp_preflight_bridge.txt" 2>&1
findstr /C:"versionName=%EXPECTED_BRIDGE%" "%TEMP%\iretail_sbp_preflight_bridge.txt" >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Installed bridge version mismatch.
  findstr /I /C:"versionName=" "%TEMP%\iretail_sbp_preflight_bridge.txt"
  pause
  exit /b 23
)
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul

echo [3/7] Building i-Retail...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 exit /b 24
set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APP_APK%" exit /b 25

echo [4/7] Installing i-Retail on JL22...
call "%~dp0tools\WAIT_FOR_JL22.bat" JL22
if errorlevel 1 exit /b 11
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 26

echo [5/7] Starting read-only SBP route audit...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
timeout /t 1 /nobreak >nul
adb -s "%JL22%" logcat -c
adb -s "%KOZEN%" logcat -c
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_route_readonly_audit true >nul
if errorlevel 1 exit /b 27

set "WAIT_LOG=%TEMP%\iretail_sbp_qr_source_preflight_wait.log"
set "OUTCOME=ROUTE_TIMEOUT"
for /l %%S in (1,1,120) do (
  adb -s "%JL22%" logcat -d -v brief SbpRouteAudit:V IretailKozenClient:V AndroidRuntime:E *:S > "%WAIT_LOG%" 2>&1
  findstr /C:"ROUTE_RESULT ok=true" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    findstr /C:"available=true" "%WAIT_LOG%" >nul 2>nul
    if errorlevel 1 goto FAIL_ROUTE_NOT_AVAILABLE
    findstr /C:"operationType=42" "%WAIT_LOG%" >nul 2>nul
    if errorlevel 1 goto FAIL_BAD_OPERATION_TYPE
    findstr /C:"transactionType=qrPayment" "%WAIT_LOG%" >nul 2>nul
    if errorlevel 1 goto FAIL_BAD_TRANSACTION_TYPE
    findstr /C:"currency=643" "%WAIT_LOG%" >nul 2>nul
    if errorlevel 1 goto FAIL_BAD_CURRENCY
    findstr /C:"tidPresent=true" "%WAIT_LOG%" >nul 2>nul
    if errorlevel 1 goto FAIL_TID_MISSING
    findstr /C:"liveEnabled=false" "%WAIT_LOG%" >nul 2>nul
    if errorlevel 1 goto FAIL_NORMAL_LIVE_NOT_LOCKED
    findstr /C:"probeEnabled=false" "%WAIT_LOG%" >nul 2>nul
    if errorlevel 1 goto FAIL_PROBE_NOT_LOCKED
    set "OUTCOME=PREFLIGHT_OK"
    goto PREFLIGHT_DONE
  )
  findstr /C:"ROUTE_RESULT ok=false" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=ROUTE_FAILED"
    goto PREFLIGHT_DONE
  )
  timeout /t 1 /nobreak >nul
)


:FAIL_ROUTE_NOT_AVAILABLE
set "OUTCOME=ROUTE_NOT_AVAILABLE"
goto PREFLIGHT_DONE

:FAIL_BAD_OPERATION_TYPE
set "OUTCOME=BAD_OPERATION_TYPE"
goto PREFLIGHT_DONE

:FAIL_BAD_TRANSACTION_TYPE
set "OUTCOME=BAD_TRANSACTION_TYPE"
goto PREFLIGHT_DONE

:FAIL_BAD_CURRENCY
set "OUTCOME=BAD_CURRENCY"
goto PREFLIGHT_DONE

:FAIL_TID_MISSING
set "OUTCOME=TID_MISSING"
goto PREFLIGHT_DONE

:FAIL_NORMAL_LIVE_NOT_LOCKED
set "OUTCOME=NORMAL_LIVE_NOT_LOCKED"
goto PREFLIGHT_DONE

:FAIL_PROBE_NOT_LOCKED
set "OUTCOME=PROBE_NOT_LOCKED"
goto PREFLIGHT_DONE

:PREFLIGHT_DONE
echo [6/7] Restoring safe Standalone...
call "%~dp0tools\WAIT_FOR_JL22.bat" JL22
if errorlevel 1 exit /b 11
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false >nul 2>nul

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
set "REPORT=%OUT_DIR%\SBP_QR_SOURCE_PREFLIGHT_%TS%.log"

echo [7/7] Collecting evidence...
> "%REPORT%" echo version=%EXPECTED_VERSION%
>>"%REPORT%" echo bridge=%EXPECTED_BRIDGE%
>>"%REPORT%" echo outcome=%OUTCOME%
>>"%REPORT%" echo safety=READ_ONLY_NO_FINANCIAL_COMMANDS
>>"%REPORT%" echo real_pos=false
>>"%REPORT%" echo expected_route=42/qrPayment/643
>>"%REPORT%" echo normal_live_enabled=false
>>"%REPORT%" echo generation_probe_enabled=false
>>"%REPORT%" echo.
adb -s "%JL22%" logcat -d -v threadtime SbpRouteAudit:V IretailKozenClient:V IretailMachineMode:I AndroidRuntime:E *:S >> "%REPORT%" 2>&1
>>"%REPORT%" echo.
>>"%REPORT%" echo ===== KOZEN BRIDGE =====
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:V AndroidRuntime:E *:S >> "%REPORT%" 2>&1

echo.
echo ============================================================
echo SBP QR SOURCE READ-ONLY PREFLIGHT COMPLETE
echo Outcome: %OUTCOME%
echo Report: %CD%\%REPORT%
echo No financial command was sent.
echo ============================================================
pause

if /I "%OUTCOME%"=="PREFLIGHT_OK" exit /b 0
exit /b 2
