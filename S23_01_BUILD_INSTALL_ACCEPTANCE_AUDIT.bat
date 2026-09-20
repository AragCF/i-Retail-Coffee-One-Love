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
  echo Run: S23_01_BUILD_INSTALL_ACCEPTANCE_AUDIT.bat SERIAL
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
set "OUT=test_reports\s23_acceptance\S23_ACCEPTANCE_%STAMP%"
set "ZIP=%OUT%.zip"
if not exist "test_reports\s23_acceptance" mkdir "test_reports\s23_acceptance"
mkdir "%OUT%" >nul 2>nul

%ADB_CMD% logcat -c
%ADB_CMD% shell am force-stop com.coffeeonelove.iretail
%ADB_CMD% shell am start -n com.coffeeonelove.iretail/.ui.MainActivity > "%OUT%\01_start.txt" 2>&1

echo.
echo ============================================================
echo SAFE S2 + S3 ACCEPTANCE
echo.
echo Stage A: live catalog
echo Waiting 25 seconds for I-Retail authentication and catalog refresh...
echo ============================================================
timeout /t 25 /nobreak >nul

%ADB_CMD% logcat -d -v threadtime IretailCatalog:I AndroidRuntime:E *:S > "%OUT%\02_catalog_logcat.txt" 2>&1
%ADB_CMD% shell screencap -p /sdcard/iretail_s23_catalog.png >nul 2>&1
%ADB_CMD% pull /sdcard/iretail_s23_catalog.png "%OUT%\03_catalog_screen.png" > "%OUT%\03_catalog_screen_pull.txt" 2>&1
%ADB_CMD% shell rm /sdcard/iretail_s23_catalog.png >nul 2>&1

echo.
echo ============================================================
echo Stage B: SAFE ORDER DRAFT
echo 1. In i-Retail add one or more products to the cart.
echo 2. Open the order and press the button that opens PAYMENT METHODS.
echo 3. DO NOT choose card, cash or online payment.
echo 4. Return here and press any key.
echo ============================================================
pause >nul

%ADB_CMD% shell run-as com.coffeeonelove.iretail cat files/order_sync_draft.json > "%OUT%\04_order_sync_draft.json" 2> "%OUT%\04_order_sync_draft_error.txt"
%ADB_CMD% logcat -d -v threadtime IretailOrderDraft:I IretailCatalog:I IretailKozenClient:I AndroidRuntime:E *:S > "%OUT%\05_logcat_filtered.txt" 2>&1
%ADB_CMD% shell dumpsys package com.coffeeonelove.iretail > "%OUT%\06_package.txt" 2>&1
%ADB_CMD% shell screencap -p /sdcard/iretail_s23_order.png >nul 2>&1
%ADB_CMD% pull /sdcard/iretail_s23_order.png "%OUT%\07_order_screen.png" > "%OUT%\07_order_screen_pull.txt" 2>&1
%ADB_CMD% shell rm /sdcard/iretail_s23_order.png >nul 2>&1

(
  echo i-Retail v0.5.38 combined S2+S3 acceptance
  echo Device=%ADB_SERIAL%
  echo Timestamp=%STAMP%
  echo.
  echo SAFETY:
  echo No payment method should be selected during this test.
  echo No iretail/order/synchronize request is expected.
  echo.
  echo S2 expected:
  echo IretailCatalog REFRESH success=true source=I-Retail ZIP
  echo.
  echo S3 expected:
  echo mode=DRY_RUN_ONLY
  echo send_allowed=false
  echo lines_equal_gross=true
) > "%OUT%\SUMMARY.txt"

powershell -NoProfile -Command "$p=Get-Content -Raw -LiteralPath '%OUT%\04_order_sync_draft.json' | ConvertFrom-Json; if($p.mode -ne 'DRY_RUN_ONLY'){exit 30}; if($p.send_allowed -ne $false){exit 31}; if($p.validation.lines_equal_gross -ne $true){exit 32}; exit 0"
set "JSON_RC=%ERRORLEVEL%"
if "%JSON_RC%"=="30" (
  echo [ERROR] JSON mode is not DRY_RUN_ONLY.
  pause
  exit /b 30
)
if "%JSON_RC%"=="31" (
  echo [ERROR] JSON send_allowed is not false. Stop.
  pause
  exit /b 31
)
if "%JSON_RC%"=="32" (
  echo [ERROR] JSON lines_equal_gross is not true.
  pause
  exit /b 32
)
if not "%JSON_RC%"=="0" (
  echo [ERROR] Could not parse order_sync_draft.json.
  echo Check: %OUT%\04_order_sync_draft_error.txt
  pause
  exit /b 34
)

powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath '%ZIP%' -Force"
if errorlevel 1 (
  echo [WARN] ZIP creation failed. Raw report remains at:
  echo %OUT%
  pause
  exit /b 33
)

echo.
echo [SUCCESS] Combined acceptance report:
echo %CD%\%ZIP%
echo Send this ZIP back for analysis.
pause
exit /b 0

:FOUND_DEVICE
set /a FOUND_COUNT+=1
set "FOUND_SERIAL=%~1"
exit /b 0
