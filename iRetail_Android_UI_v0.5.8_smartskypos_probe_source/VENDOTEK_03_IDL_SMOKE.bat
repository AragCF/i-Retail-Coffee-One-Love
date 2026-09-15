@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
if not defined JL22 set "JL22=192.168.1.192:5555"
set "OUTCOME=WAITING"
set "WAITLOG=%TEMP%\iretail_vendotek_idl.log"

echo ============================================================
echo i-Retail v0.5.23 - VENDOTEK VTK IDL SMOKE TEST
echo ============================================================
echo JL22: %JL22%
echo.
echo SAFETY:
echo   - This test sends exactly ONE VTK IDL message.
echo   - IDL only establishes/refreshes the idle link.
echo   - NO VRP payment request is sent.
echo   - NO FIN, ABR or DIS is sent.
echo   - NO financial command is sent.
echo.
echo Target transport:
echo   FTDI FT232R 0403:6001 via kernel ftdi_sio /dev/ttyUSB0
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
  echo [ERROR] FTDI 0403:6001 is not visible on JL22. No VTK message was sent.
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

echo [3/8] Installing v0.5.23 Vendotek IDL probe on JL22...
adb -s "%JL22%" install -r "%APK%"
if errorlevel 1 (
  echo [ERROR] APK installation failed. No VTK message was sent.
  pause
  exit /b 8
)

echo [4/8] Starting app-level IDL probe...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" logcat -c
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.vendotek.VendotekIdlDiagnosticActivity
if errorlevel 1 (
  set "OUTCOME=ACTIVITY_START_FAILED"
  echo [ERROR] Could not start VendotekIdlDiagnosticActivity.
  goto COLLECT
)

echo [5/8] Waiting for IDL result...
for /l %%S in (1,1,30) do (
  adb -s "%JL22%" logcat -d -v brief IretailVendotek:I *:S > "%WAITLOG%" 2>&1
  findstr /C:"VTK_IDL_OK" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=IDL_OK"
    goto RESULT_SEEN
  )
  findstr /C:"VTK_TTY_ACCESS_DENIED" /C:"VTK_SERIAL_CONFIG_ERROR" /C:"VTK_CODEC_SELFTEST_FAILED" /C:"VTK_IDL_ERROR" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=IDL_ERROR"
    goto RESULT_SEEN
  )
  findstr /C:"VTK_IDL_TIMEOUT" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=IDL_TIMEOUT"
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
if not exist "vendotek_idl_logs" mkdir "vendotek_idl_logs"
set "OUT=vendotek_idl_logs\VENDOTEK_IDL_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo timestamp=%TS%
  echo outcome=%OUTCOME%
  echo usb=0403:6001 FTDI FT232R
  echo tty=/dev/ttyUSB0
  echo serial=115200_8N1_NO_FLOW
  echo protocol_write=IDL_ONLY
  echo financial_commands=NONE
) > "%OUT%\00_info.txt"

adb -s "%JL22%" logcat -d -v threadtime IretailVendotek:V AndroidRuntime:E ActivityManager:I *:S > "%OUT%\01_vendotek_idl_logcat.txt" 2>&1
(
  adb -s "%JL22%" shell lsusb
  adb -s "%JL22%" shell ls -l /dev/ttyUSB0
  adb -s "%JL22%" shell ls -lZ /dev/ttyUSB0
  adb -s "%JL22%" shell cat /proc/tty/driver/usbserial
  adb -s "%JL22%" shell readlink -f /sys/class/tty/ttyUSB0/device/driver
) > "%OUT%\02_transport.txt" 2>&1
adb -s "%JL22%" shell "dmesg 2>&1 | grep -i -E 'ftdi|ttyUSB|0403|6001' | tail -n 160" > "%OUT%\03_dmesg_ftdi.txt" 2>&1
adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail > "%OUT%\04_iretail_package.txt" 2>&1
(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo ===== APP-LEVEL VTK LOG =====
  findstr /I "PROBE_BEGIN VTK_CODEC TTY_FILE SERIAL_CONFIG TTY_OPEN RX_DRAINED IDL_TX IDL_RX VTK_RX VTK_IDL PROBE_END" "%OUT%\01_vendotek_idl_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [7/8] Closing diagnostic screen and restoring normal i-Retail UI...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity >nul 2>nul

echo [8/8] Creating ZIP archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo VENDOTEK IDL SMOKE TEST COMPLETE. Outcome: %OUTCOME%
echo Exactly one non-financial IDL was allowed by this test.
echo No VRP/FIN/ABR/DIS was sent.
echo.
echo Publish with:
echo   call GIT_115_PUBLISH_VENDOTEK_IDL_RESULT.bat
echo ============================================================
pause
exit /b 0
