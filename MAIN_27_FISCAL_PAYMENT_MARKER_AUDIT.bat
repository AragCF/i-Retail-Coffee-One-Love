@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo i-Retail S3 PAYMENT MARKER AUDIT - READ ONLY
echo ============================================================
echo This audit sends NO PAYMENT, deletes NO marker and clears NO payment state.
echo It also restores i-Retail to STANDALONE with real POS disabled.
echo ============================================================
echo.

where adb >nul 2>nul
if errorlevel 1 (
  echo [ERROR] adb was not found in PATH.
  pause
  exit /b 2
)

set "JL22="
for /f "tokens=1,2,*" %%A in ('adb devices -l ^| findstr /I /C:"product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno"') do (
  if /I "%%B"=="device" if not defined JL22 set "JL22=%%A"
)
if not defined JL22 (
  echo [ERROR] Live JL22 not found.
  adb devices -l
  pause
  exit /b 3
)

set "KOZEN="
adb connect 192.168.31.134:5555 >nul 2>nul
adb -s "192.168.31.134:5555" get-state >nul 2>nul
if not errorlevel 1 (
  adb -s "192.168.31.134:5555" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
  if not errorlevel 1 set "KOZEN=192.168.31.134:5555"
)
if not defined KOZEN (
  for /f "tokens=1,2,*" %%A in ('adb devices -l') do (
    if /I "%%B"=="device" if /I not "%%A"=="%JL22%" if not defined KOZEN (
      adb -s "%%A" shell pm path com.skytech.smartskypos 2>nul | findstr /C:"package:" >nul
      if not errorlevel 1 set "KOZEN=%%A"
    )
  )
)

echo [JL22] %JL22%
if defined KOZEN (
  echo [KOZEN] %KOZEN%
) else (
  echo [KOZEN] Windows ADB unavailable. JL22 evidence will still be collected.
)

echo.
echo [1/5] Restoring i-Retail in safe standalone mode...
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez persist_machine_mode true --ez real_pos_enabled false --ez configure_only true >nul 2>nul
timeout /t 1 /nobreak >nul
adb -s "%JL22%" shell am start -W -n com.coffeeonelove.iretail/.ui.MainActivity --es machine_mode standalone --ez real_pos_enabled false >nul 2>nul
if errorlevel 1 (
  echo [WARN] Could not bring i-Retail UI to foreground, but audit will continue.
) else (
  echo [OK] i-Retail safe UI launch requested.
)

set "TS="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do if not defined TS set "TS=%%T"
if not defined TS set "TS=manual"

if not exist "payment_marker_audit_logs" mkdir "payment_marker_audit_logs"
set "OUT=payment_marker_audit_logs\PAYMENT_MARKER_AUDIT_%TS%"
mkdir "%OUT%"

echo [2/5] Reading JL22 state...
adb -s "%JL22%" shell dumpsys package com.coffeeonelove.iretail 2>nul | findstr /I "versionName= versionCode=" > "%OUT%\01_jl22_package.txt"
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_machine_mode_v1.xml > "%OUT%\02_machine_mode.txt" 2>&1
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat files/fiscal_positive_payment_test_v1_0_1.attempt > "%OUT%\03_marker_raw.txt" 2>nul
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail ls -l files/fiscal_positive_payment_test_v1_0_1.attempt > "%OUT%\04_marker_file_info.txt" 2>&1
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat shared_prefs/iretail_jl22_kozen_payment_v1.xml > "%OUT%\05_jl22_payment_prefs_raw.txt" 2>nul
adb -s "%JL22%" logcat -d -v threadtime FiscalPositivePaymentTest:V IretailKozenClient:V FiscalGateway:V IretailMachineMode:V AndroidRuntime:E *:S > "%OUT%\06_jl22_logcat_raw.txt" 2>&1
adb -s "%JL22%" shell run-as com.coffeeonelove.iretail cat files/fiscalization_dry_run.json > "%OUT%\07_fiscalization_dry_run.txt" 2>nul

echo [3/5] Reading Kozen bridge state...
if defined KOZEN (
  adb -s "%KOZEN%" shell run-as com.coffeeonelove.iretail.kozenbridge cat shared_prefs/iretail_payment_bridge_v1.xml > "%OUT%\08_kozen_bridge_prefs_raw.txt" 2>nul
  adb -s "%KOZEN%" logcat -d -v threadtime IretailKozenBridge:V AndroidRuntime:E *:S > "%OUT%\09_kozen_logcat_raw.txt" 2>&1
) else (
  > "%OUT%\08_kozen_bridge_prefs_raw.txt" echo KOZEN_ADB_NOT_AVAILABLE
  > "%OUT%\09_kozen_logcat_raw.txt" echo KOZEN_ADB_NOT_AVAILABLE
)

if exist "fiscal_positive_payment_logs\FISCAL_POSITIVE_PAYMENT_v1_0_1_CONSUMED.marker" (
  copy /Y "fiscal_positive_payment_logs\FISCAL_POSITIVE_PAYMENT_v1_0_1_CONSUMED.marker" "%OUT%\10_windows_consumed_marker.txt" >nul
) else (
  > "%OUT%\10_windows_consumed_marker.txt" echo WINDOWS_CONSUMED_MARKER_NOT_FOUND
)

echo [4/5] Analyzing and sanitizing evidence...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Analyze-FiscalPaymentMarkerAudit.ps1" -ReportDir "%CD%\%OUT%"
if errorlevel 1 (
  echo [ERROR] Marker audit analysis or safety scan failed.
  pause
  exit /b 10
)

echo [5/5] Creating archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Resolve-Path '%OUT%'; $z=$p.Path+'.zip'; Compress-Archive -Path ($p.Path+'\*') -DestinationPath $z -Force; Write-Host ('[ARCHIVE] '+$z)"
if errorlevel 1 (
  echo [ERROR] Failed to create marker audit archive.
  pause
  exit /b 11
)

echo.
echo ============================================================
echo MARKER AUDIT COMPLETE
echo No financial command was sent.
echo i-Retail was requested back to safe STANDALONE foreground.
echo Send this console log or PAYMENT_MARKER_AUDIT_*.zip for analysis.
echo ============================================================
pause
exit /b 0
