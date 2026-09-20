@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "KOZEN=%~1"
set "JL22=%~2"
set "TID=%~3"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined TID set "TID=12000679"

set "HOST=185.162.94.67"
set "PORT=9221"
set "FIRST_RECEIPT=1"
set "LAST_RECEIPT=9"

 echo ============================================================
 echo SmartSkyPOS READ-ONLY ACQUIRING / TERMINAL AUDIT v0.5.22
 echo ============================================================
 echo Kozen: %KOZEN%
 echo JL22 : %JL22%
 echo TID  : %TID%
 echo Host : %HOST%:%PORT%
 echo.
 echo SAFETY:
 echo   NO PAYMENT, CANCEL, REFUND OR RECONCILIATION IS CALLED.
 echo   The script only reads SmartSkyPOS state/TerminalData/history and
 echo   checks Kozen network/time/package/service state.
 echo ============================================================
 echo.

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found in PATH.
  pause
  exit /b 2
)
adb -s "%KOZEN%" get-state >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Kozen is not online: %KOZEN%
  pause
  exit /b 3
)

set "SDK_PATH="
if defined ANDROID_HOME set "SDK_PATH=%ANDROID_HOME%"
if not defined SDK_PATH if defined ANDROID_SDK_ROOT set "SDK_PATH=%ANDROID_SDK_ROOT%"
if not defined SDK_PATH if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_PATH=%LOCALAPPDATA%\Android\Sdk"
if not defined SDK_PATH (
  echo [ERROR] Android SDK was not found.
  pause
  exit /b 4
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
  exit /b 5
)

 echo [1/9] Building the read-only diagnostic app...
call "%GRADLE_CMD%" --no-daemon --stacktrace :app:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed. No financial command was sent.
  pause
  exit /b 6
)
set "APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APK%" (
  echo [ERROR] APK not found: %APK%
  pause
  exit /b 7
)

 echo [2/9] Installing diagnostic app on Kozen and clearing diagnostic log buffer...
adb -s "%KOZEN%" install -r "%APK%"
if errorlevel 1 (
  echo [ERROR] APK install failed.
  pause
  exit /b 8
)
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%KOZEN%" logcat -c

 echo [3/9] Reading current SmartSkyPOS state and TerminalData. Payment mode is OFF...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail/.pos.SmartSkyPosDiagnosticActivity >nul 2>nul
timeout /t 4 /nobreak >nul
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul

 echo [4/9] Reading receipts %FIRST_RECEIPT%..%LAST_RECEIPT% one by one. READ-ONLY...
for /l %%R in (%FIRST_RECEIPT%,1,%LAST_RECEIPT%) do (
  echo   receipt %%R
  adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail/.pos.SmartSkyPosTransactionLookupActivity --es terminal_id "%TID%" --es receipt_number "%%R" >nul 2>nul
  timeout /t 2 /nobreak >nul
  adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
)

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "smartskypos_acquirer_audit_logs" mkdir "smartskypos_acquirer_audit_logs"
set "OUT=smartskypos_acquirer_audit_logs\SMARTSKYPOS_ACQUIRER_AUDIT_%TS%"
mkdir "%OUT%"

 echo [5/9] Collecting safe SmartSkyPOS diagnostic history...
adb -s "%KOZEN%" logcat -d -v threadtime SmartSkyPOSDiag:V SmartSkyPOSTxLookup:V AndroidRuntime:E *:S > "%OUT%\01_smartsky_safe_logcat.txt" 2>&1

 echo [6/9] Collecting SmartSkyPOS / POS service configuration metadata...
adb -s "%KOZEN%" shell dumpsys package com.skytech.smartskypos > "%OUT%\02_smartsky_package.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity services com.skytech.smartskypos > "%OUT%\03_smartsky_services.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.pos.service > "%OUT%\04_pos_service_package.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity services com.pos.service > "%OUT%\05_pos_services.txt" 2>&1

 echo [7/9] Checking Kozen time, routing and acquiring endpoint reachability...
(
  echo ===== TIME =====
  adb -s "%KOZEN%" shell date
  adb -s "%KOZEN%" shell getprop persist.sys.timezone
  echo auto_time:
  adb -s "%KOZEN%" shell settings get global auto_time
  echo auto_time_zone:
  adb -s "%KOZEN%" shell settings get global auto_time_zone
  echo.
  echo ===== NETWORK =====
  adb -s "%KOZEN%" shell ip addr
  adb -s "%KOZEN%" shell ip route
  echo.
  echo ===== IP PING %HOST% =====
  adb -s "%KOZEN%" shell ping -c 3 %HOST%
  echo.
  echo ===== DNS/PING beta-tms.payment-guide.ru =====
  adb -s "%KOZEN%" shell ping -c 1 beta-tms.payment-guide.ru
  echo.
  echo ===== TCP %HOST%:%PORT% via toybox nc =====
  adb -s "%KOZEN%" shell "toybox nc -z -w 5 %HOST% %PORT%; echo TCP_TEST_RC=$?"
  echo.
  echo ===== CONNECTIVITY =====
  adb -s "%KOZEN%" shell dumpsys connectivity
) > "%OUT%\06_network_time_endpoint.txt" 2>&1

 echo [8/9] Building a compact provider-ready summary...
(
  echo ===== SAFETY =====
  echo READ_ONLY_NO_FINANCIAL_COMMANDS
  echo.
  echo ===== CURRENT SMARTSKYPOS / TERMINAL DATA =====
  findstr /I "GET_STATE TERMINAL_DATA TERMINAL id= PAYMENT_GATE" "%OUT%\01_smartsky_safe_logcat.txt"
  echo.
  echo ===== TRANSACTION HISTORY RECEIPTS %FIRST_RECEIPT%..%LAST_RECEIPT% =====
  findstr /I "TRANSACTION_LOOKUP" "%OUT%\01_smartsky_safe_logcat.txt"
  echo.
  echo ===== ENDPOINT / TIME =====
  findstr /I "MSK Moscow TCP_TEST_RC bytes from packet loss beta-tms" "%OUT%\06_network_time_endpoint.txt"
  echo.
  echo ===== KNOWN CONFIG =====
  echo expectedTid=%TID%
  echo expectedHost=%HOST%
  echo expectedPort=%PORT%
  echo expectedCurrency=643
  echo observedProfileFromTerminalData=VPP_BETA_TMS_V1
  echo provider=Vash Platezhnyy Provodnik / SmartSkyPOS
) > "%OUT%\SUMMARY.txt" 2>&1

(
  echo kozen=%KOZEN%
  echo jl22=%JL22%
  echo terminal_id=%TID%
  echo timestamp=%TS%
  echo safety=READ_ONLY_NO_FINANCIAL_COMMANDS
  echo receipts=%FIRST_RECEIPT%..%LAST_RECEIPT%
  echo host=%HOST%
  echo port=%PORT%
) > "%OUT%\00_info.txt"

 echo [9/9] Restoring normal Kozen bridge / JL22 UI and creating archive...
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
adb -s "%JL22%" get-state >nul 2>nul
if not errorlevel 1 adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled true >nul 2>nul

powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo READ-ONLY ACQUIRING AUDIT COMPLETE.
echo No payment/cancel/refund/reconciliation was executed.
echo Publish with:
echo   call GIT_112_PUBLISH_ACQUIRER_AUDIT.bat
echo ============================================================
pause
exit /b 0
