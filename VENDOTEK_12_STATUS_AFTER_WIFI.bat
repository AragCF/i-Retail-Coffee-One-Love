@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
where powershell >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Windows PowerShell is required.
  pause
  exit /b 2
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\VendotekNetworkAccessAudit.ps1" -Mode Status
set "RC=%ERRORLEVEL%"
echo.
echo Publish report: call GIT_123_PUBLISH_VENDOTEK_NETWORK_RESULT.bat
pause
exit /b %RC%
