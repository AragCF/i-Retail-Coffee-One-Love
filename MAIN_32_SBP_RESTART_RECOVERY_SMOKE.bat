@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_VERSION="
for /f "tokens=2" %%V in ('findstr /C:"versionName " "app\build.gradle"') do if not defined EXPECTED_VERSION set "EXPECTED_VERSION=%%V"
set "EXPECTED_VERSION=%EXPECTED_VERSION:'=%"
if /I not "%EXPECTED_VERSION%"=="0.5.113-sbp-recovery-store" (
  echo [ERROR] Wrong project version: %EXPECTED_VERSION%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - SBP RESTART RECOVERY SMOKE
echo ============================================================
echo SAFETY:
echo   real POS remains FALSE
echo   no Kozen / AOA is needed
echo   no qrPayment / PAYMENT is sent
echo   QR payload must NOT survive process restart
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
echo [JL22] %JL22%

echo [1/8] Building...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 exit /b 20
set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APP_APK%" exit /b 21

echo [2/8] Installing...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 22

echo [3/8] Persisting safe Standalone and clearing OLD DRY-RUN recovery state...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
timeout /t 1 /nobreak >nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_recovery_clear_dryrun true >nul 2>nul
timeout /t 1 /nobreak >nul
adb -s "%JL22%" logcat -c

echo [4/8] Creating synthetic active SBP session...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_dry_run_self_test true >nul
if errorlevel 1 exit /b 23

set "PRE=%TEMP%\iretail_sbp_recovery_pre.log"
set "FOUND_QR=0"
for /l %%S in (1,1,60) do (
  adb -s "%JL22%" logcat -d -v brief SbpDryRun:V SbpRecovery:V *:S > "%PRE%" 2>&1
  findstr /C:"DRY_RUN_QR_READY" "%PRE%" >nul 2>nul
  if not errorlevel 1 (
    set "FOUND_QR=1"
    goto HAVE_QR
  )
  timeout /t 1 /nobreak >nul
)

:HAVE_QR
if "%FOUND_QR%"=="0" (
  echo [ERROR] Synthetic QR session was not created.
  type "%PRE%"
  pause
  exit /b 24
)

echo [5/8] Simulating process loss...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail
timeout /t 2 /nobreak >nul
adb -s "%JL22%" logcat -c

echo [6/8] Restarting and probing durable recovery...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_recovery_probe true >nul
if errorlevel 1 exit /b 25

set "POST=%TEMP%\iretail_sbp_recovery_post.log"
set "OUTCOME=RECOVERY_TIMEOUT"
for /l %%S in (1,1,60) do (
  adb -s "%JL22%" logcat -d -v brief SbpRecovery:V SbpDryRun:V *:S > "%POST%" 2>&1
  findstr /C:"RECOVERY_RESULT" "%POST%" >nul 2>nul
  if not errorlevel 1 (
    findstr /C:"found=true" "%POST%" >nul 2>nul
    if errorlevel 1 (
      set "OUTCOME=RECOVERY_NOT_FOUND"
      goto RECOVERY_DONE
    )
    findstr /C:"state=UNCERTAIN" "%POST%" >nul 2>nul
    if errorlevel 1 (
      set "OUTCOME=RECOVERY_NOT_UNCERTAIN"
      goto RECOVERY_DONE
    )
    findstr /C:"qrIdPresent=false" "%POST%" >nul 2>nul
    if errorlevel 1 (
      set "OUTCOME=QR_ID_LEAK"
      goto RECOVERY_DONE
    )
    findstr /C:"qrPayloadPresent=false" "%POST%" >nul 2>nul
    if errorlevel 1 (
      set "OUTCOME=QR_PAYLOAD_LEAK"
      goto RECOVERY_DONE
    )
    findstr /C:"realPaymentSent=false" "%POST%" >nul 2>nul
    if errorlevel 1 (
      set "OUTCOME=FINANCIAL_FLAG_UNEXPECTED"
      goto RECOVERY_DONE
    )
    findstr /C:"DRY_RUN_QR_READY" "%POST%" >nul 2>nul
    if not errorlevel 1 (
      set "OUTCOME=NEW_QR_AFTER_RESTART"
      goto RECOVERY_DONE
    )
    set "OUTCOME=RECOVERY_OK"
    goto RECOVERY_DONE
  )
  timeout /t 1 /nobreak >nul
)

:RECOVERY_DONE
echo [7/8] Clearing only synthetic dry-run recovery...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_recovery_clear_dryrun true >nul 2>nul
timeout /t 1 /nobreak >nul

echo [8/8] Restoring ordinary Standalone...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false >nul 2>nul

echo.
echo ===== PRE-RESTART =====
type "%PRE%"
echo.
echo ===== POST-RESTART =====
type "%POST%"
echo.
echo ============================================================
echo SBP RESTART RECOVERY SMOKE COMPLETE
echo Outcome: %OUTCOME%
echo No financial command was sent.
echo ============================================================
pause
if /I "%OUTCOME%"=="RECOVERY_OK" exit /b 0
exit /b 2
