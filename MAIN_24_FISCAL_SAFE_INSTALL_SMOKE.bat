@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.84-fiscal-safe-install-smoke"
set "EXPECTED_VERSION=0.5.84-fiscal-safe-install-smoke"
set "JL22=%~1"
set "OUTCOME=STARTED"

echo ============================================================
echo i-Retail v0.5.84 - FISCAL SAFE INSTALL SMOKE
echo ============================================================
echo.
echo SAFE MODE:
echo   - installs current i-Retail UI on JL22;
echo   - starts UI with real_pos_enabled=false;
echo   - does NOT use Kozen;
echo   - does NOT send PAYMENT;
echo   - does NOT call cloud-fiscal;
echo   - does NOT call order/synchronize;
echo   - verifies that no fiscal draft appears without confirmed payment.
echo ============================================================
echo.

for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong branch: %GIT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 11
)

git diff --quiet
if errorlevel 1 (
  echo [ERROR] Tracked working tree contains local changes.
  git status --short
  pause
  exit /b 12
)
git diff --cached --quiet
if errorlevel 1 (
  echo [ERROR] Git index contains staged changes.
  git status --short
  pause
  exit /b 13
)

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found in PATH.
  pause
  exit /b 14
)

if not defined JL22 (
  for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "$m=@(adb devices -l ^| Select-String 'product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno'); if($m.Count -eq 1){ (($m[0].Line -split '\s+')[0]) }"`) do if not defined JL22 set "JL22=%%D"
)

if not defined JL22 (
  echo [ERROR] Could not uniquely find JL22 by ADB signature:
  echo         product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno
  echo.
  adb devices -l
  echo.
  echo You may pass the JL22 adb serial/IP as the first argument.
  pause
  exit /b 15
)

adb -s "%JL22%" get-state >nul 2>nul
if errorlevel 1 (
  echo [ERROR] JL22 is not online: %JL22%
  pause
  exit /b 16
)

set "MODEL="
set "DEVICE="
set "PRODUCT="
for /f "delims=" %%V in ('adb -s "%JL22%" shell getprop ro.product.model 2^>nul') do if not defined MODEL set "MODEL=%%V"
for /f "delims=" %%V in ('adb -s "%JL22%" shell getprop ro.product.device 2^>nul') do if not defined DEVICE set "DEVICE=%%V"
for /f "delims=" %%V in ('adb -s "%JL22%" shell getprop ro.product.name 2^>nul') do if not defined PRODUCT set "PRODUCT=%%V"

if /I not "%MODEL%"=="UniWin_M190" (
  echo [ERROR] Selected device is not JL22. model=%MODEL%
  pause
  exit /b 17
)
if /I not "%DEVICE%"=="octopus-jetinno" (
  echo [ERROR] Selected device is not JL22. device=%DEVICE%
  pause
  exit /b 18
)

echo [JL22] %JL22% product=%PRODUCT% model=%MODEL% device=%DEVICE%
echo.

echo [1/7] Building v%EXPECTED_VERSION%...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 (
  echo [ERROR] Build failed. Nothing was installed.
  pause
  exit /b 20
)

set "APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APK%" (
  echo [ERROR] APK not found: %APK%
  pause
  exit /b 21
)

echo [2/7] Stopping current i-Retail UI and installing APK...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" install -r "%APK%"
if errorlevel 1 (
  echo [ERROR] APK install failed.
  pause
  exit /b 22
)

echo [3/7] Clearing only this smoke-test evidence...
adb -s "%JL22%" logcat -c
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail rm -f files/fiscalization_dry_run.json >nul 2>nul

echo [4/7] Launching UI in explicit SAFE MODE...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode kiosk --ez real_pos_enabled false
if errorlevel 1 (
  echo [ERROR] Main UI launch failed.
  pause
  exit /b 23
)

echo.
echo ============================================================
echo MANUAL SAFE CHECK ON JL22
echo ============================================================
echo 1. Make sure the i-Retail UI opened normally.
echo 2. Open the catalog and add ONE product to the order.
echo 3. Open payment methods.
echo 4. Tap BANK CARD exactly once.
echo.
echo Expected:
echo   - UI says real POS is disabled;
echo   - Kozen/card is NOT requested;
echo   - no payment is sent;
echo   - no fiscalization is sent.
echo.
echo Press any key HERE only after the check.
echo ============================================================
pause >nul

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"

set "OUT=fiscal_safe_smoke_logs\FISCAL_SAFE_SMOKE_%TS%"
if not exist "fiscal_safe_smoke_logs" mkdir "fiscal_safe_smoke_logs"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo product=%PRODUCT%
  echo model=%MODEL%
  echo device=%DEVICE%
  echo expected_version=%EXPECTED_VERSION%
  echo real_pos_enabled=false
  echo kozen_used=false
  echo financial_operation_allowed=false
  echo fiscal_network_allowed=false
  echo order_sync_allowed=false
) > "%OUT%\00_info.txt"

echo [5/7] Collecting safe evidence...
adb devices -l > "%OUT%\01_adb_devices.txt" 2>&1
adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail > "%OUT%\02_package.txt" 2>&1
adb -s "%JL22%" shell dumpsys activity activities > "%OUT%\03_activities.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime IretailMachineMode:I IretailOrderDraft:I FiscalDryRun:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\04_logcat.txt" 2>&1
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail sh -c "if [ -f files/fiscalization_dry_run.json ]; then echo PRESENT; else echo ABSENT; fi" > "%OUT%\05_fiscal_draft_state.txt" 2>&1

set "VERSION_OK=0"
findstr /I /C:"versionName=%EXPECTED_VERSION%" "%OUT%\02_package.txt" >nul 2>nul
if not errorlevel 1 set "VERSION_OK=1"

set "FINANCIAL_MARKER=0"
findstr /I /C:"PAYMENT_TX_ONCE" /C:"PAYMENT_CALL_BEGIN" /C:"PAYMENT_CALL_RESULT" "%OUT%\04_logcat.txt" >nul 2>nul
if not errorlevel 1 set "FINANCIAL_MARKER=1"

set "FISCAL_MARKER=0"
findstr /I /C:"PAYMENT_CONFIRMED draft=" /C:"cloud-fiscal/order/create" /C:"cloud-fiscal/order/getStatus" "%OUT%\04_logcat.txt" >nul 2>nul
if not errorlevel 1 set "FISCAL_MARKER=1"

set "DRAFT_PRESENT=0"
findstr /I /C:"PRESENT" "%OUT%\05_fiscal_draft_state.txt" >nul 2>nul
if not errorlevel 1 set "DRAFT_PRESENT=1"

if "%VERSION_OK%"=="0" (
  set "OUTCOME=WRONG_APP_VERSION"
) else if "%FINANCIAL_MARKER%"=="1" (
  set "OUTCOME=UNSAFE_FINANCIAL_MARKER_FOUND"
) else if "%FISCAL_MARKER%"=="1" (
  set "OUTCOME=UNEXPECTED_FISCAL_MARKER_FOUND"
) else if "%DRAFT_PRESENT%"=="1" (
  set "OUTCOME=UNEXPECTED_FISCAL_DRAFT_PRESENT"
) else (
  set "OUTCOME=SAFE_OK_NO_PAYMENT_NO_FISCAL_SEND"
)

(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo version_ok=%VERSION_OK%
  echo financial_marker_found=%FINANCIAL_MARKER%
  echo fiscal_marker_found=%FISCAL_MARKER%
  echo fiscal_draft_present=%DRAFT_PRESENT%
  echo real_pos_enabled=false
  echo.
  echo ===== RELEVANT LOGS =====
  findstr /I "IretailMachineMode IretailOrderDraft FiscalDryRun PAYMENT" "%OUT%\04_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [6/7] Creating ZIP...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[REPORT] '+$z)"
if errorlevel 1 (
  echo [ERROR] Could not create ZIP.
  pause
  exit /b 24
)

echo [7/7] Restoring stock Jetinno UI and publishing report...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell monkey -p com.jinuo.mhwang.jetinnocoffe -c android.intent.category.LAUNCHER 1 >nul 2>nul

if /I not "%OUTCOME%"=="SAFE_OK_NO_PAYMENT_NO_FISCAL_SEND" (
  echo [ERROR] Smoke test outcome is not safe-success: %OUTCOME%
  echo [ERROR] Report will NOT be auto-published until inspected manually.
  pause
  exit /b 30
)

call "%~dp0GIT_124_PUBLISH_FISCAL_SAFE_SMOKE.bat"
if errorlevel 1 (
  echo [ERROR] Safe report exists, but Git publication failed.
  pause
  exit /b 31
)

echo.
echo ============================================================
echo FISCAL SAFE SMOKE COMPLETE
echo Outcome: %OUTCOME%
echo Report published to Git.
echo ============================================================
pause
exit /b 0
