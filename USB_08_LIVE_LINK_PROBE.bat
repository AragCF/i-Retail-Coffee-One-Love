@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo USB LIVE LINK PROBE: JL22 host ^<^> Kozen P12
echo ============================================================
echo READ-ONLY. This script does not change USB configuration.
echo.
echo Preconditions:
echo   1. JL22 is connected to THIS Windows PC over ADB.
echo   2. Kozen P12 is powered on but NOT yet connected to JL22.
echo   3. Keep the JL22 ADB/service connection to Windows in place.
echo   4. For the JL22-Kozen link use a FREE USB HOST port on JL22.
echo   5. On Kozen use the SAME device-side connector/cable that worked
echo      when Kozen was connected to Windows.
echo.
echo IMPORTANT: do NOT use a USB-A-to-USB-A male cable.
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 (
    echo [ERROR] adb was not found in PATH.
    pause
    exit /b 2
)

set "ADB_COUNT=0"
for /f "skip=1 tokens=1,2" %%A in ('adb devices 2^>nul') do (
    if "%%B"=="device" set /a ADB_COUNT+=1
)
if not "%ADB_COUNT%"=="1" (
    echo [ERROR] Expected exactly one ADB device connected to Windows.
    echo Keep only JL22 connected to Windows for this probe.
    adb devices -l
    pause
    exit /b 3
)

adb wait-for-device
if errorlevel 1 (
    echo [ERROR] JL22 is not available over ADB.
    pause
    exit /b 4
)

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"

if not exist "usb_link_logs" mkdir "usb_link_logs"
set "OUT=usb_link_logs\USB_LINK_JL22_KOZEN_%TS%"
mkdir "%OUT%"

(
  echo timestamp=%TS%
  echo probe=USB_08_LIVE_LINK_PROBE
  echo mode=READ_ONLY
  echo expected_windows_adb_device=JL22
  echo topology=Windows-ADB-to-JL22 plus JL22-USB-HOST-to-Kozen
) > "%OUT%\00_probe_info.txt"

call :Capture BEFORE

echo.
echo ============================================================
echo BASELINE CAPTURED.
echo.
echo NOW CONNECT KOZEN P12 TO A FREE USB HOST PORT ON JL22.
echo.
echo Use the normal cable that previously connected Kozen to Windows:
echo   Kozen device-side connector ---^> JL22 USB HOST port
echo.
echo Leave Kozen powered on and unlocked. Do not launch payment.
echo After connecting, wait until Kozen/JL22 settle, then press any key.
echo ============================================================
pause >nul

echo Waiting 12 seconds for USB enumeration...
timeout /t 12 /nobreak >nul

call :Capture AFTER

echo [DIFF] Creating before/after comparisons...
fc /N "%OUT%\BEFORE_03_dumpsys_usb.txt" "%OUT%\AFTER_03_dumpsys_usb.txt" > "%OUT%\DIFF_01_dumpsys_usb.txt" 2>&1
fc /N "%OUT%\BEFORE_04_usb_sysfs.txt" "%OUT%\AFTER_04_usb_sysfs.txt" > "%OUT%\DIFF_02_usb_sysfs.txt" 2>&1
fc /N "%OUT%\BEFORE_06_network.txt" "%OUT%\AFTER_06_network.txt" > "%OUT%\DIFF_03_network.txt" 2>&1
fc /N "%OUT%\BEFORE_08_proc_devices.txt" "%OUT%\AFTER_08_proc_devices.txt" > "%OUT%\DIFF_04_proc_devices.txt" 2>&1

echo.
echo [ZIP] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo DONE.
echo Send USB_LINK_JL22_KOZEN_*.zip back for analysis.
echo.
echo You may now disconnect Kozen from JL22.
echo No USB settings were changed by this script.
echo ============================================================
pause
exit /b 0

:Capture
set "PFX=%~1"
echo [%PFX%] Identity...
(
  adb devices -l
  echo.
  adb shell getprop ro.product.manufacturer
  adb shell getprop ro.product.model
  adb shell getprop ro.build.version.release
  adb shell getprop ro.build.version.sdk
  adb shell getprop ro.hardware
  adb shell getprop ro.board.platform
) > "%OUT%\%PFX%_01_identity.txt" 2>&1

echo [%PFX%] USB properties...
adb shell getprop > "%OUT%\%PFX%_02_getprop_all.txt" 2>&1
findstr /I "usb adb gadget rndis accessory mtp ptp serial function configfs" "%OUT%\%PFX%_02_getprop_all.txt" > "%OUT%\%PFX%_02b_getprop_usb_filtered.txt" 2>&1

echo [%PFX%] dumpsys usb...
adb shell dumpsys usb > "%OUT%\%PFX%_03_dumpsys_usb.txt" 2>&1

echo [%PFX%] USB host/sysfs topology...
(
  echo ===== lsusb =====
  adb shell lsusb
  echo.
  echo ===== /sys/bus/usb/devices =====
  adb shell ls -la /sys/bus/usb/devices
  echo.
  echo ===== recursive device tree =====
  adb shell ls -laR /sys/bus/usb/devices
  echo.
  echo ===== vendor/product/class summary =====
  adb shell "for d in /sys/bus/usb/devices/*; do if [ -f \"$d/idVendor\" ]; then echo DEVICE=$d; cat $d/idVendor 2>/dev/null; cat $d/idProduct 2>/dev/null; cat $d/bDeviceClass 2>/dev/null; cat $d/product 2>/dev/null; cat $d/manufacturer 2>/dev/null; echo ---; fi; done"
) > "%OUT%\%PFX%_04_usb_sysfs.txt" 2>&1

echo [%PFX%] Kernel USB snapshot...
(
  echo ===== dmesg USB-related =====
  adb shell dmesg ^| findstr /I "usb xhci ehci ohci dwc gadget rndis accessory mtp adb"
) > "%OUT%\%PFX%_05_dmesg_usb.txt" 2>&1

echo [%PFX%] Network...
(
  adb shell ip addr
  echo.
  adb shell ip route
  echo.
  adb shell cat /proc/net/dev
) > "%OUT%\%PFX%_06_network.txt" 2>&1

echo [%PFX%] USB serial/device nodes...
(
  adb shell ls -la /dev/ttyACM0
  adb shell ls -la /dev/ttyUSB0
  adb shell ls -la /dev/ttyUSB1
  adb shell ls -la /dev/ttyGS0
  adb shell ls -la /dev/ttyGS1
) > "%OUT%\%PFX%_07_usb_serial_devices.txt" 2>&1

echo [%PFX%] proc devices and mounts...
(
  echo ===== /proc/bus/input/devices =====
  adb shell cat /proc/bus/input/devices
  echo.
  echo ===== /proc/tty/drivers =====
  adb shell cat /proc/tty/drivers
  echo.
  echo ===== mounts =====
  adb shell mount
) > "%OUT%\%PFX%_08_proc_devices.txt" 2>&1

exit /b 0
