@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
if not defined JL22 set "JL22=192.168.1.192:5555"

echo ============================================================
echo i-Retail v0.5.23 - VENDOTEK TTY ACCESS PROBE
echo ============================================================
echo JL22: %JL22%
echo.
echo SAFETY:
echo   READ-ONLY permission and serial-environment inspection.
echo   NO bytes are written to /dev/ttyUSB0.
echo   NO VTK message is sent.
echo   NO financial command is sent.
echo   Vendotek state/settings are not changed.
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

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"

if not exist "vendotek_tty_logs" mkdir "vendotek_tty_logs"
set "OUT=vendotek_tty_logs\VENDOTEK_TTY_ACCESS_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo timestamp=%TS%
  echo target=/dev/ttyUSB0
  echo target_usb=0403:6001 FTDI FT232R
  echo safety=READ_ONLY_NO_TTY_WRITE_NO_VTK_NO_FINANCIAL_COMMANDS
) > "%OUT%\00_info.txt"

echo [1/8] Checking JL22 and FTDI presence...
(
  adb -s "%JL22%" shell getprop ro.product.manufacturer
  adb -s "%JL22%" shell getprop ro.product.model
  adb -s "%JL22%" shell getprop ro.build.version.release
  adb -s "%JL22%" shell getprop ro.build.version.sdk
  adb -s "%JL22%" shell lsusb
  adb -s "%JL22%" shell ls -l /dev/ttyUSB0
  adb -s "%JL22%" shell ls -l /sys/class/tty/ttyUSB0/device/driver
  adb -s "%JL22%" shell readlink -f /sys/class/tty/ttyUSB0/device/driver
) > "%OUT%\01_identity_ftdi.txt" 2>&1

echo [2/8] Inspecting shell identity and effective filesystem permissions...
(
  echo ===== ID =====
  adb -s "%JL22%" shell id
  echo ===== TTY LS =====
  adb -s "%JL22%" shell ls -l /dev/ttyUSB0
  echo ===== TTY SELINUX CONTEXT =====
  adb -s "%JL22%" shell ls -lZ /dev/ttyUSB0
  echo ===== TTY STAT =====
  adb -s "%JL22%" shell stat /dev/ttyUSB0
  echo ===== SHELL ACCESS TESTS - DO NOT OPEN DEVICE =====
  adb -s "%JL22%" shell "test -e /dev/ttyUSB0; echo SHELL_EXISTS_RC=$?"
  adb -s "%JL22%" shell "test -r /dev/ttyUSB0; echo SHELL_READ_RC=$?"
  adb -s "%JL22%" shell "test -w /dev/ttyUSB0; echo SHELL_WRITE_RC=$?"
) > "%OUT%\02_shell_permissions.txt" 2>&1

echo [3/8] Inspecting SELinux / Android security mode...
(
  adb -s "%JL22%" shell getenforce
  adb -s "%JL22%" shell getprop ro.secure
  adb -s "%JL22%" shell getprop ro.debuggable
  adb -s "%JL22%" shell getprop ro.adb.secure
  adb -s "%JL22%" shell getprop service.adb.root
  adb -s "%JL22%" shell "command -v su 2>/dev/null || true"
) > "%OUT%\03_security.txt" 2>&1

echo [4/8] Inspecting i-Retail package uid and run-as access...
(
  echo ===== PACKAGE =====
  adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail
  echo ===== RUN-AS ID =====
  adb -s "%JL22%" shell run-as com.coffeeonelove.iretail id
  echo ===== RUN-AS ACCESS TESTS - DO NOT OPEN DEVICE =====
  adb -s "%JL22%" shell run-as com.coffeeonelove.iretail sh -c "test -e /dev/ttyUSB0; echo APP_EXISTS_RC=$?"
  adb -s "%JL22%" shell run-as com.coffeeonelove.iretail sh -c "test -r /dev/ttyUSB0; echo APP_READ_RC=$?"
  adb -s "%JL22%" shell run-as com.coffeeonelove.iretail sh -c "test -w /dev/ttyUSB0; echo APP_WRITE_RC=$?"
) > "%OUT%\04_app_permissions.txt" 2>&1

echo [5/8] Inspecting serial tooling and kernel tty registration...
(
  echo ===== COMMANDS =====
  adb -s "%JL22%" shell "command -v stty 2>/dev/null || true"
  adb -s "%JL22%" shell "command -v toybox 2>/dev/null || true"
  adb -s "%JL22%" shell "command -v busybox 2>/dev/null || true"
  adb -s "%JL22%" shell "command -v lsof 2>/dev/null || true"
  echo ===== STTY HELP ONLY - DEVICE IS NOT OPENED =====
  adb -s "%JL22%" shell "stty --help 2>&1 | head -n 80"
  echo ===== PROC TTY DRIVERS =====
  adb -s "%JL22%" shell cat /proc/tty/drivers
  echo ===== PROC USB SERIAL =====
  adb -s "%JL22%" shell cat /proc/tty/driver/usbserial
) > "%OUT%\05_serial_environment.txt" 2>&1

echo [6/8] Inspecting possible owners/users of tty without opening it...
(
  adb -s "%JL22%" shell "lsof /dev/ttyUSB0 2>&1 || true"
  echo ===== PROCESSES =====
  adb -s "%JL22%" shell ps -A
) > "%OUT%\06_processes.txt" 2>&1

echo [7/8] Capturing USB/driver diagnostics...
(
  adb -s "%JL22%" shell dumpsys usb
  echo ===== DMESG FTDI =====
  adb -s "%JL22%" shell "dmesg 2>&1 | grep -i -E 'ftdi|ttyUSB|0403|6001' | tail -n 120"
) > "%OUT%\07_usb_driver.txt" 2>&1

echo [8/8] Building summary and ZIP...
(
  echo ===== SAFETY =====
  echo READ_ONLY_NO_TTY_WRITE_NO_VTK_NO_FINANCIAL_COMMANDS
  echo.
  echo ===== TARGET =====
  echo Vendotek FTDI FT232R 0403:6001 expected at /dev/ttyUSB0
  echo.
  echo ===== SHELL PERMISSIONS =====
  findstr /I "ttyUSB0 SHELL_EXISTS_RC SHELL_READ_RC SHELL_WRITE_RC" "%OUT%\02_shell_permissions.txt"
  echo.
  echo ===== SECURITY =====
  type "%OUT%\03_security.txt"
  echo.
  echo ===== APP / RUN-AS =====
  findstr /I "userId= debuggable RUN-AS uid= APP_EXISTS_RC APP_READ_RC APP_WRITE_RC package:" "%OUT%\04_app_permissions.txt"
  echo.
  echo ===== SERIAL TOOLING =====
  findstr /I "stty toybox busybox ttyUSB usbserial" "%OUT%\05_serial_environment.txt"
  echo.
  echo ===== FTDI DRIVER =====
  findstr /I "0403 6001 FTDI ttyUSB ftdi_sio" "%OUT%\01_identity_ftdi.txt" "%OUT%\07_usb_driver.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo VENDOTEK TTY ACCESS PROBE COMPLETE
echo No byte was written to ttyUSB0. No VTK message was sent.
echo.
echo Publish with:
echo   call GIT_114_PUBLISH_VENDOTEK_TTY_ACCESS_RESULT.bat
echo ============================================================
pause
exit /b 0
