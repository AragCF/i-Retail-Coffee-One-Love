param(
    [ValidateSet('Audit','Status')][string]$Mode = 'Audit',
    [string]$PortName = '',
    [string]$ExpectedSerial = 'A507YBKB',
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'

function Get-FtdiPorts($Entities, [string]$Serial) {
    $pattern = '^FTDIBUS\\VID_0403\+PID_6001\+' + [regex]::Escape($Serial) + '(?:A)?\\'
    foreach ($item in @($Entities)) {
        if ([string]$item.PNPDeviceID -notmatch $pattern) { continue }
        $m = [regex]::Match([string]$item.Name, '\((COM[0-9]+)\)', 'IgnoreCase')
        if (-not $m.Success) { continue }
        if ($null -ne $item.ConfigManagerErrorCode -and $item.ConfigManagerErrorCode -ne 0) { continue }
        if ($null -ne $item.Present -and -not $item.Present) { continue }
        [pscustomobject]@{ Port=$m.Groups[1].Value.ToUpperInvariant(); Name=$item.Name; PnpId=$item.PNPDeviceID }
    }
}
function Get-VendorSsids([string]$Text) {
    $names = foreach ($line in ($Text -split "`r?`n")) {
        $m = [regex]::Match($line, '^\s*SSID\s+[0-9]+\s*:\s*(.*?)\s*$')
        if ($m.Success -and $m.Groups[1].Value -match '^Vendotek(?:[_ -]|$)') { $m.Groups[1].Value }
    }
    @($names | Sort-Object -Unique)
}
function Select-VerifiedPort($Candidates, [string]$Requested, $Visible) {
    $items = @($Candidates | Where-Object { $Visible -contains $_.Port })
    if ($Requested) {
        if ($Requested -notmatch '^COM[0-9]+$') { throw 'Invalid COM port name.' }
        $items = @($items | Where-Object { $_.Port -ieq $Requested })
    }
    if ($items.Count -ne 1) { throw 'A unique present FTDI port with the expected adapter serial was not verified. No COM access.' }
    return $items[0].Port
}
function Assert-Check([bool]$Ok, [string]$Name) { if (-not $Ok) { throw "SELFTEST FAILED: $Name" }; Write-Host "PASS $Name" }
if ($SelfTest) {
    $good = [pscustomobject]@{ Name='USB Serial Port (COM24)'; PNPDeviceID='FTDIBUS\VID_0403+PID_6001+A507YBKBA\0000'; ConfigManagerErrorCode=0; Present=$true }
    $bt = [pscustomobject]@{ Name='Standard Serial over Bluetooth link (COM7)'; PNPDeviceID='BTHENUM\OTHER'; ConfigManagerErrorCode=0; Present=$true }
    $bad = [pscustomobject]@{ Name='USB Serial Port (COM8)'; PNPDeviceID='FTDIBUS\VID_0403+PID_6001+OTHER123A\0000'; ConfigManagerErrorCode=0; Present=$true }
    $ports = @(Get-FtdiPorts @($good,$bt,$bad) 'A507YBKB')
    Assert-Check ($ports.Count -eq 1 -and $ports[0].Port -eq 'COM24') 'identity_not_bluetooth'
    Assert-Check ((Select-VerifiedPort $ports '' @('COM7','COM24')) -eq 'COM24') 'automatic_port'
    $blocked=$false; try { [void](Select-VerifiedPort $ports 'COM7' @('COM7','COM24')) } catch { $blocked=$true }
    Assert-Check $blocked 'reject_explicit_wrong_port'
    $blocked=$false; try { [void](Select-VerifiedPort $ports '' @('COM7')) } catch { $blocked=$true }
    Assert-Check $blocked 'reject_absent_port'
    $good.Present=$false
    Assert-Check (@(Get-FtdiPorts @($good) 'A507YBKB').Count -eq 0) 'reject_phantom_device'
    $good.Present=$true; $good.ConfigManagerErrorCode=22
    Assert-Check (@(Get-FtdiPorts @($good) 'A507YBKB').Count -eq 0) 'reject_disabled_device'
    $names = @(Get-VendorSsids "SSID 1 : PrivateHome`r`nSSID 2 : Vendotek_220000047601`r`nBSSID 1 : 01:02:03:04:05:06`r`nSSID 3 : Vendotek_220000047601")
    Assert-Check ($names.Count -eq 1 -and $names[0] -eq 'Vendotek_220000047601') 'vendor_ssids_only'
    Assert-Check (@(Get-VendorSsids 'No wireless interface').Count -eq 0) 'no_fabricated_ssid'
    Write-Host 'SELFTEST_OK 8 checks; no hardware opened and no network settings changed.'
    exit 0
}

$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root = Join-Path $project 'vendotek_network_logs'
$out = Join-Path $root ('VENDOTEK_NETWORK_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $out -Force | Out-Null
$log = Join-Path $out '01_audit.txt'
$summary = New-Object 'System.Collections.Generic.List[string]'
function Note([string]$Text) { Write-Host $Text; Add-Content -LiteralPath $log -Value $Text -Encoding UTF8 }
$outcome='AUDIT_ERROR'; $rc=1
try {
    Note 'i-Retail v0.5.33 - Vendotek network access / verified COM diagnostics'
    Note "MODE=$Mode"
    Note 'No driver, IP, Wi-Fi profile, sharing, firmware or bank configuration is changed.'
    Note 'No passwords, Wi-Fi keys or unrelated SSID names are collected.'
    try { $entities = @(Get-CimInstance Win32_PnPEntity) }
    catch { $entities = @(Get-WmiObject Win32_PnPEntity) }
    $ports = @(Get-FtdiPorts $entities $ExpectedSerial)
    $visible = @([IO.Ports.SerialPort]::GetPortNames())
    foreach ($p in $ports) { Note "FTDI_PORT=$($p.Port) PNP=$($p.PnpId)" }
    [void]$summary.Add('VERSION=0.5.33')
    [void]$summary.Add("MODE=$Mode")
    [void]$summary.Add("EXPECTED_FTDI_SERIAL=$ExpectedSerial")
    [void]$summary.Add('FTDI_PORTS=' + (($ports | ForEach-Object { $_.Port }) -join ','))
    $usbNics = @($entities | Where-Object { $_.PNPClass -eq 'Net' -and $_.PNPDeviceID -like 'USB\*' -and $_.ConfigManagerErrorCode -eq 0 -and ($null -eq $_.Present -or $_.Present) })
    foreach ($n in $usbNics) { Note "USB_NETWORK_CANDIDATE=$($n.Name) PNP=$($n.PNPDeviceID)" }
    [void]$summary.Add("USB_NETWORK_CANDIDATE_COUNT=$($usbNics.Count)")
    Note 'A USB network adapter, if listed, is only a candidate; it may belong to another device.'
    if ($Mode -eq 'Audit') {
        $seen = New-Object 'System.Collections.Generic.List[string]'
        $scanErrors=0
        for ($i=1; $i -le 3; $i++) {
            try {
                $text = (& netsh.exe wlan show networks mode=bssid 2>&1 | Out-String)
                $netshRc=$LASTEXITCODE
                if ($netshRc -ne 0) { $scanErrors++; Note "WLAN_SCAN=$i ERROR_CODE=$netshRc" }
                foreach ($ssid in @(Get-VendorSsids $text)) { [void]$seen.Add($ssid); Note "VENDOTEK_SSID=$ssid" }
            } catch { $scanErrors++; Note "WLAN_SCAN=$i UNAVAILABLE" }
            if ($i -lt 3) { Start-Sleep -Seconds 3 }
        }
        $unique=@($seen | Sort-Object -Unique)
        [void]$summary.Add('VENDOTEK_SSIDS=' + ($unique -join '|'))
        [void]$summary.Add("WLAN_SCAN_ERRORS=$scanErrors")
        [void]$summary.Add('NO_SSID_DOES_NOT_PROVE_WIFI_UNSUPPORTED=true')
        if ($unique.Count -gt 0) { $outcome='VENDOTEK_AP_OBSERVED' }
        elseif ($scanErrors -gt 0) { $outcome='WLAN_SCAN_INCONCLUSIVE' }
        else { $outcome='NO_VENDOTEK_SSID_OBSERVED' }
        Note 'This mode opens no COM port. It does not activate the terminal access point.'
        Note 'VTKPOS-V2: at boot, present a card/NFC device while all four LEDs blink in turn.'
        Note 'Then use the documented Wi-Fi menu. VTKPOS-V1 instead needs the supplier headless utility.'
        Note 'After manual network setup, saving and reboot: run VENDOTEK_12_STATUS_AFTER_WIFI.bat.'
        $rc=0
    } else {
        $verified=Select-VerifiedPort $ports $PortName $visible
        [void]$summary.Add("VERIFIED_PORT=$verified")
        Note "VERIFIED_PORT=$verified"
        Note 'Sending only the existing IDL + STATUS probe. No sale or TMS request.'
        $probe=Join-Path $PSScriptRoot 'VendotekWindowsComProbe.ps1'
        if (-not (Test-Path -LiteralPath $probe)) { throw 'The existing VendotekWindowsComProbe.ps1 is missing. Run from the full repository.' }
        $exe=Join-Path $PSHOME 'powershell.exe'
        $child = @(& $exe -NoProfile -ExecutionPolicy Bypass -File $probe -PortName $verified 2>&1)
        $childRc=$LASTEXITCODE
        # Retain only status/error markers in the publishable report, never raw frames.
        $safe = @($child | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^(VTK_CODEC_SELFTEST_OK|COM_OPEN_OK|VTK_IDL_OK|VTK_STATUS value=|VENDOTEK_WINDOWS_COM_OK|ERROR=)' })
        foreach ($line in $safe) { Note $line }
        $status=@($safe | Where-Object { $_ -like 'VTK_STATUS value=*' })
        if ($childRc -ne 0 -or $status.Count -eq 0) { throw "COM status probe did not complete successfully, code=$childRc. No automatic retry." }
        [void]$summary.Add($status[-1])
        [void]$summary.Add('PAYMENT_READINESS=NOT_CERTIFIED_BY_THIS_SINGLE_STATUS_CHECK')
        $outcome='COM_STATUS_READ'; $rc=0
    }
} catch {
    Note ('ERROR=' + $_.Exception.Message)
    $outcome='AUDIT_ERROR'; $rc=1
} finally {
    [void]$summary.Add("OUTCOME=$outcome")
    [void]$summary.Add('FINANCIAL_COMMANDS=NONE')
    [void]$summary.Add('TMS_COMMANDS=NONE')
    [void]$summary.Add('NETWORK_CONFIGURATION_WRITES=NONE')
    $summary | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8
    try {
        $zip=$out+'.zip'
        Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
        Write-Host "[ARCHIVE] $zip"
        Write-Host "OUTCOME=$outcome"
        Write-Host 'Publish only this limited report with GIT_123_PUBLISH_VENDOTEK_NETWORK_RESULT.bat.'
    } catch { Write-Host ('ARCHIVE_ERROR=' + $_.Exception.Message); $rc=2 }
}
exit $rc
