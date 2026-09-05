@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "LABEL=%~1"
if not defined LABEL set "LABEL=ANDROID_DEVICE"

where adb >nul 2>nul
if errorlevel 1 (
    echo [ERROR] adb was not found in PATH.
    pause
    exit /b 2
)

adb wait-for-device
if errorlevel 1 (
    echo [ERROR] Device is not available over adb.
    pause
    exit /b 3
)

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"

if not exist "usb_probe_logs" mkdir "usb_probe_logs"
set "OUT=usb_probe_logs\USB_%LABEL%_%TS%"
mkdir "%OUT%"

echo ============================================================
echo USB capability probe: %LABEL%
echo ============================================================
echo This probe is READ-ONLY. It does not change USB mode or settings.
echo Output: %CD%\%OUT%
echo ============================================================
echo.

echo [1/12] ADB identity...
adb devices -l > "%OUT%\01_adb_devices.txt" 2>&1
(
  adb shell getprop ro.product.manufacturer
  adb shell getprop ro.product.model
  adb shell getprop ro.build.version.release
  adb shell getprop ro.build.version.sdk
  adb shell getprop ro.hardware
  adb shell getprop ro.board.platform
) > "%OUT%\02_identity.txt" 2>&1

echo [2/12] Android features...
adb shell pm list features > "%OUT%\03_features.txt" 2>&1

echo [3/12] USB properties...
adb shell getprop > "%OUT%\04_getprop_all.txt" 2>&1
findstr /I "usb adb gadget rndis accessory mtp ptp serial function configfs" "%OUT%\04_getprop_all.txt" > "%OUT%\05_getprop_usb_filtered.txt" 2>&1

echo [4/12] dumpsys usb...
adb shell dumpsys usb > "%OUT%\06_dumpsys_usb.txt" 2>&1

echo [5/12] Legacy Android USB gadget sysfs...
(
  echo ===== ls /sys/class/android_usb =====
  adb shell ls -la /sys/class/android_usb
  echo.
  echo ===== ls /sys/class/android_usb/android0 =====
  adb shell ls -la /sys/class/android_usb/android0
  echo.
  echo ===== functions =====
  adb shell cat /sys/class/android_usb/android0/functions
  echo.
  echo ===== state =====
  adb shell cat /sys/class/android_usb/android0/state
  echo.
  echo ===== enable =====
  adb shell cat /sys/class/android_usb/android0/enable
  echo.
  echo ===== idVendor =====
  adb shell cat /sys/class/android_usb/android0/idVendor
  echo.
  echo ===== idProduct =====
  adb shell cat /sys/class/android_usb/android0/idProduct
) > "%OUT%\07_legacy_android_usb.txt" 2>&1

echo [6/12] ConfigFS USB gadget tree...
(
  echo ===== /config/usb_gadget =====
  adb shell ls -la /config/usb_gadget
  echo.
  echo ===== /config/usb_gadget/g1 =====
  adb shell ls -la /config/usb_gadget/g1
  echo.
  echo ===== g1/functions =====
  adb shell ls -la /config/usb_gadget/g1/functions
  echo.
  echo ===== g1/configs/b.1 =====
  adb shell ls -la /config/usb_gadget/g1/configs/b.1
) > "%OUT%\08_configfs_usb.txt" 2>&1

echo [7/12] USB command interfaces...
(
  echo ===== cmd usb =====
  adb shell cmd usb
  echo.
  echo ===== cmd usb get-functions =====
  adb shell cmd usb get-functions
  echo.
  echo ===== svc usb =====
  adb shell svc usb
  echo.
  echo ===== svc usb getFunctions =====
  adb shell svc usb getFunctions
) > "%OUT%\09_usb_commands.txt" 2>&1

echo [8/12] Network interfaces (for possible USB RNDIS/Ethernet transport)...
(
  echo ===== ip addr =====
  adb shell ip addr
  echo.
  echo ===== ip route =====
  adb shell ip route
  echo.
  echo ===== /proc/net/dev =====
  adb shell cat /proc/net/dev
) > "%OUT%\10_network.txt" 2>&1

echo [9/12] Character devices relevant to USB serial...
(
  adb shell ls -la /dev/ttyGS0
  adb shell ls -la /dev/ttyGS1
  adb shell ls -la /dev/ttyACM0
  adb shell ls -la /dev/ttyUSB0
) > "%OUT%\11_usb_serial_devices.txt" 2>&1

echo [10/12] Kernel modules and mounts...
(
  echo ===== /proc/modules =====
  adb shell cat /proc/modules
  echo.
  echo ===== mount =====
  adb shell mount
) > "%OUT%\12_kernel_mounts.txt" 2>&1

echo [11/12] USB-related system settings...
(
  echo adb_enabled:
  adb shell settings get global adb_enabled
  echo development_settings_enabled:
  adb shell settings get global development_settings_enabled
  echo usb_mass_storage_enabled:
  adb shell settings get global usb_mass_storage_enabled
) > "%OUT%\13_settings.txt" 2>&1

echo [12/12] Kernel log snapshot where permitted...
adb shell dmesg > "%OUT%\14_dmesg.txt" 2>&1

(
  echo label=%LABEL%
  echo timestamp=%TS%
  echo probe=USB_07_CAPABILITY_PROBE
  echo mode=READ_ONLY
) > "%OUT%\00_probe_info.txt"

echo.
echo [ZIP] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo DONE. Send the resulting USB_%LABEL%_*.zip.
echo No USB configuration was changed.
echo ============================================================
pause
exit /b 0
