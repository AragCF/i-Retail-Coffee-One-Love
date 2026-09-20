@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo i-Retail v0.5.28 - VENDOTEK DIRECT WINDOWS COM PROBE
echo ============================================================
echo SAFETY:
echo   - IDL and STATUS only.
echo   - NO payment, VRP, FIN, ABR or DIS.
echo   - Vendotek must be connected directly to this Windows PC.
echo   - FTDI VCP driver should expose VID_0403 PID_6001 as COMx.
echo ============================================================
echo.

where powershell >nul 2>nul
if errorlevel 1 (
  echo [ERROR] PowerShell was not found.
  pause
  exit /b 2
)

set "PORT=%~1"
if defined PORT (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\VendotekWindowsComProbe.ps1" -PortName "%PORT%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\VendotekWindowsComProbe.ps1"
)
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo [OK] Direct Windows COM VTK probe completed.
  echo Publish with:
  echo   call GIT_120_PUBLISH_VENDOTEK_COM_RESULT.bat
) else (
  echo [ERROR] COM probe finished with code %RC%.
  echo A ZIP should still be available in vendotek_com_logs when the script started successfully.
)
echo.
pause
exit /b %RC%
