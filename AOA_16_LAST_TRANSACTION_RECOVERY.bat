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
set "WAITLOG=%TEMP%\iretail_aoa_recovery_wait.log"

echo ============================================================
echo i-Retail READ-ONLY TRANSACTION RECOVERY OVER AOA
echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo TID  : %TID%
echo.
echo SAFETY: this package contains no PAYMENT, CANCEL, REFUND or
echo reconciliation command. It only reads state and transaction data.
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

echo [1/9] Building read-only recovery apps...
call "%GRADLE_CMD%" --no-daemon --stacktrace :kozenRecoveryBridge:assembleDebug :jl22AoaRecovery:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed. No financial command exists in this test.
  pause
  exit /b 7
)

set "KOZEN_APK=kozenRecoveryBridge\build\outputs\apk\debug\kozenRecoveryBridge-debug.apk"
set "JL22_APK=jl22AoaRecovery\build\outputs\apk\debug\jl22AoaRecovery-debug.apk"

echo [2/9] Installing read-only Kozen Recovery Bridge...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 (
  echo [ERROR] Kozen recovery APK install failed.
  pause
  exit /b 8
)

echo [3/9] Installing JL22 read-only recovery host...
adb -s "%JL22%" install -r "%JL22_APK%"
if errorlevel 1 (
  echo [ERROR] JL22 recovery APK install failed.
  pause
  exit /b 9
)

echo [4/9] Closing old test senders and clearing diagnostic logs...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoarecovery >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenrecovery >nul 2>nul
adb -s "%JL22%" logcat -c
adb -s "%KOZEN%" logcat -c

echo [5/9] Starting Kozen Recovery Bridge...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenrecovery/.RecoveryBridgeActivity

echo [6/9] Starting JL22 read-only recovery...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail.aoarecovery/.AoaRecoveryActivity --es terminal_id "%TID%"

echo.
echo Waiting up to 150 seconds for read-only recovery.
echo If Kozen asks for USB accessory permission, allow it.
echo NO CARD IS NEEDED. NO PAYMENT WILL BE STARTED.
echo.

for /l %%S in (1,1,150) do (
  adb -s "%JL22%" logcat -d -v brief IretailAoaRecovery:I *:S > "%WAITLOG%" 2>&1
  findstr /C:"RECOVERY_OVER_AOA_OK" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 goto RECOVERY_OK
  findstr /C:"RECOVERY_OVER_AOA_FAILED" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 goto RECOVERY_FAILED
  rem v0.5.22: do not relaunch RecoveryBridgeActivity; duplicate starts can interrupt the live AOA reader.
  timeout /t 1 /nobreak >nul
)
set "OUTCOME=RECOVERY_TIMEOUT"
echo [TIMEOUT] Recovery did not finish in 150 seconds.
goto COLLECT

:RECOVERY_OK
set "OUTCOME=RECOVERY_OK"
echo [SUCCESS] Last transaction was read over JL22 - USB/AOA - Kozen - SmartSkyPOS.
goto COLLECT

:RECOVERY_FAILED
set "OUTCOME=RECOVERY_FAILED"
echo [FAILED] Read-only recovery reported an error. Evidence will be collected.
goto COLLECT

:COLLECT
set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "aoa_recovery_logs" mkdir "aoa_recovery_logs"
set "OUT=aoa_recovery_logs\AOA_RECOVERY_JL22_KOZEN_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo kozen=%KOZEN%
  echo terminal_id=%TID%
  echo timestamp=%TS%
  echo outcome=%OUTCOME%
  echo safety=READ_ONLY_NO_FINANCIAL_COMMANDS
) > "%OUT%\00_info.txt"

echo [7/9] Collecting read-only evidence...
adb devices -l > "%OUT%\01_windows_adb_devices.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime IretailAoaRecovery:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\JL22_02_recovery_logcat.txt" 2>&1
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenRecovery:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\KOZEN_02_recovery_logcat.txt" 2>&1
adb -s "%JL22%" shell dumpsys usb > "%OUT%\JL22_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys usb > "%OUT%\KOZEN_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity services com.skytech.smartskypos > "%OUT%\KOZEN_04_smartsky_services.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.skytech.smartskypos > "%OUT%\KOZEN_05_smartsky_package.txt" 2>&1

(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo ===== JL22 READ-ONLY RECOVERY =====
  findstr /I "RECOVERY_LAST_TRANSACTION_RESULT RECOVERY_TARGET_TRANSACTION_RESULT RECOVERY_OVER_AOA_OK RECOVERY_OVER_AOA_FAILED LAST_TRANSACTION TRANSACTION" "%OUT%\JL22_02_recovery_logcat.txt"
  echo.
  echo ===== KOZEN READ-ONLY RECOVERY =====
  findstr /I "RECOVERY_LAST_TRANSACTION_OK RECOVERY_TRANSACTION_OK LAST_TRANSACTION TRANSACTION READ_ONLY" "%OUT%\KOZEN_02_recovery_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [8/9] Closing recovery applications...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoarecovery >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenrecovery >nul 2>nul

echo [9/9] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo READ-ONLY RECOVERY COMPLETE. Outcome: %OUTCOME%
echo No financial operation was executed by this package.
echo Publish with:
echo   call GIT_105_PUBLISH_AOA_RECOVERY_RESULT.bat
echo ============================================================
pause
exit /b 0
