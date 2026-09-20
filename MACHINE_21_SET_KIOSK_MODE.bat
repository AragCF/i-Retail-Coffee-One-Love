@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
if not defined JL22 set "JL22=192.168.1.192:5555"

echo ============================================================
echo i-Retail v0.5.21 - SET COFFEE KIOSK INTEGRATION MODE
echo ============================================================
echo JL22: %JL22%
echo.
echo Result:
echo   - i-Retail UI will NOT keep itself in foreground;
echo   - i-Retail UI will NOT auto-start after boot;
echo   - real POS inside i-Retail UI is disabled;
echo   - stock Jetinno app is brought to foreground and may show its screensaver.
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found in PATH.
  pause
  exit /b 2
)
adb -s "%JL22%" get-state >nul 2>nul
if errorlevel 1 (
  echo [ERROR] JL22 is not online: %JL22%
  pause
  exit /b 3
)

echo [1/4] Persisting kiosk mode without showing the i-Retail interface...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode kiosk --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true
if errorlevel 1 (
  echo [ERROR] Could not store kiosk mode. Is i-Retail v0.5.21 installed?
  pause
  exit /b 4
)
timeout /t 1 /nobreak >nul

echo [2/4] Stopping i-Retail UI and foreground keeper...
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul

echo [3/4] Bringing stock Jetinno application to foreground...
adb -s "%JL22%" shell monkey -p com.jinuo.mhwang.jetinnocoffe -c android.intent.category.LAUNCHER 1 >nul 2>nul
if errorlevel 1 echo [WARN] Stock app launcher was not found through monkey; it may already be active.
timeout /t 2 /nobreak >nul

echo [4/4] Current mode and foreground:
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_machine_mode_v1.xml 2>nul
adb -s "%JL22%" shell dumpsys activity activities ^| findstr /I "mResumedActivity mFocusedActivity"

echo.
echo ============================================================
echo KIOSK MODE IS PERSISTENT.
echo To return to standalone mode, run MACHINE_19_STANDALONE_MODE_SMOKE.bat

echo first, then MACHINE_20_ENABLE_STANDALONE_POS.bat when ready for real card payment.
echo ============================================================
pause
exit /b 0
