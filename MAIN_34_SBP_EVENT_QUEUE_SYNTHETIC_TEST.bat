@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_VERSION="
for /f "tokens=2" %%V in ('findstr /C:"versionName " "app\build.gradle"') do if not defined EXPECTED_VERSION set "EXPECTED_VERSION=%%V"
set "EXPECTED_VERSION=%EXPECTED_VERSION:'=%"
if /I not "%EXPECTED_VERSION%"=="0.5.125-sbp-channel-service-doc-audit" (
  echo [ERROR] Wrong project version: %EXPECTED_VERSION%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - SBP EVENT QUEUE SYNTHETIC TEST
echo ============================================================
echo SAFETY: real POS=FALSE, qrPayment is NOT called.
echo.

where adb >nul 2>nul
if errorlevel 1 (echo [ERROR] adb was not found.& pause& exit /b 12)

set "JL22="
call "%~dp0tools\WAIT_FOR_JL22.bat" JL22
if errorlevel 1 exit /b 13

set "KOZEN="
set "KOZEN_ADB_AVAILABLE=0"
if not "%~1"=="" call :TryKozen "%~1"
if "%KOZEN_ADB_AVAILABLE%"=="0" call :TryKozen "192.168.31.134:5555"
if "%KOZEN_ADB_AVAILABLE%"=="0" for /f "tokens=1,2,*" %%A in ('adb devices -l') do if /I "%%B"=="device" if /I not "%%A"=="%JL22%" call :TryKozen "%%A"
if "%KOZEN_ADB_AVAILABLE%"=="1" (echo [KOZEN ADB] %KOZEN%) else echo [KOZEN ADB] unavailable; existing bridge will be tested over AOA.

echo [1/7] Building i-Retail...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 (echo [ERROR] Main APK build failed.& pause& exit /b 20)
set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
if not exist "%APP_APK%" exit /b 21

set "GRADLE_CMD="
if exist "gradlew.bat" set "GRADLE_CMD=%CD%\gradlew.bat"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD (echo [ERROR] Gradle was not found.& pause& exit /b 22)

echo [2/7] Preparing Kozen bridge 0.5.7 when ADB is available...
if "%KOZEN_ADB_AVAILABLE%"=="1" (
  call "%GRADLE_CMD%" --no-daemon --stacktrace :kozenBridge:assembleDebug
  if errorlevel 1 exit /b 23
  if not exist "%KOZEN_APK%" exit /b 24
  adb -s "%KOZEN%" install -r "%KOZEN_APK%"
  if errorlevel 1 exit /b 25
  adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
)

echo [3/7] Installing i-Retail on JL22...
call "%~dp0tools\WAIT_FOR_JL22.bat" JL22
if errorlevel 1 exit /b 13
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 26
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
if errorlevel 1 exit /b 27
timeout /t 1 /nobreak >nul
if "%KOZEN_ADB_AVAILABLE%"=="1" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
adb -s "%JL22%" logcat -c

echo [4/7] Running synthetic queue - peek - idempotent ACK test...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_event_queue_synthetic_test true >nul
if errorlevel 1 exit /b 28

set "WAIT_LOG=%TEMP%\iretail_sbp_event_queue_wait.log"
set "OUTCOME=EVENT_TIMEOUT"
for /l %%S in (1,1,120) do (
  if "%KOZEN_ADB_AVAILABLE%"=="1" if "%%S"=="3" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
  adb -s "%JL22%" logcat -d -v brief SbpEventQueueTest:V IretailKozenClient:V AndroidRuntime:E *:S > "%WAIT_LOG%" 2>&1
  findstr /C:"EVENT_QUEUE_RESULT ok=true" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (set "OUTCOME=EVENT_QUEUE_OK"& goto EVENT_DONE)
  findstr /C:"BRIDGE_UPGRADE_REQUIRED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (set "OUTCOME=BRIDGE_UPGRADE_REQUIRED"& goto EVENT_DONE)
  findstr /C:"EVENT_QUEUE_RESULT ok=false" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (set "OUTCOME=EVENT_QUEUE_FAILED"& goto EVENT_DONE)
  timeout /t 1 /nobreak >nul
)

:EVENT_DONE
echo [5/7] Restoring ordinary i-Retail foreground...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false >nul 2>nul
timeout /t 1 /nobreak >nul

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "sbp_event_logs" mkdir "sbp_event_logs"
set "LOG=sbp_event_logs\SBP_EVENT_QUEUE_%TS%.log"

echo [6/7] Collecting sanitized evidence...
(
  echo version=%EXPECTED_VERSION%
  echo outcome=%OUTCOME%
  echo safety=SYNTHETIC_NO_FINANCIAL_COMMANDS
  echo real_pos=false
  echo expected_bridge=0.5.6
  echo event_contract=QR_EVENT_PEEK_ACK_V1
  echo live_qr_payment_enabled=false
  echo.
  adb -s "%JL22%" logcat -d -v threadtime SbpEventQueueTest:V IretailKozenClient:V IretailMachineMode:I AndroidRuntime:E *:S
) > "%LOG%" 2>&1
powershell -NoProfile -Command "$p='%CD%\%LOG%'; $x=Get-Content -Raw -LiteralPath $p; $x=[regex]::Replace($x,'(?i)\b(payloadB64|qrPayload|payload|qrIdB64|qrId)=([^\s]+)','$1=[REDACTED]'); Set-Content -Encoding UTF8 -LiteralPath $p -Value $x; if($x -match 'SBP-EVENT-QUEUE\|'){ Write-Host '[ERROR] RAW QR PAYLOAD LEAK'; exit 1 }"
if errorlevel 1 (echo [ERROR] Safety scan failed.& pause& exit /b 31)

echo [7/7] Result:
echo ============================================================
echo %OUTCOME%
echo Report: %CD%\%LOG%
echo No financial command was sent.
echo ============================================================
findstr /I "EVENT_QUEUE_RESULT SBP_EVENT_OK SBP_EVENT_FAILED SBP_EVENT_ACK_RETRY" "%LOG%"
pause
if /I "%OUTCOME%"=="EVENT_QUEUE_OK" exit /b 0
if /I "%OUTCOME%"=="BRIDGE_UPGRADE_REQUIRED" exit /b 2
exit /b 3

:TryKozen
if "%KOZEN_ADB_AVAILABLE%"=="1" exit /b 0
set "CANDIDATE=%~1"
echo %CANDIDATE% | findstr /C:":" >nul 2>nul
if not errorlevel 1 adb connect "%CANDIDATE%" >nul 2>nul
adb -s "%CANDIDATE%" get-state >nul 2>nul
if errorlevel 1 exit /b 0
adb -s "%CANDIDATE%" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
if errorlevel 1 exit /b 0
set "KOZEN=%CANDIDATE%"
set "KOZEN_ADB_AVAILABLE=1"
exit /b 0
