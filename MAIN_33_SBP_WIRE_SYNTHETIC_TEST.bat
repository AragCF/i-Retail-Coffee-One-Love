@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "EXPECTED_VERSION="
for /f "tokens=2" %%V in ('findstr /C:"versionName " "app\build.gradle"') do if not defined EXPECTED_VERSION set "EXPECTED_VERSION=%%V"
set "EXPECTED_VERSION=%EXPECTED_VERSION:'=%"
if /I not "%EXPECTED_VERSION%"=="0.5.114-sbp-wire-sanitizer" (
  echo [ERROR] Wrong project version: %EXPECTED_VERSION%
  pause
  exit /b 11
)

echo ============================================================
echo i-Retail %EXPECTED_VERSION% - SBP SYNTHETIC AOA WIRE TEST
echo ============================================================
echo SAFETY:
echo   real POS remains FALSE
echo   SmartSkyPOS qrPayment is NOT called
echo   synthetic payload only
echo   raw payload must never appear in logs/reports
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
echo [JL22] %JL22%

set "KOZEN="
set "KOZEN_ADB_AVAILABLE=0"
if not "%~1"=="" call :TryKozen "%~1"
if "%KOZEN_ADB_AVAILABLE%"=="1" goto KOZEN_DISCOVERY_DONE

call :TryKozen "192.168.31.134:5555"
if "%KOZEN_ADB_AVAILABLE%"=="1" goto KOZEN_DISCOVERY_DONE

for /f "tokens=1,2,*" %%A in ('adb devices -l') do (
  if /I "%%B"=="device" if /I not "%%A"=="%JL22%" call :TryKozen "%%A"
)

:KOZEN_DISCOVERY_DONE
if "%KOZEN_ADB_AVAILABLE%"=="1" (
  echo [KOZEN ADB] %KOZEN%
) else (
  echo [KOZEN ADB] unavailable - safe fallback is allowed.
  echo [INFO] Installed bridge will be inspected over USB/AOA.
)

echo [1/9] Building i-Retail...
call "%~dp0BUILD_WINDOWS_CLI.bat"
if errorlevel 1 (
  echo [ERROR] Main APK build failed.
  pause
  exit /b 20
)

set "APP_APK=app\build\outputs\apk\debug\app-debug.apk"
set "KOZEN_APK=kozenBridge\build\outputs\apk\debug\kozenBridge-debug.apk"
if not exist "%APP_APK%" (
  echo [ERROR] Main APK not found.
  pause
  exit /b 21
)

set "GRADLE_CMD="
if exist "gradlew.bat" set "GRADLE_CMD=%CD%\gradlew.bat"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle.bat 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD for /f "delims=" %%G in ('where gradle 2^>nul') do if not defined GRADLE_CMD set "GRADLE_CMD=%%G"
if not defined GRADLE_CMD (
  echo [ERROR] Gradle was not found.
  pause
  exit /b 22
)

echo [2/9] Preparing Kozen bridge 0.5.5 when ADB is available...
if "%KOZEN_ADB_AVAILABLE%"=="1" call :BuildInstallKozen
if errorlevel 1 (
  pause
  exit /b 23
)
if "%KOZEN_ADB_AVAILABLE%"=="0" echo [INFO] Kozen bridge upgrade skipped; old bridge may report BRIDGE_UPGRADE_REQUIRED.

echo [3/9] Installing i-Retail on JL22...
adb -s "%JL22%" install -r "%APP_APK%"
if errorlevel 1 (
  echo [ERROR] i-Retail install failed.
  pause
  exit /b 24
)

echo [4/9] Persisting safe Standalone baseline...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
if errorlevel 1 exit /b 25
timeout /t 1 /nobreak >nul

if "%KOZEN_ADB_AVAILABLE%"=="1" call :StartKozenBridge
adb -s "%JL22%" logcat -c

echo [5/9] Clearing ONLY previous synthetic SBP session state...
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail rm -f shared_prefs/iretail_sbp_session_v1.xml >nul 2>nul

echo [6/9] Starting synthetic SBP payload round-trip...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false --ez sbp_wire_synthetic_test true >nul
if errorlevel 1 exit /b 26

set "WAIT_LOG=%TEMP%\iretail_sbp_wire_wait.log"
set "OUTCOME=WIRE_TIMEOUT"

for /l %%S in (1,1,150) do (
  if "%KOZEN_ADB_AVAILABLE%"=="1" (
    if "%%S"=="1" call :StartKozenBridge
    if "%%S"=="3" call :StartKozenBridge
    if "%%S"=="5" call :StartKozenBridge
  )

  adb -s "%JL22%" logcat -d -v brief SbpWireTest:V IretailKozenClient:V IretailMachineMode:I *:S > "%WAIT_LOG%" 2>&1

  findstr /C:"WIRE_RESULT ok=true" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=WIRE_OK"
    goto WIRE_DONE
  )

  findstr /C:"code=BRIDGE_UPGRADE_REQUIRED" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=BRIDGE_UPGRADE_REQUIRED"
    goto WIRE_DONE
  )

  findstr /C:"WIRE_RESULT ok=false" "%WAIT_LOG%" >nul 2>nul
  if not errorlevel 1 (
    set "OUTCOME=WIRE_FAILED"
    goto WIRE_DONE
  )

  timeout /t 1 /nobreak >nul
)

:WIRE_DONE
echo [7/9] Restoring ordinary safe i-Retail foreground...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false >nul 2>nul
timeout /t 1 /nobreak >nul

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"
if not exist "sbp_wire_logs" mkdir "sbp_wire_logs"
set "OUT=sbp_wire_logs\SBP_WIRE_TEST_%TS%"
mkdir "%OUT%"

echo [8/9] Collecting private state, reducing it to hashes, then sanitizing logs...
(
  echo version=%EXPECTED_VERSION%
  echo outcome=%OUTCOME%
  echo safety=SYNTHETIC_NO_FINANCIAL_COMMANDS
  echo real_pos=false
  echo kozen_adb_available=%KOZEN_ADB_AVAILABLE%
  echo wire_contract=BASE64URL_REDACTED_V1
  echo expected_bridge=0.5.5
  echo live_qr_payment_enabled=false
) > "%OUT%\01_environment.txt"

adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail 2>nul | findstr /I "versionName= versionCode=" > "%OUT%\02_package.txt"
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_machine_mode_v1.xml > "%OUT%\03_machine_mode.txt" 2>&1
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_sbp_session_v1.xml > "%OUT%\04_sbp_session_raw.txt" 2>nul

powershell -NoProfile -Command "$p='%CD%\%OUT%\04_sbp_session_raw.txt'; $o='%CD%\%OUT%\04_sbp_session_safe.txt'; if(Test-Path -LiteralPath $p){ $x=Get-Content -Raw -LiteralPath $p; $payload=''; if($x -match '<string name=\"qr_payload\">([^<]*)</string>'){ $payload=$matches[1] }; $hash='-'; if($payload){ $sha=[Security.Cryptography.SHA256]::Create(); $b=[Text.Encoding]::UTF8.GetBytes($payload); $h=$sha.ComputeHash($b); $hash=(-join ($h[0..7] | ForEach-Object { $_.ToString('x2') })) }; $lines=@('privateSessionPresent=true',('payloadHash='+$hash),('payloadLength='+$payload.Length),'rawPayloadPublished=false'); Set-Content -Encoding UTF8 -LiteralPath $o -Value $lines; Remove-Item -Force -LiteralPath $p } else { Set-Content -Encoding UTF8 -LiteralPath $o -Value @('privateSessionPresent=false','payloadHash=-','payloadLength=0','rawPayloadPublished=false') }"
if errorlevel 1 exit /b 31

adb -s "%JL22%" logcat -d -v threadtime SbpWireTest:V IretailKozenClient:V IretailMachineMode:I AndroidRuntime:E *:S > "%OUT%\RAW_jl22_logcat.txt" 2>&1

if "%KOZEN_ADB_AVAILABLE%"=="1" (
  adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:V AndroidRuntime:E *:S > "%OUT%\RAW_kozen_logcat.txt" 2>&1
) else (
  > "%OUT%\RAW_kozen_logcat.txt" echo KOZEN_ADB_NOT_AVAILABLE
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Sanitize-SbpWireReport.ps1" -RawJl22 "%CD%\%OUT%\RAW_jl22_logcat.txt" -RawKozen "%CD%\%OUT%\RAW_kozen_logcat.txt" -ReportDir "%CD%\%OUT%"
if errorlevel 1 (
  echo [ERROR] SBP wire safety scan failed. Report will not be published.
  pause
  exit /b 32
)

(
  echo ===== OUTCOME =====
  echo %OUTCOME%
  echo.
  findstr /I "WIRE_RESULT SBP_WIRE_OK SBP_WIRE_PENDING SBP_WIRE_FAILED" "%OUT%\05_jl22_logcat.txt"
) > "%OUT%\07_summary.txt" 2>&1

powershell -NoProfile -Command "$all=(Get-ChildItem -LiteralPath '%CD%\%OUT%' -File | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue }) -join [Environment]::NewLine; if($all -match 'SBP-SYNTHETIC-WIRE\|'){ Write-Host '[ERROR] Raw synthetic payload leaked into report'; exit 1 }"
if errorlevel 1 (
  pause
  exit /b 33
)

echo [9/9] Creating archive and publishing evidence...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Set-Content -Encoding ASCII -LiteralPath ($z+'.safe.txt') -Value 'SAFETY_SCAN_OK'; Write-Host ('[REPORT] '+$z)"
if errorlevel 1 exit /b 34

call "%~dp0GIT_131_PUBLISH_SBP_WIRE_TEST.bat"
if errorlevel 1 echo [WARN] Publication failed; local ZIP preserved.

echo.
echo ============================================================
echo SBP SYNTHETIC AOA WIRE TEST COMPLETE
echo Outcome: %OUTCOME%
echo No financial command was sent.
echo ============================================================
pause

if /I "%OUTCOME%"=="WIRE_OK" exit /b 0
if /I "%OUTCOME%"=="BRIDGE_UPGRADE_REQUIRED" exit /b 0
exit /b 3

:TryKozen
if "%KOZEN_ADB_AVAILABLE%"=="1" exit /b 0
set "CANDIDATE=%~1"
adb -s "%CANDIDATE%" get-state >nul 2>nul
if errorlevel 1 exit /b 0
adb -s "%CANDIDATE%" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
if errorlevel 1 exit /b 0
set "KOZEN=%CANDIDATE%"
set "KOZEN_ADB_AVAILABLE=1"
exit /b 0

:BuildInstallKozen
set "KOZEN_CACHE_ARG="
set "FREE_MB="
for /f "delims=" %%F in ('powershell -NoProfile -Command "$r=[System.IO.Path]::GetPathRoot((Get-Location).Path); $d=Get-PSDrive -Name $r.Substring(0,1); [math]::Floor($d.Free/1MB)" 2^>nul') do if not defined FREE_MB set "FREE_MB=%%F"
if not defined FREE_MB set "FREE_MB=0"
if %FREE_MB% LSS 2048 set "KOZEN_CACHE_ARG=--no-build-cache"
call "%GRADLE_CMD%" --no-daemon %KOZEN_CACHE_ARG% --stacktrace :kozenBridge:assembleDebug
if errorlevel 1 exit /b 1
if not exist "%KOZEN_APK%" exit /b 1
adb -s "%KOZEN%" install -r "%KOZEN_APK%"
if errorlevel 1 exit /b 1
exit /b 0

:StartKozenBridge
adb -s "%KOZEN%" shell am start -W -n com.coffeeonelove.iretail.kozenbridge/.BridgeActivity >nul 2>nul
exit /b 0
