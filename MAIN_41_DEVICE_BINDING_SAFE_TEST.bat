@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 goto FAILED
where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Windows PowerShell was not found.
  goto FAILED
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CD%\tools\Run-DeviceBindingSafeTest.ps1" -RepoRoot "%CD%"
set "RESULT=%ERRORLEVEL%"
echo.
echo [INFO] Exit code: %RESULT%
echo [INFO] No app data, payment markers or old logs were deleted.
pause
exit /b %RESULT%
:FAILED
echo [ERROR] Cannot start the binding test.
pause
exit /b 1
