@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 exit /b 10

set "EXPECTED_BRANCH=v0.5.45-s2-tls-chain-capture-fix"
set "GIT_BRANCH="
set "GIT_SHA="

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git not found in PATH.
  pause
  exit /b 9
)

for /f "delims=" %%B in ('git branch --show-current') do if not defined GIT_BRANCH set "GIT_BRANCH=%%B"
if /I not "%GIT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo [ERROR] Wrong Git branch: %GIT_BRANCH%
  echo [ERROR] Expected: %EXPECTED_BRANCH%
  pause
  exit /b 13
)

git diff --quiet
if errorlevel 1 (
  echo [ERROR] Tracked working tree contains local changes.
  git status --short
  pause
  exit /b 14
)
git diff --cached --quiet
if errorlevel 1 (
  echo [ERROR] Git index contains staged local changes.
  git status --short
  pause
  exit /b 15
)
for /f "delims=" %%H in ('git rev-parse HEAD') do if not defined GIT_SHA set "GIT_SHA=%%H"

set "ADB_SERIAL="
set "DEVICE_PICK=%TEMP%\iretail_jl22_%RANDOM%_%RANDOM%.txt"
if exist "%DEVICE_PICK%" del /F /Q "%DEVICE_PICK%" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Select-JL22Device.ps1" -OutputFile "%DEVICE_PICK%" -PreferredSerial "%~1"
if errorlevel 1 (
  echo [ERROR] Android device selection failed.
  if exist "%DEVICE_PICK%" del /F /Q "%DEVICE_PICK%" >nul 2>nul
  pause
  exit /b 12
)
if not exist "%DEVICE_PICK%" (
  echo [ERROR] Device selector did not return a serial.
  pause
  exit /b 12
)
set /p ADB_SERIAL=<"%DEVICE_PICK%"
del /F /Q "%DEVICE_PICK%" >nul 2>nul
if not defined ADB_SERIAL (
  echo [ERROR] Empty ADB serial returned by device selector.
  pause
  exit /b 12
)
set "ADB_CMD=adb -s %ADB_SERIAL%"

for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%T"
set "OUT=test_reports\s2_tls_chain_capture\TLS_CHAIN_%STAMP%"
set "ZIP=%OUT%.zip"
if not exist "test_reports\s2_tls_chain_capture" mkdir "test_reports\s2_tls_chain_capture"
mkdir "%OUT%" >nul 2>nul

%ADB_CMD% shell dumpsys package com.coffeeonelove.iretail > "%OUT%\01_package_before.txt" 2>&1
findstr /C:"versionName=0.5.44-s2-tls-chain-probe" /C:"versionName=0.5.45-s2-tls-chain-capture-fix" "%OUT%\01_package_before.txt" >nul
if errorlevel 1 (
  echo [INFO] Probe-capable APK is not installed. Building/installing v0.5.45...
  call BUILD_WINDOWS_CLI.bat
  if errorlevel 1 (
    echo [ERROR] APK build failed.
    pause
    exit /b 20
  )
  set "APK=app\build\outputs\apk\debug\app-debug.apk"
  if not exist "%APK%" (
    echo [ERROR] APK not found: %APK%
    pause
    exit /b 21
  )
  %ADB_CMD% install -r "%APK%"
  if errorlevel 1 (
    echo [ERROR] APK install failed.
    pause
    exit /b 22
  )
  %ADB_CMD% shell dumpsys package com.coffeeonelove.iretail > "%OUT%\01_package_before.txt" 2>&1
) else (
  echo [OK] Existing APK already supports TLS chain probe. Rebuild skipped.
)

(
  echo Branch=%GIT_BRANCH%
  echo SHA=%GIT_SHA%
  echo Device=%ADB_SERIAL%
  echo.
  adb devices -l
) > "%OUT%\00_git_and_device.txt" 2>&1

%ADB_CMD% logcat -c
%ADB_CMD% shell am force-stop com.coffeeonelove.iretail
%ADB_CMD% shell am start -n com.coffeeonelove.iretail/.ui.MainActivity --ez real_pos_enabled false --ez tls_chain_probe true > "%OUT%\02_start.txt" 2>&1

echo [INFO] Waiting 12 seconds for TLS chain probe...
timeout /t 12 /nobreak >nul

%ADB_CMD% logcat -d -v threadtime IretailTls:V IretailCatalog:I AndroidRuntime:E *:S > "%OUT%\03_tls_logcat.txt" 2>&1
%ADB_CMD% shell date -u > "%OUT%\04_date_utc.txt" 2>&1
%ADB_CMD% shell getprop ro.build.version.release > "%OUT%\05_android_version.txt" 2>&1
%ADB_CMD% shell getprop ro.build.version.security_patch > "%OUT%\06_security_patch.txt" 2>&1

set "HAS_CHAIN=NO"
set "HAS_CERT=NO"
set "TRUST_RESULT=UNKNOWN"
findstr /C:"I IretailTls: CHAIN " "%OUT%\03_tls_logcat.txt" >nul
if not errorlevel 1 set "HAS_CHAIN=YES"
findstr /C:"I IretailTls: CERT " "%OUT%\03_tls_logcat.txt" >nul
if not errorlevel 1 set "HAS_CERT=YES"
findstr /C:"SYSTEM_TRUST=FAIL" "%OUT%\03_tls_logcat.txt" >nul
if not errorlevel 1 set "TRUST_RESULT=FAIL"
findstr /C:"SYSTEM_TRUST=OK" "%OUT%\03_tls_logcat.txt" >nul
if not errorlevel 1 set "TRUST_RESULT=OK"

(
  echo i-Retail v0.5.45 TLS chain capture
  echo Timestamp=%STAMP%
  echo GitBranch=%GIT_BRANCH%
  echo GitSHA=%GIT_SHA%
  echo Device=%ADB_SERIAL%
  echo HasChain=%HAS_CHAIN%
  echo HasCert=%HAS_CERT%
  echo SystemTrust=%TRUST_RESULT%
  echo.
  echo This probe does not disable certificate validation.
) > "%OUT%\SUMMARY.txt"

powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath '%ZIP%' -Force"
if errorlevel 1 (
  echo [ERROR] ZIP creation failed.
  pause
  exit /b 30
)

echo [INFO] TLS chain report:
echo %CD%\%ZIP%

call "%~dp0S2_05_PUBLISH_LATEST_TLS_CHAIN.bat"
if errorlevel 1 (
  echo [ERROR] Report was created but Git publication failed.
  pause
  exit /b 31
)

if /I not "%HAS_CHAIN%"=="YES" (
  echo [WARN] CHAIN line was not captured. Report was still published for analysis.
) else if /I not "%HAS_CERT%"=="YES" (
  echo [WARN] CERT line was not captured. Report was still published for analysis.
) else (
  echo [SUCCESS] TLS chain and certificate lines captured and published.
)

pause
exit /b 0
