@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo i-Retail v0.5.31 - VENDOTEK DIRECT WINDOWS COM24 PROBE
echo ============================================================
echo Verified Vendotek FTDI VCP: COM24
echo USB VID:PID: 0403:6001
echo SAFETY:
echo   - IDL and STATUS only.
echo   - NO payment, VRP, FIN, ABR or DIS.
echo ============================================================
echo.

call VENDOTEK_08_WINDOWS_COM_PROBE.bat COM24
exit /b %ERRORLEVEL%
