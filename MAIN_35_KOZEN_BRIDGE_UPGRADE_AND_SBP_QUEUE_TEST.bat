@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_APP_VERSION=0.5.119-sbp-landscape-qr"
set "EXPECTED_BRIDGE_VERSION=0.5.6-sbp-event-queue"
set "JL22="
set "KOZEN="
set "KOZEN_IP="
set "KOZEN_NET="

echo ============================================================
echo i-Retail %EXPECTED_APP_VERSION%
echo KOZEN BRIDGE UPGRADE + SAFE SBP EVENT QUEUE TEST
echo ============================================================
echo.
echo This procedure DOES NOT call qrPayment or PAYMENT.
echo real POS remains disabled during the SBP queue test.
echo.

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found.
  pause
  exit /b 10
)

call "%~dp0tools\WAIT_FOR_JL22.bat" JL22
if errorlevel 1 exit /b 13

call :FindKozen
if not defined KOZEN (
  echo.
  echo ------------------------------------------------------------
  echo KOZEN BRIDGE UPGRADE REQUIRES ONE DIRECT ADB CONNECTION
  echo ------------------------------------------------------------
  echo 1. Disconnect the Kozen device-side USB cable from JL22.
  echo 2. Connect that Kozen USB device port directly to this Windows PC.
  echo 3. Leave Kozen powered on and unlocked.
  echo 4. Wait until Windows finishes detecting it.
  echo.
  echo Press any key when Kozen is connected to Windows.
  pause >nul
  timeout /t 2 /nobreak >nul
  call :FindKozen
)

if not defined KOZEN (
  echo [ERROR] Kozen with com.skytech.smartskypos was not found through ADB.
  echo [INFO] Current devices:
  adb devices -l
  pause
  exit /b 11
)
echo [KOZEN ADB] %KOZEN%

set "GRADLE_CMD="
if exist "gradlew.bat" set "GRADLE_CMD=%CD%\gradlew.bat"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD (
  echo [ERROR] Gradle was not found.
  pause
  exit /b 12
)

echo.
echo [1/7] Building Kozen Bridge 0.5.6...
call "%GRADLE_CMD%" --no-daemon --stacktrace :kozenBridge:assembleDebug
if errorlevel 1 (
  echo [ERROR] Kozen Bridge build failed.
  pause
  exit /b 20
)

set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
if not exist "%KOZEN_APK%" (
  echo [ERROR] Kozen Bridge APK was not created:
  echo %KOZEN_APK%
  pause
  exit /b 21
)

echo.
echo [2/7] Installing Kozen Bridge 0.5.6...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 (
  echo [ERROR] Kozen Bridge installation failed.
  pause
  exit /b 22
)

adb -s "%KOZEN%" shell dumpsys package com.coffeeonelove.iretail.kozenbridge > "%TEMP%\iretail_kozen_bridge_package.txt" 2>&1
findstr /C:"versionName=%EXPECTED_BRIDGE_VERSION%" "%TEMP%\iretail_kozen_bridge_package.txt" >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Installed Kozen Bridge version could not be verified.
  findstr /I /C:"versionName=" "%TEMP%\iretail_kozen_bridge_package.txt"
  pause
  exit /b 23
)
echo [OK] Installed bridge: %EXPECTED_BRIDGE_VERSION%

echo.
echo [3/7] Preparing optional network ADB for Kozen...
adb -s "%KOZEN%" shell ip route > "%TEMP%\iretail_kozen_ip_route.txt" 2>&1
for /f "delims=" %%I in ('powershell -NoProfile -Command "$t=Get-Content -Raw -LiteralPath '%TEMP%\iretail_kozen_ip_route.txt'; if($t -match '\bsrc\s+(\d{1,3}(?:\.\d{1,3}){3})\b'){ $matches[1] }" 2^>nul') do if not defined KOZEN_IP set "KOZEN_IP=%%I"

if defined KOZEN_IP (
  echo [INFO] Kozen IP: %KOZEN_IP%
  adb -s "%KOZEN%" tcpip 5555 >nul 2>nul
  timeout /t 2 /nobreak >nul
  adb connect "%KOZEN_IP%:5555" >nul 2>nul
  adb -s "%KOZEN_IP%:5555" get-state >nul 2>nul
  if not errorlevel 1 (
    set "KOZEN_NET=%KOZEN_IP%:5555"
    echo [OK] Kozen network ADB prepared: %KOZEN_IP%:5555
  ) else (
    echo [NOTE] Network ADB is not available. This is not fatal.
  )
) else (
  echo [NOTE] Kozen IP was not detected. This is not fatal.
)

echo.
echo [4/7] Return Kozen to JL22.
echo ------------------------------------------------------------
echo Disconnect Kozen from this Windows PC and connect the same
echo Kozen device-side USB port back to the JL22 USB HOST port.
echo Keep JL22 and Kozen powered on.
echo ------------------------------------------------------------
echo Press any key after the cable is connected and devices have settled.
pause >nul
timeout /t 3 /nobreak >nul

if defined KOZEN_NET (
  adb connect "%KOZEN_NET%" >nul 2>nul
  adb -s "%KOZEN_NET%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
)

echo.
echo [5/7] Running safe SBP queue test...
call "%~dp0MAIN_34_SBP_EVENT_QUEUE_SYNTHETIC_TEST.bat"
set "QUEUE_RC=%ERRORLEVEL%"

if not "%QUEUE_RC%"=="0" goto QUEUE_FAILED

echo.
echo [6/7] Running JL22 screen QR DRY RUN...
call "%~dp0MAIN_30_SBP_DRYRUN_UI_TEST.bat"
set "QR_UI_RC=%ERRORLEVEL%"

echo.
echo [7/7] Finished.
if "%QR_UI_RC%"=="0" (
  echo ============================================================
  echo KOZEN_BRIDGE_UPGRADE_OK
  echo SBP_EVENT_QUEUE_OK
  echo JL22_SCREEN_QR_DRYRUN_OK
  echo No financial command was sent.
  echo ============================================================
  exit /b 0
)

echo ============================================================
echo KOZEN_BRIDGE_UPGRADE_OK
echo SBP_EVENT_QUEUE_OK
echo JL22 screen QR DRY RUN returned code %QR_UI_RC%.
echo No financial command was sent.
echo ============================================================
pause
exit /b %QR_UI_RC%

:QUEUE_FAILED
echo.
echo ============================================================
echo KOZEN_BRIDGE_UPGRADE_OK
echo SBP queue test returned code %QUEUE_RC%.
echo Send the newest sbp_event_logs\SBP_EVENT_QUEUE_*.log.
echo No financial command was sent by this upgrade procedure.
echo ============================================================
pause
exit /b %QUEUE_RC%

:FindKozen
set "KOZEN="
for /f "tokens=1,2,*" %%A in ('adb devices -l') do (
  if /I "%%B"=="device" call :ProbeKozen "%%A"
)
exit /b 0

:ProbeKozen
if defined KOZEN exit /b 0
if defined JL22 if /I "%~1"=="%JL22%" exit /b 0
adb -s "%~1" shell pm path com.skytech.smartskypos > "%TEMP%\iretail_probe_smartskypos.txt" 2>nul
findstr /B /C:"package:" "%TEMP%\iretail_probe_smartskypos.txt" >nul 2>nul
if not errorlevel 1 set "KOZEN=%~1"
exit /b 0
