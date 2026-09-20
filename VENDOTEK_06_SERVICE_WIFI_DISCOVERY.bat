@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo i-Retail v0.5.26.1 - VENDOTEK SERVICE WI-FI DISCOVERY
echo ============================================================
echo This is a passive Windows Wi-Fi scan only.
echo It sends NO VTK message and NO financial command.
echo It does NOT connect to or change any Wi-Fi network.
echo ============================================================
echo.

where powershell >nul 2>nul
if errorlevel 1 (
  echo [ERROR] PowerShell was not found.
  pause
  exit /b 2
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\VendotekServiceWifiDiscovery.ps1"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo [OK] Vendotek service Wi-Fi discovery completed.
  echo Publish the result with:
  echo   call GIT_118_PUBLISH_VENDOTEK_WIFI_RESULT.bat
) else (
  echo [ERROR] Discovery finished with code %RC%.
  echo The evidence folder may still contain useful diagnostics.
)
echo.
pause
exit /b %RC%
