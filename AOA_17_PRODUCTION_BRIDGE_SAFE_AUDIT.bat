@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
set "TID=%~3"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"
if not defined TID set "TID=12000679"
set "OUTCOME=STARTED"
set "WAITLOG=%TEMP%\iretail_prod_bridge_audit_wait.log"

echo ============================================================
echo i-Retail HARDENED PRODUCTION BRIDGE - READ-ONLY AUDIT
echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo TID  : %TID%
echo.
echo SAFETY:
echo   The installed Kozen production bridge contains payment support,
echo   but THIS JL22 audit client contains and sends only read-only commands:
echo   PING, INFO, GET_STATE, GET_TERMINAL_DATA,
echo   GET_LAST_TRANSACTION and GET_TRANSACTION.
echo   No PAYMENT, CANCEL, REFUND or reconciliation command is sent.
echo   NO CARD IS NEEDED.
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found in PATH.
  pause
  exit /b 2
)
adb -s "%JL22%" get-state >nul 2>nul
if errorlevel 1 (
  echo [ERROR] JL22 is not online: %JL22%
  pause
  exit /b 3
)
adb -s "%KOZEN%" get-state >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Kozen is not online: %KOZEN%
  pause
  exit /b 4
)

set "SDK_PATH="
if defined ANDROID_HOME set "SDK_PATH=%ANDROID_HOME%"
if not defined SDK_PATH if defined ANDROID_SDK_ROOT set "SDK_PATH=%ANDROID_SDK_ROOT%"
if not defined SDK_PATH if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_PATH=%LOCALAPPDATA%\Android\Sdk"
if not defined SDK_PATH (
  echo [ERROR] Android SDK was not found.
  pause
  exit /b 5
)
set "SDK_PATH_GRADLE=%SDK_PATH:\=/%"
> local.properties echo sdk.dir=%SDK_PATH_GRADLE%

set "GRADLE_CMD="
if exist "gradlew.bat" set "GRADLE_CMD=%CD%\gradlew.bat"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD (
  echo [ERROR] Gradle was not found.
  pause
  exit /b 6
)

echo [1/9] Building hardened Kozen bridge and JL22 read-only audit client...
call "%GRADLE_CMD%" --no-daemon --stacktrace :kozenBridge:assembleDebug :jl22AoaRecovery:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed. No financial command was sent.
  pause
  exit /b 7
)

set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
set "JL22_APK=jl22AoaRecovery\build\outputs\apk\debug\jl22AoaRecovery-debug.apk"

echo [2/9] Installing hardened Kozen production bridge...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 (
  echo [ERROR] Kozen bridge APK install failed.
  pause
  exit /b 8
)

echo [3/9] Installing JL22 read-only audit client...
adb -s "%JL22%" install -r "%JL22_APK%"
if errorlevel 1 (
  echo [ERROR] JL22 audit APK install failed.
  pause
  exit /b 9
)

echo [4/9] Closing old test clients and clearing diagnostic logs...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost >nul 2>nul
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoarecovery >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenrecovery >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
adb -s "%JL22%" logcat -c
adb -s "%KOZEN%" logcat -c

echo [5/9] Starting hardened Kozen production bridge...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity

echo [6/9] Starting JL22 READ-ONLY production bridge audit...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail.aoarecovery/.AoaProductionBridgeAuditActivity --es terminal_id "%TID%"

echo.
echo Waiting up to 150 seconds for the read-only audit.
echo If Android asks for USB/accessory permission, allow it.
echo NO CARD IS NEEDED. NO PAYMENT WILL BE STARTED BY THIS AUDIT.
echo.

for /l %%S in (1,1,150) do (
  adb -s "%JL22%" logcat -d -v brief IretailProdAudit:I *:S > "%WAITLOG%" 2>&1
  findstr /C:"PROD_BRIDGE_AUDIT_OK" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 goto AUDIT_OK
  findstr /C:"PROD_BRIDGE_AUDIT_FAILED" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 goto AUDIT_FAILED
  if "%%S"=="5" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
  timeout /t 1 /nobreak >nul
)
set "OUTCOME=AUDIT_TIMEOUT"
echo [TIMEOUT] Production bridge audit did not finish in 150 seconds.
goto COLLECT

:AUDIT_OK
set "OUTCOME=AUDIT_OK"
echo [SUCCESS] Hardened production bridge passed the read-only audit.
goto COLLECT

:AUDIT_FAILED
set "OUTCOME=AUDIT_FAILED"
echo [FAILED] Read-only production bridge audit reported an error.
goto COLLECT

:COLLECT
set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "aoa_production_bridge_logs" mkdir "aoa_production_bridge_logs"
set "OUT=aoa_production_bridge_logs\AOA_PROD_BRIDGE_JL22_KOZEN_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo kozen=%KOZEN%
  echo terminal_id=%TID%
  echo timestamp=%TS%
  echo outcome=%OUTCOME%
  echo audit_client=READ_ONLY_NO_FINANCIAL_COMMANDS
  echo production_bridge=0.5.0-production-hardening
) > "%OUT%\00_info.txt"

echo [7/9] Collecting both sides...
adb devices -l > "%OUT%\01_windows_adb_devices.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime IretailProdAudit:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\JL22_02_prod_audit_logcat.txt" 2>&1
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\KOZEN_02_bridge_logcat.txt" 2>&1
adb -s "%JL22%" shell dumpsys usb > "%OUT%\JL22_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys usb > "%OUT%\KOZEN_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity services com.skytech.smartskypos > "%OUT%\KOZEN_04_smartsky_services.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.coffeeonelove.iretail.kozenbridge > "%OUT%\KOZEN_05_bridge_package.txt" 2>&1

(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo ===== JL22 PRODUCTION BRIDGE SAFE AUDIT =====
  findstr /I "PROD_BRIDGE_AUDIT_OK PROD_BRIDGE_AUDIT_FAILED PROD_AUDIT_TERMINAL_DATA PROD_AUDIT_LAST_TRANSACTION PROD_AUDIT_TARGET_TRANSACTION PONG INFO STATE TERMINAL_DATA LAST_TRANSACTION TRANSACTION" "%OUT%\JL22_02_prod_audit_logcat.txt"
  echo.
  echo ===== KOZEN HARDENED BRIDGE =====
  findstr /I "BRIDGE_READY RX TX GET_LAST_TRANSACTION GET_TRANSACTION PAYMENT_CALL SMARTSKY_BOUND" "%OUT%\KOZEN_02_bridge_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [8/9] Closing audit applications...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoarecovery >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul

echo [9/9] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo PRODUCTION BRIDGE SAFE AUDIT COMPLETE. Outcome: %OUTCOME%
echo This audit client sent NO financial command.
echo Publish with:
echo   call GIT_106_PUBLISH_PRODUCTION_BRIDGE_AUDIT.bat
echo ============================================================
pause
exit /b 0
