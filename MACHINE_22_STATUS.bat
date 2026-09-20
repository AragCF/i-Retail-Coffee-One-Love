@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
if not defined JL22 set "JL22=192.168.1.192:5555"

echo ============================================================
echo i-Retail MACHINE MODE STATUS
echo ============================================================
echo JL22: %JL22%
echo.

adb -s "%JL22%" get-state
if errorlevel 1 (
  echo [ERROR] JL22 is not online.
  pause
  exit /b 2
)

echo.
echo [Persistent mode]
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_machine_mode_v1.xml 2>nul

echo.
echo [Foreground activity]
adb -s "%JL22%" shell dumpsys activity activities ^| findstr /I "mResumedActivity mFocusedActivity"

echo.
echo [i-Retail keeper service]
adb -s "%JL22%" shell dumpsys activity services com.coffeeonelove.iretail ^| findstr /I "ForegroundKeeperService ServiceRecord"

echo.
echo [Recent machine-mode log]
adb -s "%JL22%" logcat -d -v brief IretailMachineMode:I IretailForegroundKeeper:I *:S

echo.
pause
exit /b 0
