@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"

echo ============================================================
echo i-Retail v0.5.21 - ENABLE STANDALONE MODE + REAL KOZEN POS
echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo.
echo IMPORTANT:
echo   This script itself sends NO PAYMENT command.
echo   It persists standalone mode and real_pos_enabled=true.
echo   AFTER this script, tapping BANK CARD in the main i-Retail UI can start

echo   one real payment through JL22 - USB/AOA - Kozen - SmartSkyPOS.
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

echo [1/5] Building i-Retail main UI and Kozen bridge...
call "%GRADLE_CMD%" --no-daemon --stacktrace :app:assembleDebug :kozenBridge:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed. No payment was sent.
  pause
  exit /b 7
)

set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"

echo [2/5] Installing i-Retail v0.5.21 on JL22...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 8

echo [3/5] Installing hardened production bridge on Kozen...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 exit /b 9

echo [4/5] Starting Kozen production bridge...
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity
if errorlevel 1 exit /b 10

echo [5/5] Persisting STANDALONE mode with REAL POS enabled and starting i-Retail...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled true
if errorlevel 1 exit /b 11

echo.
echo ============================================================
echo STANDALONE + REAL POS IS NOW PERSISTENT.
echo No payment was sent by this script.
echo.
echo From now on, BANK CARD in the main i-Retail UI is the real path:
echo   JL22 - USB/AOA - Kozen - SmartSkyPOS.
echo One click creates one requestId; there is no automatic PAYMENT retry.
echo ============================================================
pause
exit /b 0
