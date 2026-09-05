@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo i-Retail SmartSkyPOS / Kozen P12 - BUILD + INSTALL
echo ============================================================
echo.

call BUILD_WINDOWS_CLI.bat
if errorlevel 1 (
    echo [ERROR] Build failed.
    pause
    exit /b 1
)

where adb >nul 2>nul
if errorlevel 1 (
    echo [ERROR] adb was not found in PATH.
    echo Install Android SDK Platform Tools and add platform-tools to PATH.
    pause
    exit /b 2
)

set "APK=dist\iRetail_Android_UI_v0.5.8-smartskypos-probe-debug-latest.apk"
if not exist "%APK%" (
    echo [ERROR] APK not found:
    echo %CD%\%APK%
    pause
    exit /b 3
)

echo [ADB] Waiting for Kozen P12...
adb wait-for-device
if errorlevel 1 (
    echo [ERROR] adb wait-for-device failed.
    pause
    exit /b 4
)

echo.
echo [ADB] Device:
adb shell getprop ro.product.manufacturer
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release

echo.
echo [ADB] SmartSkyPOS package/version:
adb shell dumpsys package com.skytech.smartskypos 2>nul | findstr /I "versionName versionCode"
echo.

echo [ADB] Installing i-Retail diagnostic build...
adb install -r "%APK%"
if errorlevel 1 (
    echo [ERROR] APK installation failed.
    pause
    exit /b 5
)

echo.
echo [SUCCESS] Build installed.
echo Next step: SMARTSKYPOS_02_SAFE_PROBE.bat
pause
exit /b 0
