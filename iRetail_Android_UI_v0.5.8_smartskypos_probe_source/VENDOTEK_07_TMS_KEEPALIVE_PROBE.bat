@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
if not defined JL22 set "JL22=192.168.1.192:5555"
set "OUTCOME=WAITING"
set "WAITLOG=%TEMP%\iretail_vendotek_tms_probe.log"

echo ============================================================
echo i-Retail v0.5.27 - VENDOTEK TMS KEEPALIVE PROBE
echo ============================================================
echo JL22: %JL22%
echo.
echo IMPORTANT:
echo   - This is NON-FINANCIAL. It cannot send VRP/FIN/ABR/DIS.
echo   - It sends exactly ONE POS Management command: tag 10 = A.
echo   - A means Send keepalive / synchronize terminal with TMS.
echo   - If remote configuration is already staged in TMS, synchronization
echo     MAY allow the terminal to receive/apply that existing configuration.
echo   - It does NOT send SW update, restart, log upload or settlement.
echo   - It does NOT implement the VTK Internet proxy in this test.
echo ============================================================
echo.
set "CONFIRM="
set /p "CONFIRM=Type exactly TMS A to authorize this one TMS synchronization request: "
if /I not "%CONFIRM%"=="TMS A" (
  echo [CANCELLED] Exact authorization was not entered. No VTK message was sent.
  pause
  exit /b 10
)

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

echo [1/9] Verifying Vendotek FTDI and ttyUSB0...
adb -s "%JL22%" shell lsusb | findstr /I "0403:6001" >nul
if errorlevel 1 (
  echo [ERROR] FTDI 0403:6001 is not visible. No protocol write was sent.
  pause
  exit /b 4
)
adb -s "%JL22%" shell test -e /dev/ttyUSB0
if errorlevel 1 (
  echo [ERROR] /dev/ttyUSB0 does not exist. No protocol write was sent.
  pause
  exit /b 5
)

echo [2/9] Building v0.5.27 diagnostic APK...
call BUILD_WINDOWS_CLI.bat
if errorlevel 1 (
  echo [ERROR] Build failed. No protocol write was sent.
  pause
  exit /b 6
)
set "APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APK%" (
  echo [ERROR] APK not found: %APK%
  pause
  exit /b 7
)

echo [3/9] Installing TMS probe on JL22...
adb -s "%JL22%" install -r "%APK%"
if errorlevel 1 (
  echo [ERROR] APK installation failed. No protocol write was sent.
  pause
  exit /b 8
)

echo [4/9] Starting explicitly armed TMS keepalive probe...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" logcat -c
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.vendotek.VendotekTmsKeepaliveDiagnosticActivity --ez allow_tms_keepalive true
if errorlevel 1 (
  set "OUTCOME=ACTIVITY_START_FAILED"
  goto COLLECT
)

echo [5/9] Waiting for IDL, STATUS, one TMS A request, observation and final STATUS...
for /l %%S in (1,1,125) do (
  adb -s "%JL22%" logcat -d -v brief IretailVendotek:I *:S > "%WAITLOG%" 2>&1
  findstr /C:"VTK_TMS_PROBE_COMPLETE" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=TMS_PROBE_COMPLETE"
    goto RESULT_SEEN
  )
  findstr /C:"VTK_TMS_NOT_AUTHORIZED" /C:"VTK_CODEC_SELFTEST_FAILED" /C:"VTK_TTY_ACCESS_DENIED" /C:"VTK_SERIAL_CONFIG_ERROR" /C:"VTK_TMS_IDL_TIMEOUT" /C:"VTK_TMS_PROBE_ERROR" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=TMS_PROBE_ERROR"
    goto RESULT_SEEN
  )
  timeout /t 1 /nobreak >nul
)
set "OUTCOME=WINDOWS_WAIT_TIMEOUT"

:RESULT_SEEN
echo Result: %OUTCOME%

:COLLECT
echo [6/9] Collecting evidence...
set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "vendotek_tms_logs" mkdir "vendotek_tms_logs"
set "OUT=vendotek_tms_logs\VENDOTEK_TMS_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo timestamp=%TS%
  echo outcome=%OUTCOME%
  echo usb=0403:6001 FTDI FT232R
  echo tty=/dev/ttyUSB0
  echo serial=115200_8N1_NO_FLOW
  echo management_command=TMS_KEEPALIVE_A_ONCE
  echo financial_commands=NONE
  echo internet_proxy=NOT_IMPLEMENTED_IN_THIS_PROBE
) > "%OUT%\00_info.txt"

adb -s "%JL22%" logcat -d -v threadtime IretailVendotek:V AndroidRuntime:E ActivityManager:I *:S > "%OUT%\01_vendotek_tms_logcat.txt" 2>&1
(
  adb -s "%JL22%" shell lsusb
  adb -s "%JL22%" shell ls -l /dev/ttyUSB0
  adb -s "%JL22%" shell cat /proc/tty/driver/usbserial
  adb -s "%JL22%" shell readlink -f /sys/class/tty/ttyUSB0/device/driver
) > "%OUT%\02_transport.txt" 2>&1
(
  adb -s "%JL22%" shell ip addr
  adb -s "%JL22%" shell ip route
  adb -s "%JL22%" shell getprop net.dns1
  adb -s "%JL22%" shell getprop net.dns2
) > "%OUT%\03_jl22_network.txt" 2>&1
adb -s "%JL22%" shell "dmesg 2>&1 | grep -i -E 'ftdi|ttyUSB|0403|6001' | tail -n 180" > "%OUT%\04_dmesg_ftdi.txt" 2>&1
(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo ===== VENDOTEK TMS KEEPALIVE PROBE =====
  findstr /I "TMS_PROBE_BEGIN VTK_CODEC TTY_FILE SERIAL_CONFIG TTY_OPEN RX_DRAINED VTK_IDL_OK STATUS_BEFORE TMS_KEEPALIVE_TX TMS_RX TMS_OBSERVATION STATUS_AFTER VTK_TMS_RESULT VTK_TMS_PROBE_COMPLETE TMS_PROBE_END" "%OUT%\01_vendotek_tms_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [7/9] Restoring normal i-Retail UI...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity >nul 2>nul

echo [8/9] Creating ZIP archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo [9/9] Done.
echo.
echo ============================================================
echo VENDOTEK TMS KEEPALIVE PROBE COMPLETE. Outcome: %OUTCOME%
echo Exactly one TMS keepalive A command was authorized.
echo No VRP/FIN/ABR/DIS/SW-update/restart/log-upload/settlement was sent.
echo.
echo Publish with:
echo   call GIT_119_PUBLISH_VENDOTEK_TMS_RESULT.bat
echo ============================================================
pause
exit /b 0
