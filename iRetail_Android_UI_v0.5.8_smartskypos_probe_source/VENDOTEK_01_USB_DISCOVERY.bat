@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
if not defined JL22 set "JL22=192.168.1.192:5555"

echo ============================================================
echo i-Retail v0.5.23 - VENDOTEK USB DISCOVERY ON JL22
echo ============================================================
echo JL22: %JL22%
echo.
echo SAFETY:
echo   READ-ONLY hardware discovery.
echo   This script sends NO VTK messages and NO financial commands.
echo   It does not change Vendotek settings.
echo.
echo BEFORE CONTINUING:
echo   1. Disconnect Kozen from the JL22 USB port used for POS.
echo   2. Connect the Vendotek terminal to that JL22 USB Host port.
echo   3. Keep Vendotek powered by its normal approved power source.
echo   4. Wait 5-10 seconds after connecting it.
echo ============================================================
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

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"

if not exist "vendotek_usb_logs" mkdir "vendotek_usb_logs"
set "OUT=vendotek_usb_logs\VENDOTEK_USB_DISCOVERY_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo timestamp=%TS%
  echo safety=READ_ONLY_NO_VTK_NO_FINANCIAL_COMMANDS
  echo expected_target=Vendotek connected to JL22 USB Host
) > "%OUT%\00_info.txt"

echo [1/10] Windows ADB inventory...
adb devices -l > "%OUT%\01_windows_adb_devices.txt" 2>&1

echo [2/10] JL22 identity and USB properties...
(
  adb -s "%JL22%" shell getprop ro.product.manufacturer
  adb -s "%JL22%" shell getprop ro.product.model
  adb -s "%JL22%" shell getprop ro.build.version.release
  adb -s "%JL22%" shell getprop ro.build.version.sdk
  adb -s "%JL22%" shell getprop sys.usb.config
  adb -s "%JL22%" shell getprop sys.usb.state
) > "%OUT%\02_jl22_identity.txt" 2>&1

echo [3/10] lsusb and USB tree...
adb -s "%JL22%" shell lsusb > "%OUT%\03_lsusb.txt" 2>&1
adb -s "%JL22%" shell "lsusb -t 2>/dev/null || true" > "%OUT%\04_lsusb_tree.txt" 2>&1

echo [4/10] Android dumpsys usb...
adb -s "%JL22%" shell dumpsys usb > "%OUT%\05_dumpsys_usb.txt" 2>&1

echo [5/10] Raw USB device descriptors from sysfs...
adb -s "%JL22%" shell "for d in /sys/bus/usb/devices/*; do if [ -f $d/idVendor ]; then echo ============================================================; echo DEVICE=$d; echo idVendor:; cat $d/idVendor 2>/dev/null; echo idProduct:; cat $d/idProduct 2>/dev/null; echo manufacturer:; cat $d/manufacturer 2>/dev/null; echo product:; cat $d/product 2>/dev/null; echo serial:; cat $d/serial 2>/dev/null; echo busnum:; cat $d/busnum 2>/dev/null; echo devnum:; cat $d/devnum 2>/dev/null; echo speed:; cat $d/speed 2>/dev/null; echo bDeviceClass:; cat $d/bDeviceClass 2>/dev/null; echo bDeviceSubClass:; cat $d/bDeviceSubClass 2>/dev/null; echo bDeviceProtocol:; cat $d/bDeviceProtocol 2>/dev/null; echo bNumConfigurations:; cat $d/bNumConfigurations 2>/dev/null; echo bNumInterfaces:; cat $d/bNumInterfaces 2>/dev/null; echo uevent:; cat $d/uevent 2>/dev/null; fi; done" > "%OUT%\06_usb_devices_sysfs.txt" 2>&1

echo [6/10] USB interfaces, drivers and endpoints...
adb -s "%JL22%" shell "for i in /sys/bus/usb/devices/*:*; do if [ -f $i/bInterfaceClass ]; then echo ============================================================; echo INTERFACE=$i; echo bInterfaceNumber:; cat $i/bInterfaceNumber 2>/dev/null; echo bInterfaceClass:; cat $i/bInterfaceClass 2>/dev/null; echo bInterfaceSubClass:; cat $i/bInterfaceSubClass 2>/dev/null; echo bInterfaceProtocol:; cat $i/bInterfaceProtocol 2>/dev/null; echo DRIVER:; readlink -f $i/driver 2>/dev/null; echo uevent:; cat $i/uevent 2>/dev/null; for e in $i/ep_*; do if [ -d $e ]; then echo ENDPOINT=$e; echo bEndpointAddress:; cat $e/bEndpointAddress 2>/dev/null; echo bmAttributes:; cat $e/bmAttributes 2>/dev/null; echo wMaxPacketSize:; cat $e/wMaxPacketSize 2>/dev/null; echo bInterval:; cat $e/bInterval 2>/dev/null; fi; done; fi; done" > "%OUT%\07_usb_interfaces_endpoints.txt" 2>&1

echo [7/10] TTY devices and kernel drivers...
adb -s "%JL22%" shell "cat /proc/tty/drivers 2>/dev/null; echo ===== DEV TTY =====; ls -l /dev/ttyACM* /dev/ttyUSB* /dev/ttyS* /dev/ttyHS* 2>&1; echo ===== SYS CLASS TTY =====; for t in /sys/class/tty/ttyACM* /sys/class/tty/ttyUSB*; do if [ -e $t ]; then echo TTY=$t; readlink -f $t/device 2>/dev/null; readlink -f $t/device/driver 2>/dev/null; cat $t/device/uevent 2>/dev/null; fi; done" > "%OUT%\08_tty_inventory.txt" 2>&1

echo [8/10] Recent kernel/logcat USB evidence...
adb -s "%JL22%" shell "dmesg 2>&1 | tail -n 350" > "%OUT%\09_dmesg_tail.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime > "%OUT%\10_logcat_full.txt" 2>&1
findstr /I "usb tty cdc acm serial ftdi ch34 pl2303 vendotek" "%OUT%\10_logcat_full.txt" > "%OUT%\11_logcat_usb_filtered.txt" 2>&1

echo [9/10] Building concise summary...
(
  echo ===== VENDOTEK USB DISCOVERY =====
  echo Safety: READ ONLY - no VTK and no financial commands
  echo.
  echo ===== LSUSB =====
  type "%OUT%\03_lsusb.txt"
  echo.
  echo ===== USB DEVICE IDENTIFIERS =====
  findstr /I "DEVICE= idVendor idProduct manufacturer product serial speed" "%OUT%\06_usb_devices_sysfs.txt"
  echo.
  echo ===== USB INTERFACES / DRIVERS =====
  findstr /I "INTERFACE= bInterfaceNumber bInterfaceClass bInterfaceSubClass bInterfaceProtocol DRIVER ENDPOINT= bEndpointAddress bmAttributes wMaxPacketSize" "%OUT%\07_usb_interfaces_endpoints.txt"
  echo.
  echo ===== TTY CANDIDATES =====
  findstr /I "ttyACM ttyUSB TTY=" "%OUT%\08_tty_inventory.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo [10/10] Creating ZIP archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo VENDOTEK USB DISCOVERY COMPLETE
echo No VTK message or payment command was sent.
echo.
echo Publish the result with:
echo   call GIT_113_PUBLISH_VENDOTEK_DISCOVERY.bat
echo ============================================================
pause
exit /b 0
