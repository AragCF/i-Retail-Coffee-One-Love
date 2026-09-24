@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_VERSION="
for /f "tokens=2" %%V in ('findstr /C:"versionName " "app\build.gradle"') do if not defined EXPECTED_VERSION set "EXPECTED_VERSION=%%V"
set "EXPECTED_VERSION=%EXPECTED_VERSION:'=%"
if /I not "%EXPECTED_VERSION%"=="0.5.111-sbp-route-readonly-contract" (
  echo [ERROR] Wrong project version: %EXPECTED_VERSION%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - SBP ROUTE READ-ONLY AUDIT
echo ============================================================
echo SAFETY:
echo   real POS remains FALSE
echo   no qrPayment / PAYMENT / REFUND / CANCEL is sent
echo   only PING, INFO, GET_STATE and GET_TERMINAL_DATA are read
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found in PATH.
  pause
  exit /b 12
)

set "JL22="
for /f "tokens=1,2,*" %%A in ('adb devices -l ^| findstr /I /C:"product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno"') do (
  if /I "%%B"=="device" if not defined JL22 set "JL22=%%A"
)
if not defined JL22 (
  echo [ERROR] Live JL22 not found.
  adb devices -l
  pause
  exit /b 13
)

set "KOZEN="
set "KOZEN_ADB_AVAILABLE=0"
adb connect 192.168.31.134:5555 >nul 2>nul
adb -s "192.168.31.134:5555" get-state >nul 2>nul
if not errorlevel 1 (
  adb -s "192.168.31.134:5555" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
  if not errorlevel 1 (
    set "KOZEN=192.168.31.134:5555"
    set "KOZEN_ADB_AVAILABLE=1"
  )
)
if "%KOZEN_ADB_AVAILABLE%"=="0" (
  for /f "tokens=1,2,*" %%A in ('adb devices -l') do (
    if /I "%%B"=="device" if /I not "%%A"=="%JL22%" if "%KOZEN_ADB_AVAILABLE%"=="0" (
      adb -s "%%A" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
      if not errorlevel 1 (
        set "KOZEN=%%A"
        set "KOZEN_ADB_AVAILABLE=1"
      )
    )
  )
)

echo [JL22] %JL22%
if "%KOZEN_ADB_AVAILABLE%"=="1" (
  echo [KOZEN ADB] %KOZEN%
) else (
  echo [KOZEN ADB] unavailable - safe. Existing bridge will be audited without modification.
)

echo [1/6] Building i-Retail...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 exit /b 20
set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APP_APK%" exit /b 21

if "%KOZEN_ADB_AVAILABLE%"=="1" (
  echo [2/6] Building and installing Kozen bridge 0.5.3...
  set "GRADLE_EXE="
  for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_EXE set "GRADLE_EXE=%%G"
  if not defined GRADLE_EXE if defined ANDROID_HOME if exist "%ANDROID_HOME%\gradle\bin\gradle.bat" set "GRADLE_EXE=%ANDROID_HOME%\gradle\bin\gradle.bat"
  if not defined GRADLE_EXE if exist "C:\54\Dist\Progr\Android_Tools\gradle\bin\gradle.bat" set "GRADLE_EXE=C:\54\Dist\Progr\Android_Tools\gradle\bin\gradle.bat"
  if not defined GRADLE_EXE (
    echo [ERROR] Gradle not found for Kozen bridge build.
    pause
    exit /b 22
  )
  call "%GRADLE_EXE%" --no-daemon :kozenBridge:assembleDebug
  if errorlevel 1 exit /b 23
  set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
  if not exist "%KOZEN_APK%" exit /b 24
  adb -s "%KOZEN%" install -r "%KOZEN_APK%"
  if errorlevel 1 exit /b 25
) else (
  echo [2/6] Kozen bridge update skipped: Windows ADB unavailable.
)

echo [3/6] Installing i-Retail on JL22...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 26

echo [4/6] Persisting safe STANDALONE + real POS FALSE...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
timeout /t 1 /nobreak >nul
adb -s "%JL22%" logcat -c

if "%KOZEN_ADB_AVAILABLE%"=="1" (
  adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
  adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
)

echo [5/6] Reading exact SBP route...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_route_readonly_snapshot true >nul
if errorlevel 1 exit /b 27

set "WAIT_LOG=%TEMP%\iretail_sbp_route_wait.log"
set "OUTCOME=ROUTE_TIMEOUT"
for /l %%S in (1,1,150) do (
  if "%KOZEN_ADB_AVAILABLE%"=="1" (
    if "%%S"=="1" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
    if "%%S"=="3" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
    if "%%S"=="5" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
  )
  adb -s "%JL22%" logcat -d -v brief SbpRouteAudit:V IretailKozenClient:V *:S > "%WAIT_LOG%" 2>&1
  findstr /C:"ROUTE_RESULT ok=true" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    findstr /C:"exactRoute=true" "%WAIT_LOG%" >nul 2>nul
    if not errorlevel 1 (
      set "OUTCOME=ROUTE_CONFIRMED"
      goto ROUTE_DONE
    )
    findstr /C:"bridgeReportsSbpRoute=false" "%WAIT_LOG%" >nul 2>nul
    if not errorlevel 1 (
      set "OUTCOME=LEGACY_BRIDGE"
      goto ROUTE_DONE
    )
    set "OUTCOME=ROUTE_NOT_ADVERTISED"
    goto ROUTE_DONE
  )
  findstr /C:"ROUTE_RESULT ok=false" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=ROUTE_FAILED"
    goto ROUTE_DONE
  )
  timeout /t 1 /nobreak >nul
)

:ROUTE_DONE
echo [6/6] Restoring ordinary Standalone and printing result...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false >nul 2>nul
adb -s "%JL22%" logcat -d -v threadtime SbpRouteAudit:V IretailKozenClient:I AndroidRuntime:E *:S

echo.
echo ============================================================
echo SBP ROUTE READ-ONLY AUDIT COMPLETE
echo Outcome: %OUTCOME%
echo Kozen ADB available: %KOZEN_ADB_AVAILABLE%
echo No financial command was sent.
echo ============================================================
pause
if /I "%OUTCOME%"=="ROUTE_CONFIRMED" exit /b 0
if /I "%OUTCOME%"=="LEGACY_BRIDGE" exit /b 3
exit /b 2
