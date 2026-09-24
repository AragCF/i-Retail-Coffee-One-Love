@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Wait until the real Jetinno JL22 becomes available through ADB.
rem Usage:
rem   call "%~dp0tools\WAIT_FOR_JL22.bat" JL22
rem The selected serial is returned in the caller variable passed as %1.
rem Ctrl+C remains the standard manual abort path.

set "OUTVAR=%~1"
if not defined OUTVAR set "OUTVAR=JL22"

:WAIT_LOOP
call :SCAN

if defined FOUND goto FOUND_OK

if defined OFFLINE (
    echo.
    echo [JL22] Found but offline: !OFFLINE!
    echo [JL22] Trying to restore network ADB once...
    echo !OFFLINE! | findstr /C:":" >nul 2>nul
    if not errorlevel 1 (
        adb connect "!OFFLINE!" >nul 2>nul
        timeout /t 1 /nobreak >nul
        call :SCAN
        if defined FOUND goto FOUND_OK
    )
)

echo.
echo ============================================================
echo JL22 IS NOT AVAILABLE THROUGH ADB
echo ============================================================
echo Restore the JL22 connection now.
echo.
adb devices -l
echo.
echo Press ANY key to try again.
echo Press Ctrl+C to stop the batch file.
echo ============================================================
pause >nul
goto WAIT_LOOP

:SCAN
set "FOUND="
set "OFFLINE="
for /f "tokens=1,2,*" %%A in ('adb devices -l ^| findstr /I /C:"product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno"') do (
    if /I "%%B"=="device" if not defined FOUND set "FOUND=%%A"
    if /I "%%B"=="offline" if not defined OFFLINE set "OFFLINE=%%A"
)
exit /b 0

:FOUND_OK
echo [JL22] !FOUND!
for %%V in (!FOUND!) do (
    endlocal
    set "%OUTVAR%=%%V"
)
exit /b 0
