@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"
set "OUTCOME=STARTED"

echo ============================================================
echo i-Retail v0.5.20 MAIN UI + KOZEN - SAFE INSTALL SMOKE
echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo.
echo SAFETY MODE:
echo   MainActivity is launched with real_pos_enabled=false.
echo   Card payment is BLOCKED in the main UI before the AOA payment client starts.
echo   This script never enables real POS and never sends PAYMENT.
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

echo [1/8] Building main i-Retail UI and hardened Kozen bridge...
call "%GRADLE_CMD%" --no-daemon --stacktrace :app:assembleDebug :kozenBridge:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed. No financial command was sent.
  pause
  exit /b 7
)

set "JL22_APK=app\build\outputs\apk\debug\app-debug.apk"
set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
if not exist "%JL22_APK%" (
  echo [ERROR] Main UI APK not found: %JL22_APK%
  pause
  exit /b 8
)
if not exist "%KOZEN_APK%" (
  echo [ERROR] Kozen bridge APK not found: %KOZEN_APK%
  pause
  exit /b 9
)

echo [2/8] Stopping old diagnostics and applications...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost >nul 2>nul
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoarecovery >nul 2>nul
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenrecovery >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul

echo [3/8] Installing v0.5.20 main UI on JL22...
adb -s "%JL22%" install -r "%JL22_APK%"
if errorlevel 1 (
  echo [ERROR] Main UI install failed.
  pause
  exit /b 10
)

echo [4/8] Installing hardened bridge 0.5.2 on Kozen...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 (
  echo [ERROR] Kozen bridge install failed.
  pause
  exit /b 11
)

adb -s "%JL22%" logcat -c
adb -s "%KOZEN%" logcat -c

echo [5/8] Launching Kozen bridge. It cannot initiate a payment by itself...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul

echo [6/8] Launching MAIN i-Retail UI in explicit SAFE MODE...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --ez real_pos_enabled false
if errorlevel 1 (
  echo [ERROR] Main UI launch failed.
  pause
  exit /b 12
)

echo.
echo ============================================================
echo MANUAL SAFE CHECK ON JL22
echo ============================================================
echo 1. Open or create any order in the i-Retail UI.
echo 2. Go to payment methods.
echo 3. Tap BANK CARD once.
echo.
echo Expected: the UI stays safe and shows that real Kozen POS is disabled.
echo No card should be requested and no money can be charged by this mode.
echo.
echo Press any key HERE only after this visual check.
echo ============================================================
pause >nul

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "main_ui_safe_smoke_logs" mkdir "main_ui_safe_smoke_logs"
set "OUT=main_ui_safe_smoke_logs\MAIN_UI_SAFE_SMOKE_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo kozen=%KOZEN%
  echo timestamp=%TS%
  echo launch_real_pos_enabled=false
  echo expected_app_version=0.5.20-main-ui-kozen-aoa
  echo expected_bridge_version=0.5.2-production-session-owner
) > "%OUT%\00_info.txt"

echo [7/8] Collecting evidence and checking for forbidden financial markers...
adb devices -l > "%OUT%\01_adb_devices.txt" 2>&1
adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail > "%OUT%\JL22_02_app_package.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.coffeeonelove.iretail.kozenbridge > "%OUT%\KOZEN_02_bridge_package.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime IretailKozenClient:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\JL22_03_payment_client_logcat.txt" 2>&1
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\KOZEN_03_bridge_logcat.txt" 2>&1
adb -s "%JL22%" shell dumpsys activity activities > "%OUT%\JL22_04_activities.txt" 2>&1

set "FINANCIAL_MARKER=0"
findstr /I /C:"PAYMENT_TX_ONCE" "%OUT%\JL22_03_payment_client_logcat.txt" >nul 2>nul
if not errorlevel 1 set "FINANCIAL_MARKER=1"
findstr /I /C:"PAYMENT_CALL_BEGIN" /C:"RX PAYMENT " "%OUT%\KOZEN_03_bridge_logcat.txt" >nul 2>nul
if not errorlevel 1 set "FINANCIAL_MARKER=1"

set "APP_OK=0"
findstr /I /C:"versionName=0.5.20-main-ui-kozen-aoa" "%OUT%\JL22_02_app_package.txt" >nul 2>nul
if not errorlevel 1 set "APP_OK=1"
set "BRIDGE_OK=0"
findstr /I /C:"versionName=0.5.2-production-session-owner" "%OUT%\KOZEN_02_bridge_package.txt" >nul 2>nul
if not errorlevel 1 set "BRIDGE_OK=1"

if "%FINANCIAL_MARKER%"=="1" (
  set "OUTCOME=UNSAFE_FINANCIAL_MARKER_FOUND"
) else if "%APP_OK%"=="0" (
  set "OUTCOME=WRONG_MAIN_UI_VERSION"
) else if "%BRIDGE_OK%"=="0" (
  set "OUTCOME=WRONG_BRIDGE_VERSION"
) else (
  set "OUTCOME=SAFE_OK_NO_PAYMENT_SENT"
)

(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo real_pos_enabled=false
  echo financial_marker_found=%FINANCIAL_MARKER%
  echo main_ui_version_ok=%APP_OK%
  echo kozen_bridge_version_ok=%BRIDGE_OK%
  echo.
  echo ===== JL22 KOZEN CLIENT FINANCIAL MARKERS =====
  findstr /I "PAYMENT_TX_ONCE PAYMENT_RX PAYMENT_CLIENT_ERROR UNRESOLVED_STATUS_RECOVERY" "%OUT%\JL22_03_payment_client_logcat.txt"
  echo.
  echo ===== KOZEN BRIDGE FINANCIAL MARKERS =====
  findstr /I "RX PAYMENT PAYMENT_CALL_BEGIN PAYMENT_CALL_RESULT PAYMENT_CALL_UNCERTAIN" "%OUT%\KOZEN_03_bridge_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [8/8] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo MAIN UI SAFE SMOKE COMPLETE. Outcome: %OUTCOME%
echo No real POS mode was enabled by this script.
echo Publish with:
echo   call GIT_107_PUBLISH_MAIN_UI_SAFE_SMOKE.bat
echo ============================================================
pause
exit /b 0
