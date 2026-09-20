@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"
set "REQ_ID=not-authorized"
set "OUTCOME=STARTED"
set "READYLOG=%TEMP%\iretail_payment_ready.log"
set "FINALLOG=%TEMP%\iretail_payment_final.log"

echo ============================================================
echo i-Retail STAGED REAL PAYMENT TEST - 1.00 RUB
echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo.
echo SAFETY ORDER:
echo   1. Build/install apps.
echo   2. Prove AOA + SmartSkyPOS READY + fresh TerminalData.
echo   3. ONLY THEN ask you for explicit PAY 1.00 authorization.
echo   4. Send exactly one PAYMENT command.
echo   5. Wait automatically for final result and collect evidence.
echo.
echo There is NO automatic financial retry.
echo Success requires code=0 AND approved=true.
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

echo [1/10] Building staged payment bridge and JL22 host...
call "%GRADLE_CMD%" --no-daemon --stacktrace :kozenBridge:assembleDebug :jl22AoaProbe:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed. No payment was authorized or requested.
  pause
  exit /b 7
)

set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
set "JL22_APK=jl22AoaProbe\build\outputs\apk\debug\jl22AoaProbe-debug.apk"

echo [2/10] Installing Kozen Payment Bridge...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 (
  echo [ERROR] Kozen APK install failed. No payment was authorized or requested.
  pause
  exit /b 8
)

echo [3/10] Installing JL22 staged payment host...
adb -s "%JL22%" install -r "%JL22_APK%"
if errorlevel 1 (
  echo [ERROR] JL22 APK install failed. No payment was authorized or requested.
  pause
  exit /b 9
)

echo [4/10] Clearing diagnostic logs and cancelling old armed test sessions...
adb -s "%KOZEN%" logcat -c
adb -s "%JL22%" logcat -c
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge

echo [5/10] Starting Kozen Bridge...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity

echo [6/10] Starting SAFE readiness phase on JL22...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail.aoahost/.AoaHostProbeActivity --ez staged_payment true

echo.
echo Waiting up to 120 seconds for AOA + PING/PONG + READY + fresh TerminalData.
echo NO PAYMENT COMMAND CAN BE SENT DURING THIS PHASE.
echo If Kozen asks for USB accessory permission, allow it.
echo.

for /l %%S in (1,1,120) do (
  adb -s "%JL22%" logcat -d -v brief IretailAoaHost:I *:S > "%READYLOG%" 2>&1
  findstr /C:"PAYMENT_READY_FOR_EXPLICIT_AUTHORIZATION" "%READYLOG%" >nul 2>nul
  if not errorlevel 1 goto READY_FOR_AUTH
  findstr /C:"noPaymentSent=true" "%READYLOG%" >nul 2>nul
  if not errorlevel 1 goto PREAUTH_FAILED
  if "%%S"=="3" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
  timeout /t 1 /nobreak >nul
)

set "OUTCOME=PREAUTH_TIMEOUT_NO_PAYMENT_SENT"
echo [STOP] Readiness was not reached. No payment authorization was requested.
goto SAFE_STOP_AND_COLLECT

:PREAUTH_FAILED
set "OUTCOME=PREAUTH_FAILED_NO_PAYMENT_SENT"
echo [STOP] Safe readiness phase reported a failure. No payment was sent.
goto SAFE_STOP_AND_COLLECT

:READY_FOR_AUTH
echo ============================================================
echo [READY] AOA link and SmartSkyPOS payment route are confirmed.
echo No financial command has been sent yet.
echo ============================================================
echo.

set "REQ_ID="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmmss" 2^>nul') do if not defined REQ_ID set "REQ_ID=pay-%%T"
if not defined REQ_ID set "REQ_ID=pay-manual"
echo Payment request id: %REQ_ID%
echo.
set "CONFIRM="
set /p "CONFIRM=Type exactly PAY 1.00 to authorize ONE real payment now: "
if /I not "%CONFIRM%"=="PAY 1.00" (
  set "OUTCOME=USER_CANCELLED_NO_PAYMENT_SENT"
  echo [CANCELLED] No financial command was sent.
  goto SAFE_STOP_AND_COLLECT
)

echo [7/10] Delivering separate one-shot payment authorization to the READY JL22 session...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail.aoahost/.AoaHostProbeActivity --ez authorize_payment true --es payment_request_id "%REQ_ID%" --es payment_amount "1.00"
if errorlevel 1 (
  set "OUTCOME=AUTH_INTENT_FAILED_NO_PAYMENT_CONFIRMED"
  echo [ERROR] Authorization intent could not be delivered.
  goto SAFE_STOP_AND_COLLECT
)

echo [8/10] Waiting automatically for terminal result. Do not press anything here.
echo Present the card ONLY if Kozen asks for it.
echo Maximum wait: 330 seconds.
echo.

for /l %%S in (1,1,330) do (
  adb -s "%JL22%" logcat -d -v brief IretailAoaHost:I *:S > "%FINALLOG%" 2>&1
  findstr /C:"PAYMENT_OVER_AOA_APPROVED requestId=%REQ_ID%" "%FINALLOG%" >nul 2>nul
  if not errorlevel 1 goto PAYMENT_APPROVED
  findstr /C:"PAYMENT_OVER_AOA_NOT_APPROVED requestId=%REQ_ID%" "%FINALLOG%" >nul 2>nul
  if not errorlevel 1 goto PAYMENT_NOT_APPROVED
  findstr /C:"PAYMENT_OVER_AOA_UNCERTAIN" "%FINALLOG%" >nul 2>nul
  if not errorlevel 1 goto PAYMENT_UNCERTAIN
  findstr /C:"PAYMENT_AUTH_REJECTED" "%FINALLOG%" >nul 2>nul
  if not errorlevel 1 goto AUTH_REJECTED
  timeout /t 1 /nobreak >nul
)

adb -s "%JL22%" logcat -d -v brief IretailAoaHost:I *:S > "%FINALLOG%" 2>&1
findstr /C:"PAYMENT_TX_ONCE requestId=%REQ_ID%" "%FINALLOG%" >nul 2>nul
if errorlevel 1 (
  set "OUTCOME=FINAL_TIMEOUT_NO_PAYMENT_SENT"
  echo [TIMEOUT] No PAYMENT_TX_ONCE marker exists. No financial call was confirmed.
  goto SAFE_STOP_AND_COLLECT
)
set "OUTCOME=UNCERTAIN_TIMEOUT_AFTER_PAYMENT_SENT"
echo [UNCERTAIN] PAYMENT was sent, but no terminal result was received in time.
echo DO NOT repeat this payment. The transaction must be recovered/read before any new payment.
goto UNCERTAIN_STOP_AND_COLLECT

:PAYMENT_APPROVED
set "OUTCOME=APPROVED"
echo [APPROVED] code=0 and approved=true were received for %REQ_ID%.
goto FINAL_STOP_AND_COLLECT

:PAYMENT_NOT_APPROVED
set "OUTCOME=NOT_APPROVED"
echo [NOT APPROVED] The operation completed without approval. Do not retry automatically.
goto FINAL_STOP_AND_COLLECT

:PAYMENT_UNCERTAIN
set "OUTCOME=UNCERTAIN"
echo [UNCERTAIN] Financial result is uncertain. DO NOT repeat the payment.
goto UNCERTAIN_STOP_AND_COLLECT

:AUTH_REJECTED
set "OUTCOME=AUTH_REJECTED_NO_PAYMENT_CONFIRMED"
echo [STOP] JL22 rejected the separate payment authorization.
goto SAFE_STOP_AND_COLLECT

:SAFE_STOP_AND_COLLECT
echo [9/10] Stopping non-financial/unsent test session...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
goto COLLECT

:FINAL_STOP_AND_COLLECT
echo [9/10] Final result received. Closing test applications...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost >nul 2>nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
goto COLLECT

:UNCERTAIN_STOP_AND_COLLECT
echo [9/10] Stopping JL22 sender. Kozen bridge is left running for transaction recovery.
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost >nul 2>nul
goto COLLECT

:COLLECT
set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "aoa_payment_logs" mkdir "aoa_payment_logs"
set "OUT=aoa_payment_logs\AOA_PAYMENT_JL22_KOZEN_%TS%_%REQ_ID%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo kozen=%KOZEN%
  echo timestamp=%TS%
  echo request_id=%REQ_ID%
  echo amount=1.00
  echo currency=643
  echo outcome=%OUTCOME%
  echo safety=STAGED_AUTH_SINGLE_PAYMENT_NO_AUTO_RETRY
) > "%OUT%\00_info.txt"
adb devices -l > "%OUT%\01_windows_adb_devices.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime IretailAoaHost:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\JL22_02_payment_logcat.txt" 2>&1
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\KOZEN_02_bridge_logcat.txt" 2>&1
adb -s "%JL22%" shell dumpsys usb > "%OUT%\JL22_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys usb > "%OUT%\KOZEN_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity services com.skytech.smartskypos > "%OUT%\KOZEN_04_smartsky_services.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.skytech.smartskypos > "%OUT%\KOZEN_05_smartsky_package.txt" 2>&1

(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo ===== JL22 PAYMENT RESULT =====
  findstr /I "PAYMENT_READY PAYMENT_AUTH PAYMENT_TX_ONCE PAYMENT_RX PAYMENT_OVER_AOA PAYMENT_RESULT APPROVED UNCERTAIN NOT_APPROVED noPaymentSent" "%OUT%\JL22_02_payment_logcat.txt"
  echo.
  echo ===== KOZEN PAYMENT RESULT =====
  findstr /I "PAYMENT_CALL PAYMENT_CALLBACK RX.PAYMENT TX.PAYMENT PAYMENT_RESULT SMARTSKY_OPERATION DUPLICATE UNCERTAIN" "%OUT%\KOZEN_02_bridge_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [10/10] Creating evidence archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo STAGED TEST COMPLETE. Outcome: %OUTCOME%
echo Publish with:
echo   call GIT_104_PUBLISH_AOA_PAYMENT_RESULT.bat
echo.
if /I "%OUTCOME%"=="UNCERTAIN" echo DO NOT REPEAT PAYMENT. Recover/read transaction first.
if /I "%OUTCOME%"=="UNCERTAIN_TIMEOUT_AFTER_PAYMENT_SENT" echo DO NOT REPEAT PAYMENT. Recover/read transaction first.
echo ============================================================
pause
exit /b 0
