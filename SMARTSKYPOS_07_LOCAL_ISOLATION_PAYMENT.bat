@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"

set "OUTCOME=WAITING_FOR_OPERATOR"
set "WAITLOG=%TEMP%\iretail_smartsky_local_isolation.log"

echo ============================================================
echo SmartSkyPOS KOZEN-LOCAL ISOLATION PAYMENT - 1.00 RUB
echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo.
echo PURPOSE:
echo   Isolate SmartSkyPOS/acquiring from JL22 + USB/AOA + Payment Bridge.
echo.
echo SAFETY:
echo   - THIS Windows script does NOT send payment() itself.
echo   - Payment can start ONLY after your taps on the Kozen screen.
echo   - Amount is fixed to 1.00 RUB.
echo   - Tap the payment button ONCE and confirm ONCE.
echo   - There is no automatic payment retry.
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

set "SDK_PATH="
if defined ANDROID_HOME set "SDK_PATH=%ANDROID_HOME%"
if not defined SDK_PATH if defined ANDROID_SDK_ROOT set "SDK_PATH=%ANDROID_SDK_ROOT%"
if not defined SDK_PATH if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_PATH=%LOCALAPPDATA%\Android\Sdk"
if not defined SDK_PATH (
  echo [ERROR] Android SDK was not found.
  pause
  exit /b 5
)
set "SDK_PATH_GRADLE=%SDK_PATH:\=/%"
> local.properties echo sdk.dir=%SDK_PATH_GRADLE%

set "GRADLE_CMD="
if exist "gradlew.bat" set "GRADLE_CMD=%CD%\gradlew.bat"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD (
  echo [ERROR] Gradle was not found.
  pause
  exit /b 6
)

echo [1/9] Building the existing typed SmartSkyPOS diagnostic app...
call "%GRADLE_CMD%" --no-daemon --stacktrace :app:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed. No payment was sent.
  pause
  exit /b 7
)

set "APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APK%" (
  echo [ERROR] APK not found: %APK%
  pause
  exit /b 8
)

echo [2/9] Releasing production payment path so it cannot interfere...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul

echo [3/9] Installing diagnostic app directly on Kozen...
adb -s "%KOZEN%" install -r "%APK%"
if errorlevel 1 (
  echo [ERROR] Kozen diagnostic APK installation failed.
  goto RESTORE_ERROR
)

echo [4/9] Clearing Kozen diagnostic logs and opening LOCAL SmartSkyPOS payment screen...
adb -s "%KOZEN%" logcat -c
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail/.pos.SmartSkyPosDiagnosticActivity --ez allow_payment true --es amount 1.00
if errorlevel 1 (
  echo [ERROR] Could not start SmartSkyPosDiagnosticActivity on Kozen.
  goto RESTORE_ERROR
)

echo.
echo ============================================================
echo USE ONLY THE KOZEN SCREEN NOW
echo ============================================================
echo Wait until the diagnostic screen shows READY(0) and Gate: OPEN.
echo 1. Select 1 RUB.
echo 2. Tap: VYPOLNIT TESTOVUYU OPLATU / test payment.
echo 3. Confirm the dialog exactly ONCE.
echo 4. Present the SAME card to Kozen when requested.
echo.
echo This call is LOCAL on Kozen:
echo   diagnostic Activity - SmartSkyPOS Binder - acquiring.
echo JL22/AOA/production bridge do not participate in the payment.
echo.
echo Do not press keys here. Waiting up to 10 minutes for PAYMENT_RESULT...
echo ============================================================
echo.

for /l %%S in (1,1,600) do (
  adb -s "%KOZEN%" logcat -d -v brief SmartSkyPOSDiag:V *:S > "%WAITLOG%" 2>&1
  findstr /C:"PAYMENT_RESULT" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 goto RESULT_SEEN
  findstr /C:"PAYMENT_REMOTE_EXCEPTION" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 goto LOCAL_ERROR
  findstr /C:"PAYMENT_EXCEPTION" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 goto LOCAL_ERROR
  timeout /t 1 /nobreak >nul
)
set "OUTCOME=LOCAL_RESULT_TIMEOUT"
echo [TIMEOUT] No final LOCAL PAYMENT_RESULT was seen.
echo IMPORTANT: do not start another payment until this archive is inspected.
goto COLLECT

:RESULT_SEEN
findstr /C:"PAYMENT_RESULT" "%WAITLOG%" | findstr /C:"approved=true" >nul 2>nul
if not errorlevel 1 (
  findstr /C:"PAYMENT_RESULT" "%WAITLOG%" | findstr /C:"code=0" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=LOCAL_APPROVED"
    echo [SUCCESS] Kozen-local typed SmartSkyPOS payment was APPROVED.
    goto READ_BACK
  )
)
findstr /C:"PAYMENT_RESULT" "%WAITLOG%" | findstr /C:"approved=false" >nul 2>nul
if not errorlevel 1 (
  set "OUTCOME=LOCAL_DECLINED"
  echo [DECLINED] Kozen-local typed SmartSkyPOS payment was declined.
  goto READ_BACK
)
set "OUTCOME=LOCAL_FINAL_NOT_APPROVED"
echo [INFO] A final local result was returned, but it is not an approval.
goto READ_BACK

:LOCAL_ERROR
set "OUTCOME=LOCAL_PAYMENT_EXCEPTION"
echo [ERROR] Local SmartSkyPOS payment path reported an exception.
goto COLLECT

:READ_BACK
echo [5/9] Reading the last transaction locally after the final result...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail/.pos.SmartSkyPosLastTransactionActivity >nul 2>nul
timeout /t 3 /nobreak >nul

goto COLLECT

:COLLECT
set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "smartskypos_local_logs" mkdir "smartskypos_local_logs"
set "OUT=smartskypos_local_logs\SMARTSKYPOS_LOCAL_ISOLATION_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo kozen=%KOZEN%
  echo timestamp=%TS%
  echo outcome=%OUTCOME%
  echo amount=1.00
  echo currency=643
  echo initiator=OPERATOR_ON_KOZEN_DIAGNOSTIC_UI
  echo windows_script_sends_payment=false
  echo path=KOZEN_LOCAL_TYPED_SDK_BINDER
  echo bypasses=JL22_USB_AOA_PRODUCTION_BRIDGE_MAIN_UI
) > "%OUT%\00_info.txt"

echo [6/9] Collecting local SmartSkyPOS evidence...
adb -s "%KOZEN%" logcat -d -v threadtime SmartSkyPOSDiag:V SmartSkyPOSLastTx:V AndroidRuntime:E ActivityManager:I *:S > "%OUT%\01_local_payment_logcat.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.skytech.smartskypos > "%OUT%\02_smartskypos_package.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity services com.skytech.smartskypos > "%OUT%\03_smartskypos_services.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity services com.pos.service > "%OUT%\04_pos_services.txt" 2>&1
(
  adb -s "%KOZEN%" shell date
  adb -s "%KOZEN%" shell getprop persist.sys.timezone
  adb -s "%KOZEN%" shell ip addr
  adb -s "%KOZEN%" shell ip route
  adb -s "%KOZEN%" shell ping -c 3 185.162.94.67
) > "%OUT%\05_network_time.txt" 2>&1

(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo ===== DIRECT KOZEN SMARTSKYPOS =====
  findstr /I "BIND_OK CALLBACK_REGISTERED GET_STATE TERMINAL_DATA PAYMENT_GATE PAYMENT_REQUEST PAYMENT_RESULT PAYMENT_REMOTE_EXCEPTION PAYMENT_EXCEPTION" "%OUT%\01_local_payment_logcat.txt"
  echo.
  echo ===== LAST TRANSACTION READBACK =====
  findstr /I "LAST TRANSACTION approved code rc rrn receipt amount terminal" "%OUT%\01_local_payment_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [7/9] Closing Kozen diagnostic activity...
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul

echo [8/9] Restoring production Kozen bridge and standalone i-Retail UI...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled true >nul 2>nul

echo [9/9] Creating evidence archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo KOZEN-LOCAL ISOLATION TEST COMPLETE. Outcome: %OUTCOME%
echo The Windows script itself sent NO payment command.
echo Publish with:
echo   call GIT_111_PUBLISH_SMARTSKYPOS_LOCAL_RESULT.bat
echo ============================================================
if /I "%OUTCOME%"=="LOCAL_RESULT_TIMEOUT" echo IMPORTANT: DO NOT START ANOTHER PAYMENT.
pause
exit /b 0

:RESTORE_ERROR
set "OUTCOME=SETUP_ERROR_NO_PAYMENT_BY_SCRIPT"
echo [RESTORE] Returning production UI/bridge after setup error...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled true >nul 2>nul
pause
exit /b 20
