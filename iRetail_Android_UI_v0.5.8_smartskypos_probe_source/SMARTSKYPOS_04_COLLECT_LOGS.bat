@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

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
if not exist "smartskypos_logs" mkdir "smartskypos_logs"
set "OUT=smartskypos_logs\SmartSkyPOS_KozenP12_%TS%"
mkdir "%OUT%"

echo [COLLECT] SmartSkyPOS/i-Retail diagnostic logcat...
adb logcat -d -v threadtime SmartSkyPOSDiag:I AndroidRuntime:E *:S > "%OUT%\01_smartskypos_logcat.txt"

echo [COLLECT] Device identity...
(
    adb shell getprop ro.product.manufacturer
    adb shell getprop ro.product.model
    adb shell getprop ro.build.version.release
    adb shell getprop ro.build.version.sdk
) > "%OUT%\02_device.txt"

echo [COLLECT] Installed package data...
adb shell dumpsys package com.skytech.smartskypos > "%OUT%\03_smartskypos_package.txt"
adb shell dumpsys package com.coffeeonelove.iretail > "%OUT%\04_iretail_package.txt"

echo [COLLECT] Service state...
adb shell dumpsys activity services com.skytech.smartskypos > "%OUT%\05_smartskypos_services.txt"

echo.
echo [SUCCESS] Files collected:
echo %CD%\%OUT%
echo.
echo PAN/CVV/EMV data are not written by the i-Retail diagnostic logger.
echo Send the whole folder (or ZIP it) for the next integration step.
pause
exit /b 0
