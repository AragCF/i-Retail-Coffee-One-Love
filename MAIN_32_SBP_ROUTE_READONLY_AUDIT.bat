@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_VERSION="
for /f "tokens=2" %%V in ('findstr /C:"versionName " "app\build.gradle"') do if not defined EXPECTED_VERSION set "EXPECTED_VERSION=%%V"
set "EXPECTED_VERSION=%EXPECTED_VERSION:'=%"
if /I not "%EXPECTED_VERSION%"=="0.5.112-sbp-route-audit" (
  echo [ERROR] Wrong project version: %EXPECTED_VERSION%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - SBP ROUTE READ-ONLY AUDIT
echo ============================================================
echo SAFETY:
echo   real POS remains FALSE
echo   no QR_PAYMENT is sent
echo   bridge 0.5.3 exposes GET_SBP_ROUTE only
echo   live qrPayment Binder slot 19 remains hard-disabled
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

if not "%~1"=="" (
  set "KOZEN=%~1"
  adb -s "%~1" get-state >nul 2>nul
  if not errorlevel 1 (
    adb -s "%~1" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
    if not errorlevel 1 set "KOZEN_ADB_AVAILABLE=1"
  )
)

if "%KOZEN_ADB_AVAILABLE%"=="0" (
  adb connect 192.168.31.134:5555 >nul 2>nul
  adb -s "192.168.31.134:5555" get-state >nul 2>nul
  if not errorlevel 1 (
    adb -s "192.168.31.134:5555" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
    if not errorlevel 1 (
      set "KOZEN=192.168.31.134:5555"
      set "KOZEN_ADB_AVAILABLE=1"
    )
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
  echo [KOZEN ADB] unavailable - allowed.
  echo [INFO] Installed bridge will be inspected over USB/AOA.
)

echo [1/8] Building i-Retail...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 (
  echo [ERROR] Main APK build failed.
  pause
  exit /b 20
)

set "GRADLE_CMD="
if exist "gradlew.bat" set "GRADLE_CMD=%CD%\gradlew.bat"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD (
  echo [ERROR] Gradle was not found.
  pause
  exit /b 21
)

set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
if not exist "%APP_APK%" exit /b 22

echo [2/8] Preparing Kozen bridge 0.5.3 if ADB is available...
if "%KOZEN_ADB_AVAILABLE%"=="1" (
  set "KOZEN_CACHE_ARG="
  set "FREE_MB="
  for /f "delims=" %%F in ('powershell -NoProfile -Command "$r=[System.IO.Path]::GetPathRoot((Get-Location).Path); $d=Get-PSDrive -Name $r.Substring(0,1); [math]::Floor($d.Free/1MB)" 2^>nul') do if not defined FREE_MB set "FREE_MB=%%F"
  if not defined FREE_MB set "FREE_MB=0"
  if %FREE_MB% LSS 2048 set "KOZEN_CACHE_ARG=--no-build-cache"

  call "%GRADLE_CMD%" --no-daemon %KOZEN_CACHE_ARG% --stacktrace :kozenBridge:assembleDebug
  if errorlevel 1 (
    echo [ERROR] Kozen bridge build failed.
    pause
    exit /b 23
  )
  if not exist "%KOZEN_APK%" exit /b 24
) else (
  echo [INFO] Bridge build/install skipped because Kozen ADB is unavailable.
)

echo [3/8] Installing i-Retail on JL22...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 exit /b 25

if "%KOZEN_ADB_AVAILABLE%"=="1" (
  echo [INFO] Installing read-only-capable bridge 0.5.3 on Kozen...
  adb -s "%KOZEN%" install -r "%KOZEN_APK%"
  if errorlevel 1 exit /b 26
)

echo [4/8] Persisting safe Standalone baseline...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
if errorlevel 1 exit /b 27
timeout /t 1 /nobreak >nul

if "%KOZEN_ADB_AVAILABLE%"=="1" (
  adb -s "%KOZEN%" shell am force-stop com.coffeeonelove.iretail.kozenbridge >nul 2>nul
  adb -s "%KOZEN%" logcat -c
  adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
)
adb -s "%JL22%" logcat -c

echo [5/8] Starting read-only SBP route audit...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_route_readonly_audit true >nul
if errorlevel 1 exit /b 28

set "WAIT_LOG=%TEMP%\iretail_sbp_route_wait.log"
set "OUTCOME=ROUTE_TIMEOUT"
for /l %%S in (1,1,150) do (
  if "%KOZEN_ADB_AVAILABLE%"=="1" (
    if "%%S"=="1" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
    if "%%S"=="3" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
    if "%%S"=="5" adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
  )
  adb -s "%JL22%" logcat -d -v brief SbpRouteAudit:V IretailKozenClient:V IretailMachineMode:I *:S > "%WAIT_LOG%" 2>&1

  findstr /C:"ROUTE_RESULT ok=true" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    findstr /C:"available=true" "%WAIT_LOG%" >nul 2>nul
    if not errorlevel 1 (
      set "OUTCOME=ROUTE_OK"
    ) else (
      set "OUTCOME=ROUTE_NOT_AVAILABLE"
    )
    goto ROUTE_DONE
  )

  findstr /C:"code=BRIDGE_UPGRADE_REQUIRED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=BRIDGE_UPGRADE_REQUIRED"
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
echo [6/8] Restoring ordinary safe i-Retail foreground...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false >nul 2>nul
timeout /t 1 /nobreak >nul

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "sbp_route_logs" mkdir "sbp_route_logs"
set "OUT=sbp_route_logs\SBP_ROUTE_AUDIT_%TS%"
mkdir "%OUT%"

echo [7/8] Collecting and sanitizing evidence...
(
  echo version=%EXPECTED_VERSION%
  echo outcome=%OUTCOME%
  echo safety=READ_ONLY_NO_FINANCIAL_COMMANDS
  echo real_pos=false
  echo kozen_adb_available=%KOZEN_ADB_AVAILABLE%
  echo expected_operation_type=42
  echo expected_transaction_type=qrPayment
  echo expected_currency=643
  echo live_qr_payment_enabled=false
) > "%OUT%\01_environment.txt"

adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail 2>nul | findstr /I "versionName= versionCode=" > "%OUT%\02_package.txt"
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_machine_mode_v1.xml > "%OUT%\03_machine_mode.txt" 2>&1
adb -s "%JL22%" logcat -d -v threadtime SbpRouteAudit:V IretailKozenClient:V IretailMachineMode:I AndroidRuntime:E *:S > "%OUT%\RAW_jl22_logcat.txt" 2>&1
if "%KOZEN_ADB_AVAILABLE%"=="1" (
  adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:V AndroidRuntime:E *:S > "%OUT%\RAW_kozen_logcat.txt" 2>&1
) else (
  > "%OUT%\RAW_kozen_logcat.txt" echo KOZEN_ADB_NOT_AVAILABLE
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Sanitize-FiscalPositivePaymentReport.ps1" -RawJl22 "%CD%\%OUT%\RAW_jl22_logcat.txt" -RawKozen "%CD%\%OUT%\RAW_kozen_logcat.txt" -ReportDir "%CD%\%OUT%"
if errorlevel 1 (
  echo [ERROR] Safety scan failed.
  pause
  exit /b 30
)

(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  findstr /I "ROUTE_RESULT SBP_ROUTE_OK SBP_ROUTE_PENDING SBP_ROUTE_FAILED" "%OUT%\05_jl22_logcat.txt"
) > "%OUT%\07_summary.txt" 2>&1

echo [8/8] Creating archive and publishing evidence...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Set-Content -Encoding ASCII -LiteralPath ($z+'.safe.txt') -Value 'SAFETY_SCAN_OK'; Write-Host ('[REPORT] '+$z)"
if errorlevel 1 exit /b 31

call "%~dp0GIT_130_PUBLISH_SBP_ROUTE_AUDIT.bat"
if errorlevel 1 echo [WARN] Publication failed; local ZIP preserved.

echo.
echo ============================================================
echo SBP ROUTE READ-ONLY AUDIT COMPLETE
echo Outcome: %OUTCOME%
echo No financial command was sent.
echo ============================================================
pause

if /I "%OUTCOME%"=="ROUTE_OK" exit /b 0
if /I "%OUTCOME%"=="BRIDGE_UPGRADE_REQUIRED" exit /b 0
if /I "%OUTCOME%"=="ROUTE_NOT_AVAILABLE" exit /b 2
exit /b 3
