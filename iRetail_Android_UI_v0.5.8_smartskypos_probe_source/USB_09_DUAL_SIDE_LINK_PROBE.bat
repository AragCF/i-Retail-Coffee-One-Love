@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

rem Dual-sided READ-ONLY USB link probe.
rem It explicitly targets JL22 and Kozen by ADB serial/model so another
rem network-connected Android device cannot silently become the probe target.
rem
rem Optional explicit serials:
rem   USB_09_DUAL_SIDE_LINK_PROBE.bat <JL22_ADB_SERIAL> <KOZEN_ADB_SERIAL>
rem Example:
rem   USB_09_DUAL_SIDE_LINK_PROBE.bat 192.168.1.192:5555 192.168.31.134:5555

where adb >nul 2>nul
if errorlevel 1 (
    echo [ERROR] adb was not found in PATH.
    pause
    exit /b 2
)

adb start-server >nul 2>nul

set "JL22=%~1"
set "KOZEN=%~2"

if not defined JL22 (
    for /f "tokens=1" %%S in ('adb devices -l ^| findstr /I "model:M190"') do if not defined JL22 set "JL22=%%S"
)
if not defined KOZEN (
    for /f "tokens=1" %%S in ('adb devices -l ^| findstr /I "model:P12"') do if not defined KOZEN set "KOZEN=%%S"
)

echo ============================================================
echo USB DUAL-SIDE LINK PROBE: JL22 host ^<^> Kozen P12 device
echo ============================================================
echo READ-ONLY. No USB mode, payment, network or system setting is changed.
echo.
echo Current ADB devices:
adb devices -l
echo.

if not defined JL22 (
    echo [ERROR] JL22 was not found automatically as model:M190.
    echo Run: adb devices -l
    echo Then pass its serial as the first argument.
    pause
    exit /b 3
)
if not defined KOZEN (
    echo [ERROR] Kozen was not found automatically as model:P12.
    echo Run: adb devices -l
    echo Then pass its serial as the second argument.
    pause
    exit /b 4
)
if /I "%JL22%"=="%KOZEN%" (
    echo [ERROR] JL22 and Kozen resolved to the same ADB serial: %JL22%
    pause
    exit /b 5
)

echo Selected JL22 : %JL22%
echo Selected Kozen: %KOZEN%
echo.

adb -s "%JL22%" get-state >nul 2>nul
if errorlevel 1 (
    echo [ERROR] JL22 ADB endpoint is not online: %JL22%
    pause
    exit /b 6
)
adb -s "%KOZEN%" get-state >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Kozen ADB endpoint is not online: %KOZEN%
    pause
    exit /b 7
)

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"

if not exist "usb_dual_logs" mkdir "usb_dual_logs"
set "OUT=usb_dual_logs\USB_DUAL_JL22_KOZEN_%TS%"
mkdir "%OUT%"

(
  echo timestamp=%TS%
  echo probe=USB_09_DUAL_SIDE_LINK_PROBE
  echo mode=READ_ONLY
  echo jl22_adb_serial=%JL22%
  echo kozen_adb_serial=%KOZEN%
  echo expected_topology=JL22_USB_HOST_to_Kozen_USB_DEVICE
) > "%OUT%\00_probe_info.txt"

adb devices -l > "%OUT%\01_windows_adb_devices.txt" 2>&1

echo [JL22 1/7] Identity...
(
  adb -s "%JL22%" shell getprop ro.product.manufacturer
  adb -s "%JL22%" shell getprop ro.product.model
  adb -s "%JL22%" shell getprop ro.build.version.release
  adb -s "%JL22%" shell getprop ro.build.version.sdk
  adb -s "%JL22%" shell getprop ro.hardware
  adb -s "%JL22%" shell getprop ro.board.platform
) > "%OUT%\JL22_01_identity.txt" 2>&1

echo [JL22 2/7] USB framework state...
adb -s "%JL22%" shell dumpsys usb > "%OUT%\JL22_02_dumpsys_usb.txt" 2>&1

echo [JL22 3/7] USB bus enumeration...
(
  echo ===== lsusb =====
  adb -s "%JL22%" shell lsusb
  echo.
  echo ===== /sys/bus/usb/devices =====
  adb -s "%JL22%" shell ls -la /sys/bus/usb/devices
  echo.
  echo ===== VID/PID/manufacturer/product summary =====
  adb -s "%JL22%" shell "for d in /sys/bus/usb/devices/*; do if [ -f \"$d/idVendor\" ]; then echo DEVICE:$d; echo -n VID=; cat \"$d/idVendor\"; echo -n PID=; cat \"$d/idProduct\"; echo -n MANUFACTURER=; cat \"$d/manufacturer\" 2>/dev/null; echo -n PRODUCT=; cat \"$d/product\" 2>/dev/null; echo ----; fi; done"
) > "%OUT%\JL22_03_usb_bus.txt" 2>&1

echo [JL22 4/7] USB-related properties...
adb -s "%JL22%" shell getprop > "%OUT%\JL22_04_getprop_all.txt" 2>&1
findstr /I "usb adb gadget rndis accessory mtp ptp serial function configfs" "%OUT%\JL22_04_getprop_all.txt" > "%OUT%\JL22_04b_getprop_usb_filtered.txt" 2>&1

echo [JL22 5/7] Kernel USB snapshot...
adb -s "%JL22%" shell dmesg > "%OUT%\JL22_05_dmesg.txt" 2>&1
findstr /I "usb musb ehci ohci xhci gadget accessory" "%OUT%\JL22_05_dmesg.txt" > "%OUT%\JL22_05b_dmesg_usb_filtered.txt" 2>&1

echo [JL22 6/7] USB features and network...
adb -s "%JL22%" shell pm list features > "%OUT%\JL22_06_features.txt" 2>&1
(
  adb -s "%JL22%" shell ip addr
  adb -s "%JL22%" shell ip route
  adb -s "%JL22%" shell cat /proc/net/dev
) > "%OUT%\JL22_06_network.txt" 2>&1

echo [JL22 7/7] Process/device nodes...
(
  adb -s "%JL22%" shell ls -la /dev/ttyACM0
  adb -s "%JL22%" shell ls -la /dev/ttyUSB0
  adb -s "%JL22%" shell ls -la /dev/ttyUSB1
  adb -s "%JL22%" shell ls -la /dev/ttyGS0
  adb -s "%JL22%" shell ls -la /dev/ttyGS1
) > "%OUT%\JL22_07_usb_nodes.txt" 2>&1

echo [KOZEN 1/6] Identity...
(
  adb -s "%KOZEN%" shell getprop ro.product.manufacturer
  adb -s "%KOZEN%" shell getprop ro.product.model
  adb -s "%KOZEN%" shell getprop ro.build.version.release
  adb -s "%KOZEN%" shell getprop ro.build.version.sdk
  adb -s "%KOZEN%" shell getprop ro.hardware
  adb -s "%KOZEN%" shell getprop ro.board.platform
) > "%OUT%\KOZEN_01_identity.txt" 2>&1

echo [KOZEN 2/6] USB framework state...
adb -s "%KOZEN%" shell dumpsys usb > "%OUT%\KOZEN_02_dumpsys_usb.txt" 2>&1

echo [KOZEN 3/6] USB-related properties...
adb -s "%KOZEN%" shell getprop > "%OUT%\KOZEN_03_getprop_all.txt" 2>&1
findstr /I "usb adb gadget rndis accessory mtp ptp serial function configfs bootreason" "%OUT%\KOZEN_03_getprop_all.txt" > "%OUT%\KOZEN_03b_getprop_usb_filtered.txt" 2>&1

echo [KOZEN 4/6] USB features...
adb -s "%KOZEN%" shell pm list features > "%OUT%\KOZEN_04_features.txt" 2>&1

echo [KOZEN 5/6] Gadget/configfs state...
(
  echo ===== /config/usb_gadget =====
  adb -s "%KOZEN%" shell ls -la /config/usb_gadget
  echo.
  echo ===== /config/usb_gadget/g1/functions =====
  adb -s "%KOZEN%" shell ls -la /config/usb_gadget/g1/functions
  echo.
  echo ===== /config/usb_gadget/g1/configs/b.1 =====
  adb -s "%KOZEN%" shell ls -la /config/usb_gadget/g1/configs/b.1
) > "%OUT%\KOZEN_05_configfs.txt" 2>&1

echo [KOZEN 6/6] Network...
(
  adb -s "%KOZEN%" shell ip addr
  adb -s "%KOZEN%" shell ip route
) > "%OUT%\KOZEN_06_network.txt" 2>&1

echo [SUMMARY] Extracting high-value evidence...
(
  echo ===== SELECTED ADB ENDPOINTS =====
  echo JL22=%JL22%
  echo KOZEN=%KOZEN%
  echo.
  echo ===== JL22 USB DEVICES =====
  type "%OUT%\JL22_03_usb_bus.txt"
  echo.
  echo ===== KOZEN USB ROLE/STATE =====
  findstr /I "connected configured current_mode power_role data_role kernel_state supported_modes source_power sink_power usb_charging" "%OUT%\KOZEN_02_dumpsys_usb.txt"
  echo.
  echo ===== KOZEN sys.usb =====
  findstr /I "sys.usb.config sys.usb.state persist.sys.usb.config ro.boot.bootreason" "%OUT%\KOZEN_03b_getprop_usb_filtered.txt"
) > "%OUT%\SUMMARY.txt" 2>&1

echo.
echo [ZIP] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo DONE.
echo Send USB_DUAL_JL22_KOZEN_*.zip or publish it to Git.
echo This probe did not change USB configuration.
echo ============================================================
pause
exit /b 0
