@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.91-fiscal-positive-dryrun-selftest"
set "EXPECTED_VERSION=0.5.91-fiscal-positive-dryrun-selftest"
set "JL22="

echo ============================================================
echo i-Retail v0.5.91 - FISCAL POSITIVE DRY_RUN SELF-TEST
echo ============================================================
echo.
echo NO FINANCIAL OPERATION:
echo   - real_pos_enabled remains false;
echo   - Kozen is not used;
echo   - no PAYMENT command is sent;
echo   - no cloud-fiscal request is sent;
echo   - no order/synchronize request is sent;
echo   - a synthetic PAID order is passed only to DryRunFiscalGateway.
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

for /f "tokens=1,2,*" %%A in ('adb devices -l ^| findstr /I /C:"product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno"') do (
  if /I "%%B"=="device" if not defined JL22 set "JL22=%%A"
)

if not defined JL22 (
  echo [ERROR] Live JL22 not found.
  adb devices -l
  pause
  exit /b 15
)

echo [JL22] %JL22%

echo [1/7] Building current debug APK...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 (
  echo [ERROR] Build failed.
  pause
  exit /b 20
)

set "APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APK%" (
  echo [ERROR] APK not found: %APK%
  pause
  exit /b 21
)

echo [2/7] Installing current i-Retail APK...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" install -r "%APK%"
if errorlevel 1 (
  echo [ERROR] APK install failed.
  pause
  exit /b 22
)

echo [3/7] Persisting STANDALONE with real POS disabled...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul
if errorlevel 1 (
  echo [ERROR] Could not persist safe standalone mode.
  pause
  exit /b 23
)
timeout /t 1 /nobreak >nul

echo [4/7] Clearing previous self-test evidence and running positive FiscalGateway DRY_RUN...
adb -s "%JL22%" logcat -c
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail rm -f files/fiscalization_dry_run.json >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --ez fiscal_dry_run_self_test true >nul
if errorlevel 1 (
  echo [ERROR] Could not launch self-test.
  pause
  exit /b 24
)
timeout /t 3 /nobreak >nul

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
set "OUT=fiscal_dryrun_selftest_logs\FISCAL_DRYRUN_SELFTEST_%TS%"
if not exist "fiscal_dryrun_selftest_logs" mkdir "fiscal_dryrun_selftest_logs"
mkdir "%OUT%"

echo [5/7] Collecting local-only evidence...
adb devices -l > "%OUT%\01_adb_devices.txt" 2>&1
adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail > "%OUT%\02_package.txt" 2>&1
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_machine_mode_v1.xml > "%OUT%\03_machine_mode.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime FiscalGatewaySelfTest:I FiscalGateway:I FiscalDryRun:I IretailMachineMode:I IretailKozenClient:W AndroidRuntime:E *:S > "%OUT%\04_logcat.txt" 2>&1
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat files/fiscalization_dry_run.json > "%OUT%\05_fiscalization_dry_run.json" 2>&1

echo [6/7] Validating positive DRY_RUN invariants...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Assert-FiscalDryRunSelfTest.ps1" -ReportDir "%CD%\%OUT%" -ExpectedVersion "%EXPECTED_VERSION%"
if errorlevel 1 (
  echo [ERROR] Fiscal DRY_RUN self-test validation failed.
  echo [ERROR] No report will be published automatically.
  pause
  exit /b 30
)

(
  echo ===== OUTCOME =====
  echo FISCAL_DRYRUN_SELFTEST_OK
  echo.
  echo machine_mode=standalone
  echo real_pos_enabled=false
  echo payment_sent=false
  echo fiscal_network_sent=false
  echo order_sync_sent=false
  echo synthetic_amount=10.00
  echo products=1
  echo fiscal_gateway_state=DRAFT_READY
) > "%OUT%\SUMMARY.txt"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[REPORT] '+$z)"
if errorlevel 1 (
  echo [ERROR] ZIP creation failed.
  pause
  exit /b 31
)

echo [7/7] Publishing safe report to Git...
call "%~dp0GIT_125_PUBLISH_FISCAL_DRYRUN_SELFTEST.bat"
if errorlevel 1 (
  echo [ERROR] Self-test passed, but publication failed.
  pause
  exit /b 32
)

echo.
echo ============================================================
echo FISCAL POSITIVE DRY_RUN SELF-TEST COMPLETE
echo Outcome: FISCAL_DRYRUN_SELFTEST_OK
echo i-Retail remains active in STANDALONE; real POS remains disabled.
echo ============================================================
pause
exit /b 0
