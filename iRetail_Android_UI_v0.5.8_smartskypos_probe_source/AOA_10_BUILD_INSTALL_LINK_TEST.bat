@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"

echo ============================================================
echo i-Retail AOA TRANSPORT TEST: JL22 host ^> Kozen P12 bridge
echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo.
echo IMPORTANT:
echo   - This test DOES NOT call payment(), refund() or cancel().
echo   - It WILL intentionally switch Kozen USB into Android Open
echo     Accessory mode for this cable session. Unplug/replug restores
echo     the normal raw USB mode.
echo   - Keep Kozen connected to JL22 with the short stable cable.
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

where java >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Java was not found in PATH. JDK 17 is recommended.
  pause
  exit /b 5
)

set "SDK_PATH="
if defined ANDROID_HOME set "SDK_PATH=%ANDROID_HOME%"
if not defined SDK_PATH if defined ANDROID_SDK_ROOT set "SDK_PATH=%ANDROID_SDK_ROOT%"
if not defined SDK_PATH if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_PATH=%LOCALAPPDATA%\Android\Sdk"
if not defined SDK_PATH (
  echo [ERROR] Android SDK was not found.
  pause
  exit /b 6
)
set "SDK_PATH_GRADLE=%SDK_PATH:\=/%"
> local.properties echo sdk.dir=%SDK_PATH_GRADLE%

set "GRADLE_CMD="
if exist "gradlew.bat" set "GRADLE_CMD=%CD%\gradlew.bat"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD (
  echo [ERROR] Gradle was not found. Use Gradle 8.7-8.10.x.
  pause
  exit /b 7
)

echo [1/7] Building Kozen bridge and JL22 AOA host probe...
call "%GRADLE_CMD%" --no-daemon --stacktrace :kozenBridge:assembleDebug :jl22AoaProbe:assembleDebug
if errorlevel 1 (
  echo [ERROR] AOA APK build failed.
  pause
  exit /b 8
)

set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
set "JL22_APK=jl22AoaProbe\build\outputs\apk\debug\jl22AoaProbe-debug.apk"
if not exist "%KOZEN_APK%" (
  echo [ERROR] Missing %KOZEN_APK%
  pause
  exit /b 9
)
if not exist "%JL22_APK%" (
  echo [ERROR] Missing %JL22_APK%
  pause
  exit /b 10
)

echo [2/7] Installing Kozen Payment Bridge probe...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 (
  echo [ERROR] Kozen bridge APK install failed.
  pause
  exit /b 11
)

echo [3/7] Installing JL22 AOA host probe...
adb -s "%JL22%" install -r "%JL22_APK%"
if errorlevel 1 (
  echo [ERROR] JL22 AOA host APK install failed.
  pause
  exit /b 12
)

echo [4/7] Clearing only diagnostic log buffers and opening Kozen bridge status...
adb -s "%KOZEN%" logcat -c
adb -s "%JL22%" logcat -c
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity

echo [5/7] Starting AOA handshake from JL22...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail.aoahost/.AoaHostProbeActivity

echo.
echo ============================================================
echo WATCH BOTH SCREENS NOW.
echo.
echo If JL22 asks for USB permission for Kozen, tap ALLOW.
echo If Kozen asks which app should handle the USB accessory, choose
echo "i-Retail Kozen Bridge" and allow it.
echo.
echo Success on JL22 should end with:
echo   RX: PONG 1001 ...
echo   RX: INFO 1002 ...
echo   JL22 ^<-> AOA ^<-> Kozen Bridge works.
echo.
echo No financial operation is executed by this probe.
echo ============================================================
pause

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "aoa_logs" mkdir "aoa_logs"
set "OUT=aoa_logs\AOA_JL22_KOZEN_%TS%"
mkdir "%OUT%"

echo [6/7] Collecting both sides...
(
  echo jl22=%JL22%
  echo kozen=%KOZEN%
  echo timestamp=%TS%
  echo test=AOA_10_BUILD_INSTALL_LINK_TEST
) > "%OUT%\00_info.txt"
adb devices -l > "%OUT%\01_windows_adb_devices.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime IretailAoaHost:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\JL22_02_aoa_logcat.txt" 2>&1
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\KOZEN_02_bridge_logcat.txt" 2>&1
adb -s "%JL22%" shell dumpsys usb > "%OUT%\JL22_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys usb > "%OUT%\KOZEN_03_dumpsys_usb.txt" 2>&1
(
  echo ===== lsusb =====
  adb -s "%JL22%" shell lsusb
  echo.
  echo ===== sysfs USB devices =====
  adb -s "%JL22%" shell "for d in /sys/bus/usb/devices/*; do if [ -f \"$d/idVendor\" ]; then echo DEVICE:$d; echo -n VID=; cat \"$d/idVendor\"; echo -n PID=; cat \"$d/idProduct\"; echo -n MANUFACTURER=; cat \"$d/manufacturer\" 2>/dev/null; echo -n PRODUCT=; cat \"$d/product\" 2>/dev/null; echo ----; fi; done"
) > "%OUT%\JL22_04_usb_bus.txt" 2>&1
adb -s "%KOZEN%" shell getprop > "%OUT%\KOZEN_04_getprop.txt" 2>&1
adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail.aoahost > "%OUT%\JL22_05_package.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.coffeeonelove.iretail.kozenbridge > "%OUT%\KOZEN_05_package.txt" 2>&1

(
  echo ===== JL22 AOA result =====
  findstr /I "AOA_PROTOCOL AOA_START AOA_BULK_READY AOA_PING_OK AOA_LINK_OK AOA_.*FAILED AOA_.*TIMEOUT" "%OUT%\JL22_02_aoa_logcat.txt"
  echo.
  echo ===== Kozen bridge result =====
  findstr /I "ACCESSORY BRIDGE_READY RX TX BRIDGE_IO_ERROR" "%OUT%\KOZEN_02_bridge_logcat.txt"
  echo.
  echo ===== JL22 USB IDs after test =====
  findstr /I "Bus VID= PID= MANUFACTURER= PRODUCT=" "%OUT%\JL22_04_usb_bus.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [7/7] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo TEST COMPLETE.
echo Publish the new ZIP with:
echo   call GIT_101_PUBLISH_AOA_RESULT.bat
echo ============================================================
pause
exit /b 0
