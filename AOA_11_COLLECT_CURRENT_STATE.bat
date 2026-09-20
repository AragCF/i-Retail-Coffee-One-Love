@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
set "NO_PAUSE=%~3"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"

echo ============================================================
echo AOA CURRENT STATE COLLECTOR
echo ============================================================
echo READ-ONLY. Does not restart apps, does not switch USB mode and
echo does not invoke any payment operation.
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 goto :adb_missing

adb -s "%JL22%" get-state >nul 2>nul
if errorlevel 1 goto :jl22_offline
adb -s "%KOZEN%" get-state >nul 2>nul
if errorlevel 1 goto :kozen_offline

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"

if not exist "aoa_logs" mkdir "aoa_logs"
set "OUT=aoa_logs\AOA_JL22_KOZEN_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo kozen=%KOZEN%
  echo timestamp=%TS%
  echo test=AOA_11_COLLECT_CURRENT_STATE
  echo mode=READ_ONLY
) > "%OUT%\00_info.txt"

echo [1/8] Windows ADB inventory...
adb devices -l > "%OUT%\01_windows_adb_devices.txt" 2>&1

echo [2/8] JL22 AOA logs...
adb -s "%JL22%" logcat -d -v threadtime IretailAoaHost:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\JL22_02_aoa_logcat.txt" 2>&1

echo [3/8] Kozen bridge logs...
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\KOZEN_02_bridge_logcat.txt" 2>&1

echo [4/8] USB manager state...
adb -s "%JL22%" shell dumpsys usb > "%OUT%\JL22_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys usb > "%OUT%\KOZEN_03_dumpsys_usb.txt" 2>&1

echo [5/8] JL22 USB bus...
(
  echo ===== lsusb =====
  adb -s "%JL22%" shell lsusb
  echo.
  echo ===== sysfs USB devices =====
  adb -s "%JL22%" shell "for d in /sys/bus/usb/devices/*; do if [ -f \"$d/idVendor\" ]; then echo DEVICE:$d; echo -n VID=; cat \"$d/idVendor\"; echo -n PID=; cat \"$d/idProduct\"; echo -n MANUFACTURER=; cat \"$d/manufacturer\" 2>/dev/null; echo -n PRODUCT=; cat \"$d/product\" 2>/dev/null; echo ----; fi; done"
) > "%OUT%\JL22_04_usb_bus.txt" 2>&1

echo [6/8] Package/activity/process state...
adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail.aoahost > "%OUT%\JL22_05_package.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.coffeeonelove.iretail.kozenbridge > "%OUT%\KOZEN_05_package.txt" 2>&1
adb -s "%JL22%" shell dumpsys activity activities > "%OUT%\JL22_06_activities.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity activities > "%OUT%\KOZEN_06_activities.txt" 2>&1
adb -s "%JL22%" shell ps > "%OUT%\JL22_07_ps.txt" 2>&1
adb -s "%KOZEN%" shell ps > "%OUT%\KOZEN_07_ps.txt" 2>&1

echo [7/8] Kozen USB properties...
adb -s "%KOZEN%" shell getprop > "%OUT%\KOZEN_08_getprop.txt" 2>&1
findstr /I "usb accessory adb config state controller bootreason" "%OUT%\KOZEN_08_getprop.txt" > "%OUT%\KOZEN_08b_getprop_usb_filtered.txt" 2>&1

echo [8/8] High-value summary...
(
  echo ===== JL22 AOA LOG =====
  findstr /I "AOA USB_PERMISSION PING PONG INFO" "%OUT%\JL22_02_aoa_logcat.txt"
  echo.
  echo ===== KOZEN BRIDGE LOG =====
  findstr /I "ACCESSORY BRIDGE RX TX PING PONG INFO ERROR" "%OUT%\KOZEN_02_bridge_logcat.txt"
  echo.
  echo ===== JL22 USB IDS =====
  findstr /I "Bus VID= PID= MANUFACTURER= PRODUCT=" "%OUT%\JL22_04_usb_bus.txt"
  echo.
  echo ===== KOZEN USB STATE =====
  findstr /I "connected configured kernel_state supported_modes current_mode power_role data_role" "%OUT%\KOZEN_03_dumpsys_usb.txt"
  echo.
  echo ===== KOZEN USB PROPERTIES =====
  type "%OUT%\KOZEN_08b_getprop_usb_filtered.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo.
echo [ZIP] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"
if errorlevel 1 goto :zip_failed

echo ============================================================
echo COLLECTION COMPLETE.
echo Publish with: call GIT_101_PUBLISH_AOA_RESULT.bat
echo ============================================================
if /I not "%NO_PAUSE%"=="--nopause" pause
exit /b 0

:adb_missing
echo [ERROR] adb was not found in PATH.
if /I not "%NO_PAUSE%"=="--nopause" pause
exit /b 2

:jl22_offline
echo [ERROR] JL22 ADB endpoint is not online: %JL22%
if /I not "%NO_PAUSE%"=="--nopause" pause
exit /b 3

:kozen_offline
echo [ERROR] Kozen ADB endpoint is not online: %KOZEN%
if /I not "%NO_PAUSE%"=="--nopause" pause
exit /b 4

:zip_failed
echo [ERROR] Failed to create AOA diagnostic ZIP.
if /I not "%NO_PAUSE%"=="--nopause" pause
exit /b 5
