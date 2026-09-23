@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_VERSION="
for /f "tokens=2" %%V in ('findstr /C:"versionName " "app\build.gradle"') do if not defined EXPECTED_VERSION set "EXPECTED_VERSION=%%V"
set "EXPECTED_VERSION=%EXPECTED_VERSION:'=%"
if /I not "%EXPECTED_VERSION%"=="0.5.98-fiscal-positive-payment-test" (
  echo [ERROR] Wrong project version: %EXPECTED_VERSION%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - ONE REAL CARD PAYMENT, 1.00 RUB
echo ============================================================
echo AUTHORIZED CONTRACT: S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1
echo.
echo EXACTLY ONE PAYMENT ATTEMPT IS ALLOWED.
echo Windows NEVER sends PAYMENT. Only one tap in the main i-Retail UI may do it.
echo Real POS is runtime-only and is persisted FALSE before and after the test.
echo No cloud fiscal request, no order/synchronize, no brewing.
echo ============================================================
echo.

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

set "JL22="
for /f "tokens=1,2,*" %%A in ('adb devices -l ^| findstr /I /C:"product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno"') do (
  if /I "%%B"=="device" if not defined JL22 set "JL22=%%A"
)
if not defined JL22 (
  echo [ERROR] Live JL22 not found.
  adb devices -l
  pause
  exit /b 15
)

set "KOZEN=%~1"
if not defined KOZEN (
  adb connect 192.168.31.134:5555 >nul 2>nul
  adb -s "192.168.31.134:5555" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
  if not errorlevel 1 set "KOZEN=192.168.31.134:5555"
)
if not defined KOZEN (
  for /f "tokens=1,2,*" %%A in ('adb devices -l') do (
    if /I "%%B"=="device" if /I not "%%A"=="%JL22%" if not defined KOZEN (
      adb -s "%%A" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
      if not errorlevel 1 set "KOZEN=%%A"
    )
  )
)
if not defined KOZEN (
  echo [ERROR] Kozen P12 ADB target not found.
  echo [HINT] Run this script with Kozen ADB serial/address as the first argument.
  adb devices -l
  pause
  exit /b 16
)

adb -s "%KOZEN%" get-state >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Kozen is not online: %KOZEN%
  pause
  exit /b 17
)

set "LOCAL_CONSUMED=fiscal_positive_payment_logs\FISCAL_POSITIVE_PAYMENT_v1_0_1_CONSUMED.marker"
if exist "%LOCAL_CONSUMED%" (
  echo [ERROR] The authorized financial attempt was already consumed on this workstation.
  echo [ERROR] A second PAYMENT is forbidden without new explicit approval.
  pause
  exit /b 18
)

echo [JL22] detected
echo [KOZEN] detected

echo [1/10] Building current debug APK...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 (
  echo [ERROR] Main APK build failed.
  pause
  exit /b 20
)

set "GRADLE_CMD="
if exist "gradlew.bat" set "GRADLE_CMD=%CD%\gradlew.bat"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD (
  echo [ERROR] Gradle was not found for kozenBridge build.
  pause
  exit /b 21
)

echo [2/10] Building Kozen production bridge...
call "%GRADLE_CMD%" --no-daemon --stacktrace :kozenBridge:assembleDebug
if errorlevel 1 (
  echo [ERROR] Kozen bridge build failed.
  pause
  exit /b 22
)

set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
if not exist "%APP_APK%" exit /b 23
if not exist "%KOZEN_APK%" exit /b 24

echo [3/10] Installing APKs...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 25
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 exit /b 26

set "CHECK_FILE=%TEMP%\iretail_positive_payment_check.txt"
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail ls files/fiscal_positive_payment_test_v1_0_1.attempt > "%CHECK_FILE%" 2>nul
findstr /C:"fiscal_positive_payment_test_v1_0_1.attempt" "%CHECK_FILE%" >nul 2>nul
if not errorlevel 1 (
  echo [ERROR] Android one-attempt marker already exists. Repeat is forbidden.
  pause
  exit /b 27
)

adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_jl22_kozen_payment_v1.xml > "%CHECK_FILE%" 2>nul
findstr /C:"unresolved_request_id" "%CHECK_FILE%" >nul 2>nul
if not errorlevel 1 (
  echo [ERROR] Previous unresolved payment marker exists on JL22.
  echo [ERROR] New PAYMENT is forbidden until read-only recovery is completed.
  pause
  exit /b 28
)

echo [4/10] Persisting safe STANDALONE baseline with real POS FALSE...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul
if errorlevel 1 exit /b 29
timeout /t 1 /nobreak >nul

echo [5/10] Starting Kozen bridge and clearing old evidence...
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul
if errorlevel 1 exit /b 30
adb -s "%JL22%" logcat -c
adb -s "%KOZEN%" logcat -c
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail rm -f files/fiscalization_dry_run.json >nul 2>nul

echo [6/10] Starting controlled 1.00 RUB test UI...
rem IMPORTANT: real_pos_enabled=true is runtime-only. It is intentionally NOT persisted.
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled true --ez fiscal_positive_payment_test true >nul
if errorlevel 1 goto FAIL_SAFE

set "WAIT_LOG=%TEMP%\iretail_positive_payment_wait.log"
set "READY=0"
for /l %%S in (1,1,20) do (
  adb -s "%JL22%" logcat -d -v brief FiscalPositivePaymentTest:I *:S > "%WAIT_LOG%" 2>&1
  findstr /C:"TEST_MODE_READY productId=s3-fiscal-positive-test-1rub amountMinor=100 realPos=true persistedRealPos=false" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 goto TEST_READY
  timeout /t 1 /nobreak >nul
)
goto FAIL_SAFE

:TEST_READY
set "READY=1"
echo.
echo ============================================================
echo USE THE COFFEE-MACHINE SCREEN NOW
echo ============================================================
echo 1. Tap: S3 TEST PRODUCT 1 RUB.
echo 2. Add it to the cart. Do not use modifiers.
echo 3. Open payment and tap BANK CARD EXACTLY ONCE.
echo 4. Present one card to Kozen when requested.
echo.
echo Do not tap BANK CARD a second time under any outcome.
echo The script will stop real POS automatically after the result.
echo ============================================================
echo.

set "OUTCOME=NO_ATTEMPT_TIMEOUT"
echo [7/10] Waiting up to 10 minutes for the one authorized UI attempt...
for /l %%S in (1,1,600) do (
  adb -s "%JL22%" logcat -d -v brief FiscalPositivePaymentTest:I IretailKozenClient:I IretailKozenClient:W IretailKozenClient:E *:S > "%WAIT_LOG%" 2>&1
  findstr /C:"ATTEMPT_CLAIMED amountMinor=100 productId=s3-fiscal-positive-test-1rub" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 goto ATTEMPT_STARTED
  timeout /t 1 /nobreak >nul
)
goto DISABLE_POS

:ATTEMPT_STARTED
if not exist "fiscal_positive_payment_logs" mkdir "fiscal_positive_payment_logs"
> "%LOCAL_CONSUMED%" echo contract=S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1
>> "%LOCAL_CONSUMED%" echo consumed=true
>> "%LOCAL_CONSUMED%" echo amount_minor=100

echo [INFO] Authorized attempt claimed. Repeat is now permanently blocked for this contract.
set "OUTCOME=PAYMENT_RESULT_TIMEOUT_UNCERTAIN"
for /l %%S in (1,1,190) do (
  adb -s "%JL22%" logcat -d -v brief FiscalPositivePaymentTest:I IretailKozenClient:I IretailKozenClient:W IretailKozenClient:E FiscalGateway:I FiscalGateway:E *:S > "%WAIT_LOG%" 2>&1
  findstr /C:"TEST_RESULT status=APPROVED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 goto APPROVED
  findstr /C:"TEST_RESULT status=DECLINED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 goto DECLINED
  findstr /C:"TEST_RESULT status=UNCERTAIN" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 goto UNCERTAIN
  findstr /C:"TEST_RESULT status=FAILED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 goto FAILED
  findstr /C:"TEST_RESULT status=BLOCKED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 goto BLOCKED
  timeout /t 1 /nobreak >nul
)
goto DISABLE_POS

:APPROVED
set "OUTCOME=PAYMENT_APPROVED_FISCAL_MISSING"
echo [INFO] APPROVED received. Waiting for local FiscalGateway DRY_RUN...
for /l %%S in (1,1,20) do (
  adb -s "%JL22%" logcat -d -v brief FiscalPositivePaymentTest:I FiscalGateway:I FiscalGateway:E *:S > "%WAIT_LOG%" 2>&1
  findstr /C:"FISCAL_RESULT state=DRAFT_READY sendAllowed=false amountMinor=100 productId=s3-fiscal-positive-test-1rub" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=PAYMENT_APPROVED_FISCAL_READY"
    goto DISABLE_POS
  )
  timeout /t 1 /nobreak >nul
)
goto DISABLE_POS

:DECLINED
set "OUTCOME=PAYMENT_DECLINED"
goto DISABLE_POS

:UNCERTAIN
set "OUTCOME=PAYMENT_UNCERTAIN"
goto DISABLE_POS

:FAILED
set "OUTCOME=PAYMENT_FAILED"
goto DISABLE_POS

:BLOCKED
set "OUTCOME=PAYMENT_BLOCKED"
goto DISABLE_POS

:FAIL_SAFE
set "OUTCOME=TEST_SETUP_FAILED"
echo [ERROR] Controlled test mode did not become ready.

:DISABLE_POS
echo [8/10] Forcing persisted STANDALONE + real POS FALSE...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
timeout /t 1 /nobreak >nul

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "fiscal_positive_payment_logs" mkdir "fiscal_positive_payment_logs"
set "OUT=fiscal_positive_payment_logs\FISCAL_POSITIVE_PAYMENT_1RUB_%TS%"
mkdir "%OUT%"

echo [9/10] Collecting and sanitizing evidence...
(
  echo expected_version=%EXPECTED_VERSION%
  echo contract=S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1
  echo outcome=%OUTCOME%
  echo test_amount_minor=100
  echo test_product_id=s3-fiscal-positive-test-1rub
  echo windows_sends_payment=false
  echo cloud_fiscal_sent=false
  echo order_sync_sent=false
  echo brewing_started=false
) > "%OUT%\01_environment.txt"

adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail 2>nul | findstr /I "versionName= versionCode=" > "%OUT%\02_package.txt"
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_machine_mode_v1.xml > "%OUT%\03_machine_mode.txt" 2>&1
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat files/fiscal_positive_payment_test_v1_0_1.attempt > "%OUT%\04_attempt_marker.txt" 2>nul
adb -s "%JL22%" logcat -d -v threadtime FiscalPositivePaymentTest:I IretailKozenClient:I IretailKozenClient:W IretailKozenClient:E FiscalGateway:I FiscalGateway:E IretailMachineMode:I AndroidRuntime:E *:S > "%OUT%\RAW_jl22_logcat.txt" 2>&1
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:I IretailKozenBridge:W IretailKozenBridge:E AndroidRuntime:E *:S > "%OUT%\RAW_kozen_logcat.txt" 2>&1
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat files/fiscalization_dry_run.json > "%OUT%\07_fiscalization_dry_run.json" 2>nul
(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo one_authorized_attempt_only=true
  echo repeat_allowed=false
  echo persisted_real_pos_expected=false
) > "%OUT%\08_summary.txt"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Sanitize-FiscalPositivePaymentReport.ps1" -RawJl22 "%CD%\%OUT%\RAW_jl22_logcat.txt" -RawKozen "%CD%\%OUT%\RAW_kozen_logcat.txt" -ReportDir "%CD%\%OUT%"
if errorlevel 1 (
  echo [ERROR] Safety scan failed. Nothing will be published.
  pause
  exit /b 40
)

set "VALIDATION_OK=1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Assert-FiscalPositivePayment1Rub.ps1" -ReportDir "%CD%\%OUT%" -ExpectedVersion "%EXPECTED_VERSION%" -Outcome "%OUTCOME%"
if errorlevel 1 set "VALIDATION_OK=0"

echo [10/10] Creating safe archive and publishing evidence...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[REPORT] '+$z)"
if errorlevel 1 exit /b 41

> "%OUT%.zip.safe.txt" echo SAFETY_SCAN_OK
>> "%OUT%.zip.safe.txt" echo contract=S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1
>> "%OUT%.zip.safe.txt" echo outcome=%OUTCOME%

call "%~dp0GIT_126_PUBLISH_FISCAL_POSITIVE_PAYMENT_1RUB.bat"
if errorlevel 1 (
  echo [ERROR] Safe report exists, but Git publication failed.
  pause
  exit /b 42
)

echo.
echo ============================================================
echo CONTROLLED PAYMENT TEST COMPLETE
echo Outcome: %OUTCOME%
echo persisted real POS: FALSE
echo repeat under this contract: FORBIDDEN after an attempt marker
echo ============================================================

if "%VALIDATION_OK%"=="0" (
  echo [INFO] Evidence was safely published for analysis, but positive acceptance did not pass.
  pause
  exit /b 43
)

echo [SUCCESS] APPROVED -^> PAID -^> FiscalGateway DRAFT_READY proved for 1.00 RUB.
pause
exit /b 0
