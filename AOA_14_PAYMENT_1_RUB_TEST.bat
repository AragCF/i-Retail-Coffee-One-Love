@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
set "KOZEN=%~2"
if not defined JL22 set "JL22=192.168.1.192:5555"
if not defined KOZEN set "KOZEN=192.168.31.134:5555"

echo ============================================================
echo i-Retail CONTROLLED REAL PAYMENT TEST - 1.00 RUB
echo ============================================================
echo JL22 : %JL22%
echo Kozen: %KOZEN%
echo.
echo THIS TEST CALLS A REAL SmartSkyPOS payment.
echo Amount is fixed to 1.00 RUB.
echo There is NO automatic financial retry.
echo Success requires code=0 AND approved=true.
echo.
echo Keep Kozen connected to JL22 with the short stable USB cable.
echo Prepare a card for the Kozen terminal.
echo ============================================================
echo.

set "CONFIRM="
set /p "CONFIRM=Type exactly PAY 1.00 to authorize this one payment: "
if /I not "%CONFIRM%"=="PAY 1.00" (
  echo [CANCELLED] Exact authorization text was not entered.
  pause
  exit /b 20
)

set "REQ_ID="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmmss" 2^>nul') do if not defined REQ_ID set "REQ_ID=pay-%%T"
if not defined REQ_ID set "REQ_ID=pay-manual"
echo.
echo Payment request id: %REQ_ID%
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

echo [1/8] Building payment bridge and JL22 host...
call "%GRADLE_CMD%" --no-daemon --stacktrace :kozenBridge:assembleDebug :jl22AoaProbe:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed. No payment was requested.
  pause
  exit /b 7
)

set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
set "JL22_APK=jl22AoaProbe\build\outputs\apk\debug\jl22AoaProbe-debug.apk"

echo [2/8] Installing Kozen Payment Bridge v0.4...
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 (
  echo [ERROR] Kozen APK install failed. No payment was requested.
  pause
  exit /b 8
)

echo [3/8] Installing JL22 payment host v0.4...
adb -s "%JL22%" install -r "%JL22_APK%"
if errorlevel 1 (
  echo [ERROR] JL22 APK install failed. No payment was requested.
  pause
  exit /b 9
)

echo [4/8] Clearing diagnostic log buffers...
adb -s "%KOZEN%" logcat -c
adb -s "%JL22%" logcat -c
adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail.aoahost

echo [5/8] Starting Kozen Bridge...
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity

echo [6/8] Starting JL22 controlled payment request...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail.aoahost/.AoaHostProbeActivity --ez allow_payment true --es payment_request_id "%REQ_ID%" --es payment_amount "1.00"

echo.
echo ============================================================
echo WATCH JL22 AND KOZEN NOW.
echo Present the card if Kozen asks for it.
echo.
echo IMPORTANT: do not run this script again if the result is unclear.
echo Wait until JL22 shows APPROVED, NOT APPROVED, or UNCERTAIN.
echo Then press any key here to collect evidence.
echo ============================================================
pause

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "aoa_payment_logs" mkdir "aoa_payment_logs"
set "OUT=aoa_payment_logs\AOA_PAYMENT_JL22_KOZEN_%TS%_%REQ_ID%"
mkdir "%OUT%"

echo [7/8] Collecting both sides...
(
  echo jl22=%JL22%
  echo kozen=%KOZEN%
  echo timestamp=%TS%
  echo request_id=%REQ_ID%
  echo amount=1.00
  echo currency=643
  echo safety=SINGLE_PAYMENT_NO_AUTO_RETRY
) > "%OUT%\00_info.txt"
adb devices -l > "%OUT%\01_windows_adb_devices.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime IretailAoaHost:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\JL22_02_payment_logcat.txt" 2>&1
adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:I AndroidRuntime:E ActivityManager:I *:S > "%OUT%\KOZEN_02_bridge_logcat.txt" 2>&1
adb -s "%JL22%" shell dumpsys usb > "%OUT%\JL22_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys usb > "%OUT%\KOZEN_03_dumpsys_usb.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys activity services com.skytech.smartskypos > "%OUT%\KOZEN_04_smartsky_services.txt" 2>&1
adb -s "%KOZEN%" shell dumpsys package com.skytech.smartskypos > "%OUT%\KOZEN_05_smartsky_package.txt" 2>&1

(
  echo ===== JL22 PAYMENT RESULT =====
  findstr /I "TERMINAL_DATA_READY PAYMENT_TX_ONCE PAYMENT_RX PAYMENT_OVER_AOA PAYMENT_RESULT APPROVED UNCERTAIN NOT_APPROVED" "%OUT%\JL22_02_payment_logcat.txt"
  echo.
  echo ===== KOZEN PAYMENT RESULT =====
  findstr /I "PAYMENT_CALL PAYMENT_CALLBACK RX.PAYMENT TX.PAYMENT PAYMENT_RESULT SMARTSKY_OPERATION" "%OUT%\KOZEN_02_bridge_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [8/8] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo TEST COMPLETE.
echo DO NOT repeat a payment based only on code=0.
echo Success requires approved=true.
echo Publish with:
echo   call GIT_104_PUBLISH_AOA_PAYMENT_RESULT.bat
echo ============================================================
pause
exit /b 0
