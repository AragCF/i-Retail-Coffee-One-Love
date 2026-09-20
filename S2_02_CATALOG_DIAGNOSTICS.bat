@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.39-s2-catalog-diagnostics"
set "GIT_BRANCH="
set "GIT_SHA="

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git not found in PATH.
  pause
  exit /b 9
)

for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong Git branch: %GIT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 13
)

git diff --quiet
if errorlevel 1 (
  echo [ERROR] Tracked working tree contains local changes.
  git status --short
  pause
  exit /b 14
)
git diff --cached --quiet
if errorlevel 1 (
  echo [ERROR] Git index contains staged local changes.
  git status --short
  pause
  exit /b 15
)
for /f "delims=" %%H in ('git rev-parse HEAD') do if not defined GIT_SHA set "GIT_SHA=%%H"

set "ADB_SERIAL="
set "DEVICE_PICK=%TEMP%\iretail_jl22_%RANDOM%_%RANDOM%.txt"
if exist "%DEVICE_PICK%" del /F /Q "%DEVICE_PICK%" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Select-JL22Device.ps1" -OutputFile "%DEVICE_PICK%" -PreferredSerial "%~1"
if errorlevel 1 (
  echo [ERROR] Android device selection failed.
  if exist "%DEVICE_PICK%" del /F /Q "%DEVICE_PICK%" >nul 2>nul
  pause
  exit /b 12
)
if not exist "%DEVICE_PICK%" (
  echo [ERROR] Device selector did not return a serial.
  pause
  exit /b 12
)
set /p ADB_SERIAL=<"%DEVICE_PICK%"
del /F /Q "%DEVICE_PICK%" >nul 2>nul
if not defined ADB_SERIAL (
  echo [ERROR] Empty ADB serial returned by device selector.
  pause
  exit /b 12
)
set "ADB_CMD=adb -s %ADB_SERIAL%"

echo [INFO] Git: %GIT_BRANCH% @ %GIT_SHA%
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
set "OUT=test_reports\s2_catalog_diagnostics\S2_DIAGNOSTICS_%STAMP%"
set "ZIP=%OUT%.zip"
if not exist "test_reports\s2_catalog_diagnostics" mkdir "test_reports\s2_catalog_diagnostics"
mkdir "%OUT%" >nul 2>nul

(
  echo Branch=%GIT_BRANCH%
  echo SHA=%GIT_SHA%
  echo Device=%ADB_SERIAL%
  echo.
  adb devices -l
) > "%OUT%\00_git_and_device.txt" 2>&1

%ADB_CMD% shell getprop ro.product.product.name > "%OUT%\01_product_name.txt" 2>&1
%ADB_CMD% shell getprop ro.product.model > "%OUT%\02_model.txt" 2>&1
%ADB_CMD% shell getprop ro.product.device > "%OUT%\03_device.txt" 2>&1
%ADB_CMD% shell getprop ro.build.version.release > "%OUT%\04_android_version.txt" 2>&1

%ADB_CMD% logcat -c
%ADB_CMD% shell am force-stop com.coffeeonelove.iretail
%ADB_CMD% shell am start -n com.coffeeonelove.iretail/.ui.MainActivity --ez real_pos_enabled false > "%OUT%\05_start.txt" 2>&1

echo [INFO] Waiting 35 seconds for I-Retail catalog refresh...
timeout /t 35 /nobreak >nul

%ADB_CMD% logcat -d -v threadtime IretailCatalog:I AndroidRuntime:E *:S > "%OUT%\06_catalog_logcat.txt" 2>&1
%ADB_CMD% shell dumpsys package com.coffeeonelove.iretail > "%OUT%\07_package.txt" 2>&1
%ADB_CMD% shell ping -c 1 my.i-retail.com > "%OUT%\08_ping_api_host.txt" 2>&1
%ADB_CMD% shell getprop net.dns1 > "%OUT%\09_dns1.txt" 2>&1
%ADB_CMD% shell getprop net.dns2 > "%OUT%\10_dns2.txt" 2>&1
%ADB_CMD% shell settings get global http_proxy > "%OUT%\11_http_proxy.txt" 2>&1

%ADB_CMD% shell screencap -p /sdcard/iretail_s2_diag.png >nul 2>&1
%ADB_CMD% pull /sdcard/iretail_s2_diag.png "%OUT%\12_screen.png" > "%OUT%\12_screen_pull.txt" 2>&1
%ADB_CMD% shell rm /sdcard/iretail_s2_diag.png >nul 2>&1

set "LIVE=NO"
findstr /C:"REFRESH success=true source=I-Retail ZIP " "%OUT%\06_catalog_logcat.txt" >nul
if not errorlevel 1 set "LIVE=YES"

(
  echo i-Retail v0.5.39 S2 catalog diagnostics
  echo Timestamp=%STAMP%
  echo GitBranch=%GIT_BRANCH%
  echo GitSHA=%GIT_SHA%
  echo Device=%ADB_SERIAL%
  echo LiveCatalog=%LIVE%
  echo.
  echo Expected diagnostic fields in 06_catalog_logcat.txt:
  echo failureStage=authentication^|download^|parse^|validate^|cache^|unknown
  echo failureReason=REJECTED^|HTTP_NNN^|UNKNOWN_HOST^|TIMEOUT^|CONNECT^|SSL^|JSON^|...
  echo.
  echo No password, access token or client secret should be present in this report.
) > "%OUT%\SUMMARY.txt"

powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath '%ZIP%' -Force"
if errorlevel 1 (
  echo [WARN] ZIP creation failed. Raw report remains at:
  echo %OUT%
  pause
  exit /b 30
)

echo.
echo [SUCCESS] S2 diagnostics report:
echo %CD%\%ZIP%
echo Run S2_03_PUBLISH_LATEST_DIAGNOSTICS.bat to publish it to Git.
pause
exit /b 0
