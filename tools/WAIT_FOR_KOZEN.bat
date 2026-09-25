@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Wait until the real Kozen P12 with SmartSkyPOS becomes available through ADB.
rem Usage:
rem   call "%~dp0WAIT_FOR_KOZEN.bat" KOZEN
rem Ctrl+C remains the manual abort path.

set "OUTVAR=%~1"
if not defined OUTVAR set "OUTVAR=KOZEN"

:WAIT_LOOP
adb connect 192.168.31.134:5555 >nul 2>nul
call :SCAN
if defined FOUND goto FOUND_OK

echo.
echo ============================================================
echo KOZEN P12 IS NOT AVAILABLE THROUGH ADB
echo ============================================================
echo Restore the Kozen ADB connection now.
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
for /f "tokens=1,2,*" %%A in ('adb devices -l') do (
    if /I "%%B"=="device" call :PROBE "%%A"
)
exit /b 0

:PROBE
if defined FOUND exit /b 0
adb -s "%~1" shell pm path com.skytech.smartskypos > "%TEMP%\iretail_probe_smartskypos_wait.txt" 2>nul
findstr /B /C:"package:" "%TEMP%\iretail_probe_smartskypos_wait.txt" >nul 2>nul
if not errorlevel 1 set "FOUND=%~1"
exit /b 0

:FOUND_OK
echo [KOZEN] !FOUND!
for %%V in (!FOUND!) do (
    endlocal
    set "%OUTVAR%=%%V"
)
exit /b 0
