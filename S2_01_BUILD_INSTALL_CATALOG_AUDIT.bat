@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "ADB_SERIAL=%~1"
set "ADB_CMD=adb"

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb not found in PATH.
  pause
  exit /b 11
)

if defined ADB_SERIAL goto DEVICE_READY

set "FOUND_SERIAL="
set "FOUND_COUNT=0"
for /f "skip=1 tokens=1,2" %%A in ('adb devices') do if "%%B"=="device" call :FOUND_DEVICE "%%A"

if not "%FOUND_COUNT%"=="1" (
  echo [ERROR] Expected exactly one adb device, found %FOUND_COUNT%.
  echo Run: S2_01_BUILD_INSTALL_CATALOG_AUDIT.bat SERIAL
  adb devices
  pause
  exit /b 12
)
set "ADB_SERIAL=%FOUND_SERIAL%"

:DEVICE_READY
set "ADB_CMD=adb -s %ADB_SERIAL%"
echo [INFO] Device: %ADB_SERIAL%

call BUILD_WINDOWS_CLI.bat
if errorlevel 1 (
  echo [ERROR] APK build failed.
  pause
  exit /b 20
)

set "APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APK%" (
  echo [ERROR] APK not found: %APK%
  pause
  exit /b 21
)

%ADB_CMD% install -r "%APK%"
if errorlevel 1 (
  echo [ERROR] APK install failed.
  pause
  exit /b 22
)

for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%T"
set "OUT=test_reports\s2_catalog\S2_CATALOG_%STAMP%"
set "ZIP=%OUT%.zip"
if not exist "test_reports\s2_catalog" mkdir "test_reports\s2_catalog"
mkdir "%OUT%" >nul 2>nul

%ADB_CMD% logcat -c
%ADB_CMD% shell am force-stop com.coffeeonelove.iretail
%ADB_CMD% shell am start -n com.coffeeonelove.iretail/.ui.MainActivity > "%OUT%\01_start.txt" 2>&1

echo [INFO] Waiting 25 seconds for I-Retail authentication and catalog refresh...
timeout /t 25 /nobreak >nul

%ADB_CMD% shell dumpsys package com.coffeeonelove.iretail > "%OUT%\02_package.txt" 2>&1
%ADB_CMD% logcat -d -v threadtime IretailCatalog:I IretailKozenClient:I IretailMachineMode:I AndroidRuntime:E *:S > "%OUT%\03_logcat_filtered.txt" 2>&1
%ADB_CMD% logcat -d -v threadtime > "%OUT%\04_logcat_full.txt" 2>&1
%ADB_CMD% shell screencap -p /sdcard/iretail_s2_catalog.png >nul 2>&1
%ADB_CMD% pull /sdcard/iretail_s2_catalog.png "%OUT%\05_screen.png" > "%OUT%\05_screen_pull.txt" 2>&1
%ADB_CMD% shell rm /sdcard/iretail_s2_catalog.png >nul 2>&1

(
  echo i-Retail v0.5.36 S2 catalog audit
  echo Device=%ADB_SERIAL%
  echo Timestamp=%STAMP%
  echo.
  echo Expected evidence in 03_logcat_filtered.txt:
  echo IretailCatalog: REFRESH success=true source=I-Retail ZIP ...
  echo.
  echo If source=I-Retail ZIP cache, live refresh did not succeed.
  echo If source=content XML, neither live refresh nor valid cache was available.
) > "%OUT%\SUMMARY.txt"

powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath '%ZIP%' -Force"
if errorlevel 1 (
  echo [WARN] Could not create ZIP. Raw report remains in:
  echo %OUT%
  pause
  exit /b 30
)

echo.
echo [SUCCESS] Report:
echo %CD%\%ZIP%
echo Send this ZIP back for analysis.
pause
exit /b 0

:FOUND_DEVICE
set /a FOUND_COUNT+=1
set "FOUND_SERIAL=%~1"
exit /b 0
