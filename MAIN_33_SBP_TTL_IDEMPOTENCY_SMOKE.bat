@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_VERSION="
for /f "tokens=2" %%V in ('findstr /C:"versionName " "app\build.gradle"') do if not defined EXPECTED_VERSION set "EXPECTED_VERSION=%%V"
set "EXPECTED_VERSION=%EXPECTED_VERSION:'=%"
if /I not "%EXPECTED_VERSION%"=="0.5.114-sbp-expiry-idempotency" (
  echo [ERROR] Wrong project version: %EXPECTED_VERSION%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - SBP TTL / IDEMPOTENCY SMOKE
echo ============================================================
echo SAFETY:
echo   real POS remains FALSE
echo   no Kozen / AOA is needed
echo   no qrPayment / PAYMENT is sent
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 exit /b 12

set "JL22="
for /f "tokens=1,2,*" %%A in ('adb devices -l ^| findstr /I /C:"product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno"') do (
  if /I "%%B"=="device" if not defined JL22 set "JL22=%%A"
)
if not defined JL22 (
  echo [ERROR] Live JL22 not found.
  adb devices -l
  pause
  exit /b 13
)

echo [1/5] Building...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 exit /b 20
set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APP_APK%" exit /b 21

echo [2/5] Installing...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 22

echo [3/5] Persisting safe Standalone...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
timeout /t 1 /nobreak >nul
adb -s "%JL22%" logcat -c

echo [4/5] Running automatic SBP TTL/idempotency self-test...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_expiry_idempotency_self_test true >nul
if errorlevel 1 exit /b 23

set "LOG=%TEMP%\iretail_sbp_expiry_test.log"
set "OUTCOME=EXPIRY_TEST_TIMEOUT"
for /l %%S in (1,1,30) do (
  adb -s "%JL22%" logcat -d -v brief SbpExpiryTest:V *:S > "%LOG%" 2>&1
  findstr /C:"EXPIRY_TEST_RESULT" "%LOG%" >nul 2>nul
  if not errorlevel 1 (
    findstr /C:"sameBeforeExpiry=true" "%LOG%" >nul 2>nul
    if errorlevel 1 set "OUTCOME=IDEMPOTENCY_FAILED"
    if errorlevel 1 goto TEST_DONE
    findstr /C:"expired=true" "%LOG%" >nul 2>nul
    if errorlevel 1 set "OUTCOME=EXPIRY_FAILED"
    if errorlevel 1 goto TEST_DONE
    findstr /C:"confirmBlocked=true" "%LOG%" >nul 2>nul
    if errorlevel 1 set "OUTCOME=EXPIRED_CONFIRM_NOT_BLOCKED"
    if errorlevel 1 goto TEST_DONE
    findstr /C:"newAfterExpiry=true" "%LOG%" >nul 2>nul
    if errorlevel 1 set "OUTCOME=NEW_SESSION_FAILED"
    if errorlevel 1 goto TEST_DONE
    findstr /C:"realPaymentSent=false" "%LOG%" >nul 2>nul
    if errorlevel 1 set "OUTCOME=FINANCIAL_FLAG_UNEXPECTED"
    if errorlevel 1 goto TEST_DONE
    set "OUTCOME=EXPIRY_TEST_OK"
    goto TEST_DONE
  )
  timeout /t 1 /nobreak >nul
)

:TEST_DONE
echo [5/5] Restoring ordinary Standalone...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false >nul 2>nul

echo.
type "%LOG%"
echo.
echo ============================================================
echo SBP TTL / IDEMPOTENCY SMOKE COMPLETE
echo Outcome: %OUTCOME%
echo No financial command was sent.
echo ============================================================
pause
if /I "%OUTCOME%"=="EXPIRY_TEST_OK" exit /b 0
exit /b 2
