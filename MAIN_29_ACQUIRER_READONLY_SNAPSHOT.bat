@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_VERSION="
for /f "tokens=2" %%V in ('findstr /C:"versionName " "app\build.gradle"') do if not defined EXPECTED_VERSION set "EXPECTED_VERSION=%%V"
set "EXPECTED_VERSION=%EXPECTED_VERSION:'=%"
if /I not "%EXPECTED_VERSION%"=="0.5.108-acquirer-readonly-diagnostics" (
  echo [ERROR] Wrong project version: %EXPECTED_VERSION%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - ACQUIRER READ-ONLY SNAPSHOT
echo ============================================================
echo SAFETY:
echo   real POS remains FALSE
echo   no PAYMENT / CANCEL / REFUND / reconciliation is sent
echo   only PING, INFO, GET_STATE and GET_TERMINAL_DATA are allowed
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found in PATH.
  pause
  exit /b 12
)

set "JL22="
for /f "tokens=1,2,*" %%A in ('adb devices -l ^| findstr /I /C:"product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno"') do (
  if /I "%%B"=="device" if not defined JL22 set "JL22=%%A"
)
if not defined JL22 (
  echo [ERROR] Live JL22 not found.
  adb devices -l
  pause
  exit /b 13
)

set "KOZEN="
set "KOZEN_ADB_AVAILABLE=0"
adb connect 192.168.31.134:5555 >nul 2>nul
adb -s "192.168.31.134:5555" get-state >nul 2>nul
if not errorlevel 1 (
  adb -s "192.168.31.134:5555" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
  if not errorlevel 1 (
    set "KOZEN=192.168.31.134:5555"
    set "KOZEN_ADB_AVAILABLE=1"
  )
)

echo [JL22] %JL22%
if "%KOZEN_ADB_AVAILABLE%"=="1" (
  echo [KOZEN ADB] %KOZEN%
) else (
  echo [KOZEN ADB] unavailable - allowed. Snapshot will use existing production bridge over USB/AOA.
)

echo [1/7] Building i-Retail debug APK...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 (
  echo [ERROR] Build failed.
  pause
  exit /b 20
)

set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APP_APK%" (
  echo [ERROR] APK not found.
  pause
  exit /b 21
)

echo [2/7] Installing i-Retail on JL22 only...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 (
  echo [ERROR] Install failed.
  pause
  exit /b 22
)

echo [3/7] Persisting safe STANDALONE + real POS FALSE...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
timeout /t 1 /nobreak >nul

if "%KOZEN_ADB_AVAILABLE%"=="1" (
  adb -s "%KOZEN%" logcat -c
  adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
)
adb -s "%JL22%" logcat -c

echo [4/7] Reading current SmartSkyPOS/acquirer snapshot...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez acquirer_readonly_snapshot true >nul
if errorlevel 1 (
  echo [ERROR] Could not start snapshot.
  pause
  exit /b 23
)

set "WAIT_LOG=%TEMP%\iretail_acquirer_snapshot_wait.log"
set "OUTCOME=SNAPSHOT_TIMEOUT"
for /l %%S in (1,1,150) do (
  if "%KOZEN_ADB_AVAILABLE%"=="1" (
    if "%%S"=="1" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
    if "%%S"=="3" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
    if "%%S"=="5" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
  )
  adb -s "%JL22%" logcat -d -v brief AcquirerSnapshot:V IretailKozenClient:V IretailMachineMode:I *:S > "%WAIT_LOG%" 2>&1
  findstr /C:"SNAPSHOT_RESULT ok=true" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=SNAPSHOT_OK"
    goto SNAPSHOT_DONE
  )
  findstr /C:"SNAPSHOT_RESULT ok=false" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=SNAPSHOT_FAILED"
    goto SNAPSHOT_DONE
  )
  timeout /t 1 /nobreak >nul
)

:SNAPSHOT_DONE
echo [5/7] Restoring ordinary safe i-Retail foreground...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false >nul 2>nul
timeout /t 1 /nobreak >nul

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "acquirer_snapshot_logs" mkdir "acquirer_snapshot_logs"
set "OUT=acquirer_snapshot_logs\ACQUIRER_SNAPSHOT_%TS%"
mkdir "%OUT%"

echo [6/7] Collecting and sanitizing evidence...
(
  echo version=%EXPECTED_VERSION%
  echo outcome=%OUTCOME%
  echo safety=READ_ONLY_NO_FINANCIAL_COMMANDS
  echo real_pos=false
  echo kozen_adb_available=%KOZEN_ADB_AVAILABLE%
) > "%OUT%\01_environment.txt"

adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail 2>nul | findstr /I "versionName= versionCode=" > "%OUT%\02_package.txt"
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_machine_mode_v1.xml > "%OUT%\03_machine_mode.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime AcquirerSnapshot:V IretailKozenClient:V IretailMachineMode:I AndroidRuntime:E *:S > "%OUT%\RAW_jl22_logcat.txt" 2>&1
if "%KOZEN_ADB_AVAILABLE%"=="1" (
  adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:V AndroidRuntime:E *:S > "%OUT%\RAW_kozen_logcat.txt" 2>&1
) else (
  > "%OUT%\RAW_kozen_logcat.txt" echo KOZEN_ADB_NOT_AVAILABLE
)
(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  findstr /I "SNAPSHOT_RESULT ACQUIRER_SNAPSHOT_OK ACQUIRER_SNAPSHOT_FAILED" "%OUT%\RAW_jl22_logcat.txt"
) > "%OUT%\07_summary.txt" 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Sanitize-FiscalPositivePaymentReport.ps1" -RawJl22 "%CD%\%OUT%\RAW_jl22_logcat.txt" -RawKozen "%CD%\%OUT%\RAW_kozen_logcat.txt" -ReportDir "%CD%\%OUT%"
if errorlevel 1 (
  echo [ERROR] Safety scan failed.
  pause
  exit /b 30
)

echo [7/7] Creating archive and publishing evidence...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Set-Content -Encoding ASCII -LiteralPath ($z+'.safe.txt') -Value 'SAFETY_SCAN_OK'; Write-Host ('[REPORT] '+$z)"
if errorlevel 1 exit /b 31

call "%~dp0GIT_129_PUBLISH_ACQUIRER_SNAPSHOT.bat"
if errorlevel 1 echo [WARN] Publication failed; local ZIP preserved.

echo.
echo ============================================================
echo ACQUIRER READ-ONLY SNAPSHOT COMPLETE
echo Outcome: %OUTCOME%
echo No financial command was sent.
echo ============================================================
pause
if /I "%OUTCOME%"=="SNAPSHOT_OK" exit /b 0
exit /b 2
