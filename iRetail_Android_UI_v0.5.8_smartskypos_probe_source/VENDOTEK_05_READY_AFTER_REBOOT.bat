@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
if not defined JL22 set "JL22=192.168.1.192:5555"
set "OUTCOME=WAITING"
set "WAITLOG=%TEMP%\iretail_vendotek_ready_watch.log"

echo ============================================================
echo i-Retail v0.5.25 - VENDOTEK READY STATE AFTER COLD BOOT
echo ============================================================
echo JL22: %JL22%
echo.
echo SAFETY:
echo   - NO payment request is sent.
echo   - NO VRP, FIN, ABR or DIS is sent.
echo   - Only IDL and read-only SystemInfo STATUS are sent.
echo   - Messages are spaced by at least 10 seconds.
echo.
echo BEFORE CONTINUING:
echo   1. Power-cycle ONLY the Vendotek terminal.
echo   2. Keep it without power for about 10 seconds.
echo   3. Power it again and wait until its LEDs settle.
echo   4. Do not press or change anything else.
echo.
pause

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

echo [1/9] Waiting for Vendotek FTDI after power-cycle...
set "FOUND="
for /l %%S in (1,1,45) do (
  adb -s "%JL22%" shell lsusb 2>nul | findstr /I "0403:6001" >nul
  if not errorlevel 1 (
    adb -s "%JL22%" shell test -e /dev/ttyUSB0 >nul 2>nul
    if not errorlevel 1 (
      set "FOUND=1"
      goto DEVICE_READY
    )
  )
  timeout /t 1 /nobreak >nul
)
:DEVICE_READY
if not defined FOUND (
  echo [ERROR] Vendotek FTDI 0403:6001 /dev/ttyUSB0 did not return after power-cycle.
  pause
  exit /b 4
)

echo [2/9] Building v0.5.25 readiness probe...
call BUILD_WINDOWS_CLI.bat
if errorlevel 1 (
  echo [ERROR] Build failed. No VTK message was sent.
  pause
  exit /b 5
)
set "APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APK%" (
  echo [ERROR] APK not found: %APK%
  pause
  exit /b 6
)

echo [3/9] Installing readiness probe on JL22...
adb -s "%JL22%" install -r "%APK%"
if errorlevel 1 (
  echo [ERROR] APK installation failed. No VTK message was sent.
  pause
  exit /b 7
)

echo [4/9] Starting STATUS watch...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" logcat -c
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.vendotek.VendotekStatusWatchActivity
if errorlevel 1 (
  set "OUTCOME=ACTIVITY_START_FAILED"
  goto COLLECT
)

echo [5/9] Watching Vendotek readiness for up to about 100 seconds...
for /l %%S in (1,1,125) do (
  adb -s "%JL22%" logcat -d -v brief IretailVendotek:I *:S > "%WAITLOG%" 2>&1
  findstr /C:"VTK_READY_STABLE" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=READY_STABLE"
    goto RESULT_SEEN
  )
  findstr /C:"VTK_SERVICE_STATE_PERSISTENT" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=SERVICE_STATE_PERSISTENT"
    goto RESULT_SEEN
  )
  findstr /C:"VTK_READY_WATCH_COMPLETE" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=WATCH_COMPLETE_NOT_READY"
    goto RESULT_SEEN
  )
  findstr /C:"VTK_CODEC_SELFTEST_FAILED" /C:"VTK_TTY_ACCESS_DENIED" /C:"VTK_SERIAL_CONFIG_ERROR" /C:"VTK_READY_WATCH_IDL_TIMEOUT" /C:"VTK_READY_WATCH_ERROR" "%WAITLOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=WATCH_ERROR"
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
if not exist "vendotek_ready_logs" mkdir "vendotek_ready_logs"
set "OUT=vendotek_ready_logs\VENDOTEK_READY_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo timestamp=%TS%
  echo outcome=%OUTCOME%
  echo usb=0403:6001 FTDI FT232R
  echo tty=/dev/ttyUSB0
  echo protocol_writes=IDL_AND_STATUS_ONLY
  echo financial_commands=NONE
) > "%OUT%\00_info.txt"

adb -s "%JL22%" logcat -d -v threadtime IretailVendotek:V AndroidRuntime:E ActivityManager:I *:S > "%OUT%\01_vendotek_ready_logcat.txt" 2>&1
(
  adb -s "%JL22%" shell lsusb
  adb -s "%JL22%" shell ls -l /dev/ttyUSB0
  adb -s "%JL22%" shell cat /proc/tty/driver/usbserial
  adb -s "%JL22%" shell readlink -f /sys/class/tty/ttyUSB0/device/driver
) > "%OUT%\02_transport.txt" 2>&1
adb -s "%JL22%" shell "dmesg 2>&1 | grep -i -E 'ftdi|ttyUSB|0403|6001' | tail -n 180" > "%OUT%\03_dmesg_ftdi.txt" 2>&1
(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo ===== VENDOTEK STATUS WATCH =====
  findstr /I "READY_WATCH VTK_CODEC TTY_FILE SERIAL_CONFIG TTY_OPEN RX_DRAINED VTK_IDL STATUS_TX STATUS_SAMPLE STATUS_PLAIN VTK_SERVICE VTK_READY READY_WATCH_END" "%OUT%\01_vendotek_ready_logcat.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [7/9] Restoring normal i-Retail UI...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity >nul 2>nul

echo [8/9] Creating ZIP archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo [9/9] Done.
echo.
echo ============================================================
echo VENDOTEK READY STATE TEST COMPLETE. Outcome: %OUTCOME%
echo No financial command was sent.
echo.
echo Publish with:
echo   call GIT_117_PUBLISH_VENDOTEK_READY_RESULT.bat
echo ============================================================
pause
exit /b 0
