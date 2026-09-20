@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
set "TID=%~3"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"
if not defined TID set "TID=12000679"

echo ============================================================
echo i-Retail v0.5.22 - READ LAST MAIN-UI TRANSACTION
 echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo TID  : %TID%
echo.
echo SAFETY:
echo   This script sends NO PAYMENT, CANCEL, REFUND or reconciliation.
echo   It temporarily stops the main i-Retail UI only to release the AOA link,
echo   runs the existing read-only recovery client, then restores standalone UI.
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found in PATH.
  pause
  exit /b 2
)
adb -s "%JL22%" get-state >nul 2>nul
if errorlevel 1 (
  echo [ERROR] JL22 is not online: %JL22%
  pause
  exit /b 3
)
adb -s "%KOZEN%" get-state >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Kozen is not online: %KOZEN%
  pause
  exit /b 4
)

echo [1/4] Releasing the production AOA session. No financial command is sent...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
timeout /t 1 /nobreak >nul

echo [2/4] Running READ-ONLY SmartSkyPOS transaction recovery...
call AOA_16_LAST_TRANSACTION_RECOVERY.bat "%JL22%" "%KOZEN%" "%TID%"
set "RECOVERY_RC=%ERRORLEVEL%"

echo [3/4] Restoring production Kozen bridge and standalone i-Retail UI...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled true >nul 2>nul

echo [4/4] Recovery session finished.
echo.
echo ============================================================
echo READ-ONLY RECOVERY FINISHED. AOA_16 exit code: %RECOVERY_RC%
echo No new payment was initiated.
echo.
echo Publish the newest recovery archive with:
echo   call GIT_110_PUBLISH_MAIN_UI_RECOVERY_RESULT.bat
echo ============================================================
pause
exit /b %RECOVERY_RC%
