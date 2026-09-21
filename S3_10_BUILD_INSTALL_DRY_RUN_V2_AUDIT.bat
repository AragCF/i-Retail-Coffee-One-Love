@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.55-s3-dry-run-v2"
set "GIT_BRANCH="
set "ADB_SERIAL="
set "DEVICE_PICK=%TEMP%\iretail_jl22_%RANDOM%_%RANDOM%.txt"

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git not found in PATH.
  pause
  exit /b 11
)

for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong branch: %GIT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 12
)

git diff --quiet
if errorlevel 1 (
  echo [ERROR] Tracked working tree contains local changes.
  git status --short
  pause
  exit /b 13
)
git diff --cached --quiet
if errorlevel 1 (
  echo [ERROR] Git index already contains staged changes.
  git status --short
  pause
  exit /b 14
)

if exist "%DEVICE_PICK%" del /F /Q "%DEVICE_PICK%" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Select-JL22Device.ps1" -OutputFile "%DEVICE_PICK%" -PreferredSerial "%~1"
if errorlevel 1 (
  echo [ERROR] Android device selection failed.
  pause
  exit /b 15
)
set /p ADB_SERIAL=<"%DEVICE_PICK%"
del /F /Q "%DEVICE_PICK%" >nul 2>nul
if not defined ADB_SERIAL (
  echo [ERROR] Empty ADB serial.
  pause
  exit /b 16
)

echo ============================================================
echo i-Retail v0.5.55 - S3 DRY_RUN v2
echo ============================================================
echo [1/4] Build and install the diagnostic APK.
echo [2/4] Create one local order draft from the UI.
echo [3/4] Collect and validate the v2 contract report.
echo [4/4] Publish the safe ZIP to Git.
echo.
echo [SAFETY] No device registration, order synchronization,
echo [SAFETY] shift mutation, employee authorization or payment creation.
echo.

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

adb -s %ADB_SERIAL% install -r "%APK%"
if errorlevel 1 (
  echo [ERROR] APK install failed.
  pause
  exit /b 22
)

adb -s %ADB_SERIAL% logcat -c
adb -s %ADB_SERIAL% shell am force-stop com.coffeeonelove.iretail
adb -s %ADB_SERIAL% shell am start -n com.coffeeonelove.iretail/.ui.MainActivity >nul 2>&1

echo.
echo ============================================================
echo SAFE S3 DRY_RUN v2
echo 1. Add one or more products to the cart.
echo 2. Open the order and press the button that opens PAYMENT METHODS.
echo 3. DO NOT choose card, cash or online payment.
echo 4. Return here and press any key.
echo ============================================================
pause >nul

for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%T"
set "OUT=test_reports\s3_dry_run_v2\S3_DRY_RUN_V2_%STAMP%"
set "ZIP=%OUT%.zip"
if not exist "test_reports\s3_dry_run_v2" mkdir "test_reports\s3_dry_run_v2"
mkdir "%OUT%" >nul 2>nul

adb -s %ADB_SERIAL% shell run-as com.coffeeonelove.iretail cat files/order_sync_draft.json > "%OUT%\01_order_sync_draft.json" 2> "%OUT%\01_order_sync_draft_error.txt"
adb -s %ADB_SERIAL% logcat -d -v threadtime IretailOrderDraft:I IretailCatalog:I AndroidRuntime:E *:S > "%OUT%\02_logcat_filtered.txt" 2>&1
adb -s %ADB_SERIAL% shell dumpsys package com.coffeeonelove.iretail > "%OUT%\03_package.txt" 2>&1
adb -s %ADB_SERIAL% shell screencap -p /sdcard/iretail_s3_dry_run_v2.png >nul 2>&1
adb -s %ADB_SERIAL% pull /sdcard/iretail_s3_dry_run_v2.png "%OUT%\04_screen.png" > "%OUT%\04_screen_pull.txt" 2>&1
adb -s %ADB_SERIAL% shell rm /sdcard/iretail_s3_dry_run_v2.png >nul 2>&1

(
  echo i-Retail v0.5.55 S3 DRY_RUN v2
  echo Device=%ADB_SERIAL%
  echo Timestamp=%STAMP%
  echo.
  echo EXPECTED:
  echo mode=DRY_RUN_ONLY
  echo schema_version=S3_DRY_RUN_V2
  echo send_allowed=false
  echo contract_state=BLOCKED_PENDING_DEVICE_REGISTER_DECISION
  echo Current device, shift and counters must remain unresolved.
) > "%OUT%\SUMMARY.txt"

findstr /C:"S3_DRY_RUN_V2" "%OUT%\01_order_sync_draft.json" >nul
if errorlevel 1 (
  echo [ERROR] S3_DRY_RUN_V2 marker not found.
  pause
  exit /b 30
)
findstr /C:"BLOCKED_PENDING_DEVICE_REGISTER_DECISION" "%OUT%\01_order_sync_draft.json" >nul
if errorlevel 1 (
  echo [ERROR] Contract gate marker not found.
  pause
  exit /b 31
)
findstr /C:"\"send_allowed\": false" "%OUT%\01_order_sync_draft.json" >nul
if errorlevel 1 (
  echo [ERROR] send_allowed=false marker not found.
  pause
  exit /b 32
)

powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath '%ZIP%' -Force"
if errorlevel 1 (
  echo [ERROR] ZIP creation failed.
  pause
  exit /b 33
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Assert-S3DryRunV2Safe.ps1" -ZipPath "%CD%\%ZIP%"
if errorlevel 1 (
  echo [ERROR] S3 DRY_RUN v2 safety validation failed.
  pause
  exit /b 34
)

call "%~dp0S3_11_PUBLISH_DRY_RUN_V2.bat"
if errorlevel 1 (
  echo [ERROR] Report was created but Git publication failed.
  pause
  exit /b 35
)

echo.
echo [SUCCESS] S3 DRY_RUN v2 completed and published.
powershell -NoProfile -Command "Write-Host 'S3 DRY_RUN v2 в Git, продолжай.'"
pause
exit /b 0
