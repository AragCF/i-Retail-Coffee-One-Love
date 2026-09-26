@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_VERSION="
for /f "tokens=2" %%V in ('findstr /C:"versionName " "app\build.gradle"') do if not defined EXPECTED_VERSION set "EXPECTED_VERSION=%%V"
set "EXPECTED_VERSION=%EXPECTED_VERSION:'=%"
if /I not "%EXPECTED_VERSION%"=="0.5.128-device-binding" (
  echo [ERROR] Wrong project version: %EXPECTED_VERSION%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - SBP DRY RUN UI
echo ============================================================
echo SAFETY:
echo   real POS remains FALSE
echo   real SmartSkyPOS qrPayment is NOT called
echo   RuntimeOrder is NOT marked PAID
echo   FiscalGateway and coffee preparation are NOT called
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found in PATH.
  pause
  exit /b 12
)

set "JL22="
call "%~dp0tools\WAIT_FOR_JL22.bat" JL22
if errorlevel 1 exit /b 13

echo [1/5] Building i-Retail...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 exit /b 20

set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APP_APK%" exit /b 21

echo [2/5] Installing i-Retail on JL22...
call "%~dp0tools\WAIT_FOR_JL22.bat" JL22
if errorlevel 1 exit /b 13
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 22

echo [3/5] Persisting safe STANDALONE + real POS FALSE...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
timeout /t 1 /nobreak >nul

rem Start the diagnostic from a fresh Android process. This makes Android 6 class loading
rem deterministic and still preserves the durable SBP session in SharedPreferences.
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
timeout /t 1 /nobreak >nul
adb -s "%JL22%" logcat -c

echo [4/5] Starting SBP DRY RUN...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_dry_run_self_test true >nul
if errorlevel 1 exit /b 23

echo.
echo ============================================================
echo USE THE COFFEE-MACHINE SCREEN NOW
echo Phase 1:
echo   If the QR screen is shown, scan the QR and tap the QR area.
echo   The decoded text must begin with SBP-DRY-RUN.
echo Phase 2:
echo   When "QR scanned" / confirmation is shown, tap the central
echo   confirmation area once.
echo.
echo If an earlier session is recovered already in WAITING state,
echo Phase 1 is skipped automatically and you only confirm Phase 2.
echo No payment and no bank authorization are needed.
echo ============================================================
echo.

set "WAIT_LOG=%TEMP%\iretail_sbp_dryrun_wait.log"
set "OUTCOME=DRY_RUN_QR_TIMEOUT"

echo [WAIT 1/2] Waiting up to 180 seconds for QR scan/tap...
for /l %%S in (1,1,180) do (
  adb -s "%JL22%" logcat -d -v brief SbpDryRun:V IretailMachineMode:I FiscalGateway:V AndroidRuntime:E *:S > "%WAIT_LOG%" 2>&1
  findstr /C:"DRY_RUN_CONFIRMED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=DRY_RUN_OK"
    goto DRY_DONE
  )
  findstr /C:"DRY_RUN_QR_SCANNED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 goto WAIT_CONFIRM
  findstr /R /C:"DRY_RUN_RECOVERED .* state=WAITING " "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 goto WAIT_CONFIRM
  findstr /C:"DRY_RUN_REJECTED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=DRY_RUN_REJECTED"
    goto DRY_DONE
  )
  findstr /C:"FATAL EXCEPTION:" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=DRY_RUN_CRASH"
    goto DRY_DONE
  )
  findstr /C:"NoClassDefFoundError" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=DRY_RUN_CRASH"
    goto DRY_DONE
  )
  timeout /t 1 /nobreak >nul
)
goto DRY_DONE

:WAIT_CONFIRM
echo.
echo [WAIT 2/2] QR scan/tap accepted.
echo [WAIT 2/2] You now have a fresh 180 seconds to tap the confirmation area.
set "OUTCOME=DRY_RUN_CONFIRM_TIMEOUT"
for /l %%S in (1,1,180) do (
  adb -s "%JL22%" logcat -d -v brief SbpDryRun:V IretailMachineMode:I FiscalGateway:V AndroidRuntime:E *:S > "%WAIT_LOG%" 2>&1
  findstr /C:"DRY_RUN_CONFIRMED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=DRY_RUN_OK"
    goto DRY_DONE
  )
  findstr /C:"DRY_RUN_REJECTED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=DRY_RUN_REJECTED"
    goto DRY_DONE
  )
  findstr /C:"FATAL EXCEPTION:" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=DRY_RUN_CRASH"
    goto DRY_DONE
  )
  findstr /C:"NoClassDefFoundError" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=DRY_RUN_CRASH"
    goto DRY_DONE
  )
  timeout /t 1 /nobreak >nul
)

:DRY_DONE
echo [5/5] Restoring ordinary Standalone...
call "%~dp0tools\WAIT_FOR_JL22.bat" JL22
if errorlevel 1 exit /b 13
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false >nul 2>nul
adb -s "%JL22%" logcat -d -v threadtime SbpDryRun:V IretailMachineMode:I FiscalGateway:V AndroidRuntime:E *:S

echo.
echo ============================================================
echo SBP DRY RUN COMPLETE
echo Outcome: %OUTCOME%
echo No financial command was sent.
echo ============================================================
pause
if /I "%OUTCOME%"=="DRY_RUN_OK" exit /b 0
exit /b 2
