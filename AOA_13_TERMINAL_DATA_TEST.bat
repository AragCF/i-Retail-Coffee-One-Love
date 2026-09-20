@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"

echo ============================================================
echo i-Retail READ-ONLY SmartSkyPOS TerminalData over USB/AOA
echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo.
echo This test calls only SmartSkyPOS getState() and getTerminalData().
echo NO payment, refund, cancel or reconciliation is called.
echo Keep Kozen connected to JL22 with the short stable USB cable.
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
  echo [ERROR] JL22 ADB endpoint is not online: %JL22%
  pause
  exit /b 3
)
adb -s "%KOZEN%" get-state >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Kozen ADB endpoint is not online: %KOZEN%
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

echo [1/8] Building Kozen bridge and JL22 host probe...
call "%GRADLE_CMD%" --no-daemon --stacktrace :kozenBridge:assembleDebug :jl22AoaProbe:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed.
  pause
  exit /b 7
)

set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
set "JL22_APK=jl22AoaProbe\build\outputs\apk\debug\jl22AoaProbe-debug.apk"

echo [2/8] Installing Kozen Bridge v0.3...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 (
  echo [ERROR] Kozen APK install failed.
  pause
  exit /b 8
)
echo [3/8] Installing JL22 host v0.3...
adb -s "%JL22%" install -r "%JL22_APK%"
if errorlevel 1 (
  echo [ERROR] JL22 APK install failed.
  pause
  exit /b 9
)

echo [4/8] Clearing diagnostic logs...
adb -s "%KOZEN%" logcat -c
adb -s "%JL22%" logcat -c
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost

echo [5/8] Starting Kozen Bridge...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity
echo [6/8] Starting JL22 TerminalData probe...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail.aoahost/.AoaHostProbeActivity

echo.
echo ============================================================
echo WATCH THE JL22 SCREEN.
echo Expected final result mentions payment operation and RUB/643.
echo This test DOES NOT execute a payment.
echo If Android asks for USB/accessory permission, allow it.
echo When a final result is visible, press any key here.
echo ============================================================
pause

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "aoa_terminal_data_logs" mkdir "aoa_terminal_data_logs"
set "OUT=aoa_terminal_data_logs\AOA_TERMINAL_DATA_JL22_KOZEN_%TS%"
mkdir "%OUT%"

echo [7/8] Collecting both sides...
(
  echo jl22=%JL22%
  echo kozen=%KOZEN%
  echo timestamp=%TS%
  echo test=AOA_13_TERMINAL_DATA_TEST
  echo safety=READ_ONLY_GET_STATE_AND_GET_TERMINAL_DATA
) > "%OUT%\00_info.txt"
adb devices -l > "%OUT%\01_windows_adb_devices.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime IretailAoaHost:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\JL22_02_aoa_logcat.txt" 2>&1
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\KOZEN_02_bridge_logcat.txt" 2>&1
adb -s "%JL22%" shell dumpsys usb > "%OUT%\JL22_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys usb > "%OUT%\KOZEN_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.skytech.smartskypos > "%OUT%\KOZEN_04_smartsky_package.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity services com.skytech.smartskypos > "%OUT%\KOZEN_05_smartsky_services.txt" 2>&1
(
  echo ===== JL22 RESULT =====
  findstr /I "AOA_LINK_OK SMARTSKY_STATE_OVER_AOA SMARTSKY_TERMINAL_DATA TERMINAL_DATA_READY TERMINAL_DATA_NOT" "%OUT%\JL22_02_aoa_logcat.txt"
  echo.
  echo ===== KOZEN BRIDGE RESULT =====
  findstr /I "SMARTSKY_GET_STATE SMARTSKY_GET_TERMINAL_DATA RX GET_TERMINAL_DATA TX TERMINAL_DATA" "%OUT%\KOZEN_02_bridge_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [8/8] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo TEST COMPLETE.
echo Publish with:
echo   call GIT_103_PUBLISH_AOA_TERMINAL_DATA_RESULT.bat
echo ============================================================
pause
exit /b 0
