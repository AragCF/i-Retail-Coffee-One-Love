@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "ADB_SERIAL=%~1"
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
  echo Run: S3_01_BUILD_INSTALL_ORDER_DRAFT_AUDIT.bat SERIAL
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

%ADB_CMD% logcat -c
%ADB_CMD% shell am force-stop com.coffeeonelove.iretail
%ADB_CMD% shell am start -n com.coffeeonelove.iretail/.ui.MainActivity >nul 2>&1

echo.
echo ============================================================
echo SAFE S3 DRY-RUN
echo 1. In i-Retail add one or more products to the cart.
echo 2. Open the order and press the button that opens PAYMENT METHODS.
echo 3. DO NOT choose card/cash/online payment.
echo 4. Return here and press any key.
echo ============================================================
pause >nul

for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%T"
set "OUT=test_reports\s3_order_draft\S3_ORDER_DRAFT_%STAMP%"
set "ZIP=%OUT%.zip"
if not exist "test_reports\s3_order_draft" mkdir "test_reports\s3_order_draft"
mkdir "%OUT%" >nul 2>nul

%ADB_CMD% shell run-as com.coffeeonelove.iretail cat files/order_sync_draft.json > "%OUT%\01_order_sync_draft.json" 2> "%OUT%\01_order_sync_draft_error.txt"
%ADB_CMD% logcat -d -v threadtime IretailOrderDraft:I IretailCatalog:I AndroidRuntime:E *:S > "%OUT%\02_logcat_filtered.txt" 2>&1
%ADB_CMD% shell dumpsys package com.coffeeonelove.iretail > "%OUT%\03_package.txt" 2>&1
%ADB_CMD% shell screencap -p /sdcard/iretail_s3_order_draft.png >nul 2>&1
%ADB_CMD% pull /sdcard/iretail_s3_order_draft.png "%OUT%\04_screen.png" > "%OUT%\04_screen_pull.txt" 2>&1
%ADB_CMD% shell rm /sdcard/iretail_s3_order_draft.png >nul 2>&1

(
  echo i-Retail v0.5.37 S3 order draft audit
  echo Device=%ADB_SERIAL%
  echo Timestamp=%STAMP%
  echo.
  echo SAFETY:
  echo This test must not send iretail/order/synchronize.
  echo Expected JSON mode=DRY_RUN_ONLY and send_allowed=false.
  echo Expected unresolved fields include id, employee_id, pin and wire contract.
) > "%OUT%\SUMMARY.txt"

findstr /C:"DRY_RUN_ONLY" "%OUT%\01_order_sync_draft.json" >nul
if errorlevel 1 (
  echo [ERROR] Dry-run draft was not found or is invalid.
  echo Check: %OUT%\01_order_sync_draft_error.txt
  pause
  exit /b 30
)

findstr /C:"\"send_allowed\": false" "%OUT%\01_order_sync_draft.json" >nul
if errorlevel 1 (
  echo [ERROR] send_allowed=false marker not found. Stop.
  pause
  exit /b 31
)

powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath '%ZIP%' -Force"
if errorlevel 1 (
  echo [WARN] ZIP creation failed. Raw report remains at:
  echo %OUT%
  pause
  exit /b 32
)

echo.
echo [SUCCESS] Safe order draft report:
echo %CD%\%ZIP%
echo Send this ZIP back for contract comparison.
pause
exit /b 0

:FOUND_DEVICE
set /a FOUND_COUNT+=1
set "FOUND_SERIAL=%~1"
exit /b 0
