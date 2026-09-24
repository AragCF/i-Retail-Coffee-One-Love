@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_VERSION="
for /f "tokens=2" %%V in ('findstr /C:"versionName " "app\build.gradle"') do if not defined EXPECTED_VERSION set "EXPECTED_VERSION=%%V"
set "EXPECTED_VERSION=%EXPECTED_VERSION:'=%"
if /I not "%EXPECTED_VERSION%"=="0.5.111-sbp-session-contract" (
  echo [ERROR] Wrong project version: %EXPECTED_VERSION%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - SBP SESSION RECOVERY TEST
echo ============================================================
echo SAFETY:
echo   real POS remains FALSE
echo   no SmartSkyPOS qrPayment is called
echo   synthetic QR only
echo   app restart must recover the SAME session
echo ============================================================
echo.

where adb >nul 2>nul || exit /b 12

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

echo [1/7] Building...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 exit /b 20
set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APP_APK%" exit /b 21

echo [2/7] Installing...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 22

echo [3/7] Resetting ONLY previous SBP dry-run test state...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail rm -f shared_prefs/iretail_sbp_session_v1.xml >nul 2>nul
adb -s "%JL22%" logcat -c
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
timeout /t 1 /nobreak >nul

echo [4/7] Creating one synthetic SBP session...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_dry_run_self_test true >nul
if errorlevel 1 exit /b 23
timeout /t 2 /nobreak >nul

set "BEFORE=%TEMP%\iretail_sbp_before.log"
adb -s "%JL22%" logcat -d -v brief SbpDryRun:V *:S > "%BEFORE%" 2>&1
findstr /C:"DRY_RUN_QR_READY" "%BEFORE%" >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Initial synthetic QR session was not created.
  type "%BEFORE%"
  pause
  exit /b 24
)

set "SESSION_BEFORE="
for /f "tokens=2 delims==" %%S in ('findstr /C:"DRY_RUN_QR_READY" "%BEFORE%" ^| powershell -NoProfile -Command "$input | %% { if ($_ -match 'session=([^ ]+)') { $matches[1] } }"') do if not defined SESSION_BEFORE set "SESSION_BEFORE=%%S"
if not defined SESSION_BEFORE (
  for /f "delims=" %%S in ('powershell -NoProfile -Command "$x=Get-Content -Raw '%BEFORE%'; if($x -match 'DRY_RUN_QR_READY[^\r\n]*session=([^ ]+)'){ $matches[1] }"') do if not defined SESSION_BEFORE set "SESSION_BEFORE=%%S"
)
if not defined SESSION_BEFORE (
  echo [ERROR] Could not parse initial session id.
  type "%BEFORE%"
  pause
  exit /b 25
)
echo [OK] Initial session: %SESSION_BEFORE%

echo [5/7] Simulating application process restart...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
timeout /t 1 /nobreak >nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_dry_run_self_test true >nul
if errorlevel 1 exit /b 26
timeout /t 2 /nobreak >nul

set "AFTER=%TEMP%\iretail_sbp_after.log"
adb -s "%JL22%" logcat -d -v brief SbpDryRun:V *:S > "%AFTER%" 2>&1
findstr /C:"DRY_RUN_RECOVERED" "%AFTER%" >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Session was not recovered after restart.
  type "%AFTER%"
  pause
  exit /b 27
)

set "SESSION_AFTER="
for /f "delims=" %%S in ('powershell -NoProfile -Command "$x=Get-Content -Raw '%AFTER%'; if($x -match 'DRY_RUN_RECOVERED[^\r\n]*session=([^ ]+)'){ $matches[1] }"') do if not defined SESSION_AFTER set "SESSION_AFTER=%%S"
if not defined SESSION_AFTER (
  echo [ERROR] Could not parse recovered session id.
  pause
  exit /b 28
)

echo [OK] Recovered session: %SESSION_AFTER%
if /I not "%SESSION_BEFORE%"=="%SESSION_AFTER%" (
  echo [ERROR] Session changed after restart.
  pause
  exit /b 29
)

echo [6/7] Verifying no second QR generation and no financial markers...
powershell -NoProfile -Command "$x=Get-Content -Raw '%AFTER%'; $n=([regex]::Matches($x,'DRY_RUN_QR_READY')).Count; if($n -ne 1){ Write-Host ('[ERROR] QR_READY count='+$n); exit 30 } else { Write-Host '[OK] Exactly one QR_READY across restart' }"
if errorlevel 1 (
  pause
  exit /b 30
)
findstr /I /C:"realQrPaymentSent=true" /C:"PAYMENT_TX_ONCE" /C:"qrPayment called" "%AFTER%" >nul 2>nul
if not errorlevel 1 (
  echo [ERROR] Financial marker found in SBP recovery test.
  type "%AFTER%"
  pause
  exit /b 31
)

echo [7/7] Cleaning synthetic test state and restoring Standalone...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail rm -f shared_prefs/iretail_sbp_session_v1.xml >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false >nul 2>nul

echo.
echo ============================================================
echo SBP SESSION RECOVERY TEST PASSED
echo Same session survived process restart.
echo No real financial command was sent.
echo ============================================================
pause
exit /b 0
