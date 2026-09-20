@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"
set "OUTCOME=WAITING_FOR_UI_PAYMENT"
set "JL22WAIT=%TEMP%\iretail_main_ui_payment_jl22.log"
set "KOZENWAIT=%TEMP%\iretail_main_ui_payment_kozen.log"

echo ============================================================
echo i-Retail v0.5.21 - REAL PAYMENT FROM MAIN UI
 echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo.
echo IMPORTANT:
echo   This Windows script NEVER sends PAYMENT itself.
echo   It installs/configures STANDALONE mode + real POS and then waits.
echo   PAYMENT can be initiated ONLY by your tap on BANK CARD inside the
 echo   main i-Retail UI running on the coffee machine.
echo.
echo   Tap BANK CARD ONCE. If the result becomes uncertain, DO NOT tap it again.
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

echo [1/8] Building main i-Retail UI and hardened Kozen bridge...
call "%GRADLE_CMD%" --no-daemon --stacktrace :app:assembleDebug :kozenBridge:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed. No payment was sent.
  pause
  exit /b 7
)

set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"

echo [2/8] Installing i-Retail main UI on JL22...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 8

echo [3/8] Installing hardened payment bridge on Kozen...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 exit /b 9

echo [4/8] Closing old diagnostic clients and clearing logs...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost >nul 2>nul
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoarecovery >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenrecovery >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" logcat -c
adb -s "%KOZEN%" logcat -c

echo [5/8] Starting Kozen production bridge...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity
if errorlevel 1 exit /b 10

echo [6/8] Persisting STANDALONE + REAL POS and starting MAIN i-Retail UI...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled true
if errorlevel 1 exit /b 11

echo.
echo ============================================================
echo USE THE COFFEE-MACHINE SCREEN NOW
 echo ============================================================
echo 1. In the MAIN i-Retail UI create/select an order.
echo 2. Open payment methods.
echo 3. Tap BANK CARD exactly ONCE.
echo 4. When Kozen asks for a card, present the card to Kozen.
echo.
echo Do NOT press keys in this console. It will detect the payment automatically.
echo Waiting up to 10 minutes for the UI to initiate one payment...
echo ============================================================
echo.

set "PAYMENT_SEEN=0"
for /l %%S in (1,1,600) do (
  adb -s "%JL22%" logcat -d -v brief IretailKozenClient:I IretailKozenClient:W IretailKozenClient:E *:S > "%JL22WAIT%" 2>&1
  findstr /C:"PAYMENT_TX_ONCE" "%JL22WAIT%" >nul 2>nul
  if not errorlevel 1 goto PAYMENT_STARTED
  timeout /t 1 /nobreak >nul
)
set "OUTCOME=NO_PAYMENT_FROM_UI"
echo [TIMEOUT] No PAYMENT_TX_ONCE was observed from the main i-Retail UI.
goto COLLECT

:PAYMENT_STARTED
set "PAYMENT_SEEN=1"
echo [INFO] Main i-Retail UI sent exactly one PAYMENT request. Waiting for final result...
for /l %%S in (1,1,160) do (
  adb -s "%JL22%" logcat -d -v brief IretailKozenClient:I IretailKozenClient:W IretailKozenClient:E *:S > "%JL22WAIT%" 2>&1
  adb -s "%KOZEN%" logcat -d -v brief IretailKozenBridge:I IretailKozenBridge:W IretailKozenBridge:E *:S > "%KOZENWAIT%" 2>&1
  findstr /C:"PAYMENT_RX" "%JL22WAIT%" >nul 2>nul
  if not errorlevel 1 goto CLASSIFY
  findstr /C:"PAYMENT_CALL_RESULT" "%KOZENWAIT%" >nul 2>nul
  if not errorlevel 1 goto CLASSIFY
  findstr /C:"PAYMENT_CALL_UNCERTAIN" "%KOZENWAIT%" >nul 2>nul
  if not errorlevel 1 goto PAYMENT_UNCERTAIN
  findstr /C:"PAYMENT_CLIENT_ERROR" "%JL22WAIT%" >nul 2>nul
  if not errorlevel 1 goto PAYMENT_UNCERTAIN
  timeout /t 1 /nobreak >nul
)
set "OUTCOME=PAYMENT_RESULT_TIMEOUT_UNCERTAIN"
echo [UNCERTAIN] Payment was sent, but no final result was observed in time.
echo DO NOT start another payment before we inspect the archive.
goto COLLECT

:CLASSIFY
findstr /C:"status=APPROVED" "%JL22WAIT%" >nul 2>nul
if not errorlevel 1 goto PAYMENT_APPROVED
findstr /C:"status=APPROVED" "%KOZENWAIT%" >nul 2>nul
if not errorlevel 1 goto PAYMENT_APPROVED
findstr /C:"status=DECLINED" "%JL22WAIT%" >nul 2>nul
if not errorlevel 1 goto PAYMENT_DECLINED
findstr /C:"status=DECLINED" "%KOZENWAIT%" >nul 2>nul
if not errorlevel 1 goto PAYMENT_DECLINED
findstr /C:"status=UNCERTAIN" "%JL22WAIT%" >nul 2>nul
if not errorlevel 1 goto PAYMENT_UNCERTAIN
findstr /C:"status=UNCERTAIN" "%KOZENWAIT%" >nul 2>nul
if not errorlevel 1 goto PAYMENT_UNCERTAIN
set "OUTCOME=PAYMENT_FINAL_NON_APPROVED"
echo [INFO] Payment returned a final non-approved result.
goto COLLECT

:PAYMENT_APPROVED
set "OUTCOME=PAYMENT_APPROVED"
echo [SUCCESS] Main i-Retail UI received an APPROVED payment result.
goto COLLECT

:PAYMENT_DECLINED
set "OUTCOME=PAYMENT_DECLINED"
echo [DECLINED] Payment was completed and declined. Do not repeat unless you deliberately want a new payment.
goto COLLECT

:PAYMENT_UNCERTAIN
set "OUTCOME=PAYMENT_UNCERTAIN"
echo [UNCERTAIN] Payment result is uncertain. DO NOT tap BANK CARD again.
goto COLLECT

:COLLECT
set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "main_ui_payment_logs" mkdir "main_ui_payment_logs"
set "OUT=main_ui_payment_logs\MAIN_UI_REAL_PAYMENT_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo kozen=%KOZEN%
  echo timestamp=%TS%
  echo outcome=%OUTCOME%
  echo payment_seen=%PAYMENT_SEEN%
  echo initiator=MAIN_IRETAIL_UI_ON_JL22
  echo windows_script_sends_payment=false
  echo machine_mode=standalone
  echo real_pos_enabled=true
) > "%OUT%\00_info.txt"

echo [7/8] Collecting both sides...
adb devices -l > "%OUT%\01_windows_adb_devices.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime IretailKozenClient:I IretailKozenClient:W IretailKozenClient:E IretailMachineMode:I IretailForegroundKeeper:I ActivityManager:I AndroidRuntime:E *:S > "%OUT%\JL22_02_main_ui_payment_logcat.txt" 2>&1
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:I IretailKozenBridge:W IretailKozenBridge:E ActivityManager:I AndroidRuntime:E *:S > "%OUT%\KOZEN_02_bridge_payment_logcat.txt" 2>&1
adb -s "%JL22%" shell dumpsys usb > "%OUT%\JL22_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys usb > "%OUT%\KOZEN_03_dumpsys_usb.txt" 2>&1
adb -s "%JL22%" shell dumpsys activity activities > "%OUT%\JL22_04_activities.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity services com.skytech.smartskypos > "%OUT%\KOZEN_04_smartsky_services.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.coffeeonelove.iretail.kozenbridge > "%OUT%\KOZEN_05_bridge_package.txt" 2>&1
adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail > "%OUT%\JL22_05_iretail_package.txt" 2>&1

(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo ===== JL22 MAIN i-RETAIL PAYMENT CLIENT =====
  findstr /I "AOA_LINK_READY STATUS PAYMENT_TX_ONCE PAYMENT_RX PAYMENT_RESPONSE_TIMEOUT PAYMENT_CLIENT_ERROR UNRESOLVED_STATUS_RECOVERY" "%OUT%\JL22_02_main_ui_payment_logcat.txt"
  echo.
  echo ===== KOZEN PRODUCTION BRIDGE =====
  findstr /I "BRIDGE_READY RX PAYMENT GET_STATE GET_TERMINAL_DATA PAYMENT_CALL_BEGIN PAYMENT_CALL_RESULT PAYMENT_CALL_UNCERTAIN SMARTSKY_BOUND" "%OUT%\KOZEN_02_bridge_payment_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [8/8] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo MAIN i-Retail UI REAL PAYMENT TEST COMPLETE
echo Outcome: %OUTCOME%
echo.
echo The payment, if any, was initiated ONLY by the tap in i-Retail UI.
echo Publish the evidence with:
echo   call GIT_109_PUBLISH_MAIN_UI_PAYMENT_RESULT.bat
echo ============================================================
if /I "%OUTCOME%"=="PAYMENT_UNCERTAIN" echo IMPORTANT: DO NOT START ANOTHER PAYMENT.
if /I "%OUTCOME%"=="PAYMENT_RESULT_TIMEOUT_UNCERTAIN" echo IMPORTANT: DO NOT START ANOTHER PAYMENT.
pause
exit /b 0
