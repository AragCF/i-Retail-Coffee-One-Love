@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "JL22=%~1"
if not defined JL22 set "JL22=192.168.1.192:5555"
set "OUTCOME=STARTED"

echo ============================================================
echo i-Retail v0.5.21 - STANDALONE MACHINE MODE SAFE SMOKE
echo ============================================================
echo JL22: %JL22%
echo.
echo This test persists machine_mode=standalone but keeps real POS OFF.
echo It sends NO PAYMENT command.
echo It intentionally launches the stock Jetinno app once and verifies that
echo i-Retail returns to the foreground while Jetinno keeps running behind it.
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

set "SDK_PATH="
if defined ANDROID_HOME set "SDK_PATH=%ANDROID_HOME%"
if not defined SDK_PATH if defined ANDROID_SDK_ROOT set "SDK_PATH=%ANDROID_SDK_ROOT%"
if not defined SDK_PATH if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_PATH=%LOCALAPPDATA%\Android\Sdk"
if not defined SDK_PATH (
  echo [ERROR] Android SDK was not found.
  pause
  exit /b 4
)
set "SDK_PATH_GRADLE=%SDK_PATH:\=/%"
> local.properties echo sdk.dir=%SDK_PATH_GRADLE%

set "GRADLE_CMD="
if exist "gradlew.bat" set "GRADLE_CMD=%CD%\gradlew.bat"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD (
  echo [ERROR] Gradle was not found.
  pause
  exit /b 5
)

echo [1/7] Building i-Retail v0.5.21...
call "%GRADLE_CMD%" --no-daemon --stacktrace :app:assembleDebug
if errorlevel 1 (
  echo [ERROR] Build failed.
  pause
  exit /b 6
)

set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
echo [2/7] Installing main i-Retail UI...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 (
  echo [ERROR] i-Retail APK install failed.
  pause
  exit /b 7
)

echo [3/7] Clearing diagnostics and configuring STANDALONE + POS OFF...
adb -s "%JL22%" logcat -c
adb -s "%JL22%" shell am force-stop com.coffeeonelove.iretail >nul 2>nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false
if errorlevel 1 (
  echo [ERROR] Could not launch i-Retail in standalone mode.
  pause
  exit /b 8
)
timeout /t 3 /nobreak >nul

echo [4/7] Intentionally bringing the stock Jetinno application to foreground...
adb -s "%JL22%" shell monkey -p com.jinuo.mhwang.jetinnocoffe -c android.intent.category.LAUNCHER 1 >nul 2>nul
if errorlevel 1 (
  echo [WARN] Could not launch stock app through monkey. Continuing: it may already be running.
)
echo Waiting 6 seconds for the standalone foreground keeper...
timeout /t 6 /nobreak >nul

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "machine_mode_logs" mkdir "machine_mode_logs"
set "OUT=machine_mode_logs\STANDALONE_MODE_SMOKE_%TS%"
mkdir "%OUT%"

(
  echo jl22=%JL22%
  echo timestamp=%TS%
  echo requested_mode=standalone
  echo real_pos_enabled=false
  echo financial_commands=NONE
) > "%OUT%\00_info.txt"

echo [5/7] Collecting mode, lifecycle and foreground evidence...
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_machine_mode_v1.xml > "%OUT%\01_machine_mode_prefs.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime IretailMachineMode:I IretailForegroundKeeper:I ActivityManager:I AndroidRuntime:E *:S > "%OUT%\02_mode_logcat.txt" 2>&1
adb -s "%JL22%" shell dumpsys activity activities > "%OUT%\03_activity.txt" 2>&1
adb -s "%JL22%" shell dumpsys activity services com.coffeeonelove.iretail > "%OUT%\04_iretail_services.txt" 2>&1
adb -s "%JL22%" shell dumpsys package com.jinuo.mhwang.jetinnocoffe > "%OUT%\05_stock_package.txt" 2>&1
adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail > "%OUT%\06_iretail_package.txt" 2>&1

findstr /I /C:"mResumedActivity" /C:"mFocusedActivity" "%OUT%\03_activity.txt" > "%OUT%\07_foreground.txt" 2>&1
findstr /I "com.coffeeonelove.iretail" "%OUT%\07_foreground.txt" >nul 2>nul
if errorlevel 1 (
  set "OUTCOME=VISUAL_CHECK_REQUIRED"
) else (
  set "OUTCOME=STANDALONE_FOREGROUND_OK"
)

(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  echo ===== FOREGROUND =====
  type "%OUT%\07_foreground.txt"
  echo.
  echo ===== MACHINE MODE =====
  type "%OUT%\01_machine_mode_prefs.txt"
  echo.
  echo ===== FOREGROUND KEEPER =====
  findstr /I "IretailMachineMode IretailForegroundKeeper CONFIG_PERSISTED BRING_MAIN_UI_TO_FRONT SERVICE_CREATE" "%OUT%\02_mode_logcat.txt"
  echo.
  echo ===== SAFETY =====
  echo real_pos_enabled=false
  echo PAYMENT command is not sent by this smoke test.
) > "%OUT%\SUMMARY.txt" 2>&1

echo [6/7] Result: %OUTCOME%
echo.
echo Please look at JL22 now:
echo   - i-Retail UI should be on top;
echo   - stock Jetinno app should no longer cover it with its screensaver;
echo   - card payment remains disabled in this safe smoke.
echo.
echo Press any key after the visual check.
pause >nul

echo [7/7] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[SUCCESS] '+$z)"

echo.
echo ============================================================
echo STANDALONE MODE SAFE SMOKE COMPLETE. Outcome: %OUTCOME%
echo Publish with:
echo   call GIT_108_PUBLISH_MACHINE_MODE_RESULT.bat
echo ============================================================
pause
exit /b 0
