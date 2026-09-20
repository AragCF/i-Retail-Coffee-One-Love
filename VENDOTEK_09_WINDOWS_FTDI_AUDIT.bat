@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo i-Retail v0.5.30 - VENDOTEK WINDOWS FTDI READ-ONLY AUDIT
echo ============================================================
echo This test writes NO bytes to Vendotek.
echo It sends NO VTK command and NO financial command.
echo It only inspects the Windows FTDI VCP driver, COM port and signals.
echo ============================================================
echo.

set "PORT=%~1"
if defined PORT (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\VendotekWindowsFtdiAudit.ps1" -PortName "%PORT%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\VendotekWindowsFtdiAudit.ps1"
)
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo [OK] Passive FTDI audit completed.
  echo Publish with:
  echo   call GIT_121_PUBLISH_VENDOTEK_FTDI_AUDIT.bat
) else (
  echo [ERROR] Passive FTDI audit finished with code %RC%.
  echo Publish the archive anyway; it may contain the exact driver problem.
  echo   call GIT_121_PUBLISH_VENDOTEK_FTDI_AUDIT.bat
)
echo.
pause
exit /b %RC%
