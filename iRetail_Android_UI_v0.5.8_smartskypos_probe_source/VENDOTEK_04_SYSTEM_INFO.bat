@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
if not defined JL22 set "JL22=192.168.1.192:5555"
set "OUTCOME=WAITING"
set "WAITLOG=%TEMP%\iretail_vendotek_system_info.log"

echo ============================================================
echo i-Retail v0.5.24 - VENDOTEK READ-ONLY SYSTEM INFO
echo ============================================================
echo JL22: %JL22%
echo.
echo SAFETY:
echo   - NO payment request is sent.
echo   - NO VRP, FIN, ABR or DIS is sent.
echo   - Allowed VTK writes are IDL plus read-only SystemInfo queries:
echo       STATUS, POS_PARAMS, BANK_PARAMS, NET_PARAMS
echo   - IDL writes are spaced by at least 10 seconds.
echo.
echo Target:
echo   FTDI FT232R 0403:6001 /dev/ttyUSB0
echo   115200 8N1, no flow control
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

echo [1/8] Verifying Vendotek FTDI and ttyUSB0...
adb -s "%JL22%" shell lsusb | findstr /I "0403:6001" >nul
if errorlevel 1 (
  echo [ERROR] FTDI 0403:6001 is not visible. No VTK message was sent.
  pause
  exit /b 4
)
adb -s "%JL22%" shell test -e /dev/ttyUSB0
if errorlevel 1 (
  echo [ERROR] /dev/ttyUSB0 does not exist. No VTK message was sent.
  pause
  exit /b 5
)

echo [2/8] Building i-Retail diagnostic APK...
call BUILD_WINDOWS_CLI.bat
if errorlevel 1 (
  echo [ERROR] Build failed. No VTK message was sent.
  pause
  exit /b 6
)
set "APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APK%" (
  echo [ERROR] APK not found: %APK%
  pause
  exit /b 7
)

echo [3/8] Installing v0.5.24 SystemInfo probe on JL22...
adb -s "%JL22%" install -r "%APK%"
if errorlevel 1 (
  echo [ERROR] APK installation failed. No VTK message was sent.
  pause
  exit /b 8
)

echo [4/8] Starting read-only SystemInfo probe...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" logcat -c
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.vendotek.VendotekSystemInfoDiagnosticActivity
if errorlevel 1 (
  set "OUTCOME=ACTIVITY_START_FAILED"
  goto COLLECT
)

echo [5/8] Waiting for read-only result. This intentionally takes about 40-80 seconds...
for /l %%S in (1,1,110) do (
  adb -s "%JL22%" logcat -d -v brief IretailVendotek:I *:S > "%WAITLOG%" 2>&1
  findstr /C:"VTK_SYSTEM_INFO_COMPLETE" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=SYSTEM_INFO_COMPLETE"
    goto RESULT_SEEN
  )
  findstr /C:"VTK_CODEC_SELFTEST_FAILED" /C:"VTK_TTY_ACCESS_DENIED" /C:"VTK_SERIAL_CONFIG_ERROR" /C:"VTK_SYSINFO_IDL_TIMEOUT" /C:"VTK_SYSTEM_INFO_ERROR" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=SYSTEM_INFO_ERROR"
    goto RESULT_SEEN
  )
  timeout /t 1 /nobreak >nul
)
set "OUTCOME=WINDOWS_WAIT_TIMEOUT"

:RESULT_SEEN
echo Result: %OUTCOME%

:COLLECT
echo [6/8] Collecting evidence...
set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "vendotek_system_info_logs" mkdir "vendotek_system_info_logs"
set "OUT=vendotek_system_info_logs\VENDOTEK_SYSTEM_INFO_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo timestamp=%TS%
  echo outcome=%OUTCOME%
  echo usb=0403:6001 FTDI FT232R
  echo tty=/dev/ttyUSB0
  echo serial=115200_8N1_NO_FLOW
  echo protocol_writes=IDL_STATUS_POS_PARAMS_BANK_PARAMS_NET_PARAMS_ONLY
  echo financial_commands=NONE
) > "%OUT%\00_info.txt"

adb -s "%JL22%" logcat -d -v threadtime IretailVendotek:V AndroidRuntime:E ActivityManager:I *:S > "%OUT%\01_vendotek_system_info_logcat.txt" 2>&1
(
  adb -s "%JL22%" shell lsusb
  adb -s "%JL22%" shell ls -l /dev/ttyUSB0
  adb -s "%JL22%" shell ls -lZ /dev/ttyUSB0
  adb -s "%JL22%" shell cat /proc/tty/driver/usbserial
  adb -s "%JL22%" shell readlink -f /sys/class/tty/ttyUSB0/device/driver
) > "%OUT%\02_transport.txt" 2>&1
adb -s "%JL22%" shell "dmesg 2>&1 | grep -i -E 'ftdi|ttyUSB|0403|6001' | tail -n 180" > "%OUT%\03_dmesg_ftdi.txt" 2>&1
adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail > "%OUT%\04_iretail_package.txt" 2>&1
(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo ===== READ-ONLY VTK SYSTEM INFO =====
  findstr /I "SYSINFO_BEGIN VTK_CODEC TTY_FILE SERIAL_CONFIG TTY_OPEN RX_DRAINED VTK_IDL_OK SYSINFO_TX SYSINFO_RX SYSINFO_TIMEOUT VTK_STATUS VTK_POS_PARAMS VTK_BANK_PARAMS VTK_NET_PARAMS VTK_PAYMENT_ROUTE VTK_SYSTEM_INFO SYSINFO_END" "%OUT%\01_vendotek_system_info_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [7/8] Restoring normal i-Retail UI...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity >nul 2>nul

echo [8/8] Creating ZIP archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo VENDOTEK SYSTEM INFO TEST COMPLETE. Outcome: %OUTCOME%
echo No financial command was sent.
echo.
echo Publish with:
echo   call GIT_116_PUBLISH_VENDOTEK_SYSTEM_INFO_RESULT.bat
echo ============================================================
pause
exit /b 0
