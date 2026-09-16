param(
    [string]$PortName = ''
)

$ErrorActionPreference = 'Continue'
$root = Join-Path $PSScriptRoot '..\vendotek_ftdi_audit_logs'
$root = [System.IO.Path]::GetFullPath($root)
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ("VENDOTEK_FTDI_AUDIT_{0}" -f $ts)
New-Item -ItemType Directory -Path $out -Force | Out-Null
$log = Join-Path $out '01_audit.txt'

function Line([string]$Text) {
    Write-Host $Text
    Add-Content -LiteralPath $log -Encoding ASCII -Value $Text
}

function Safe([object]$Value) {
    if ($null -eq $Value) { return '-' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '-' }
    return ($s -replace '[\r\n]+',' ').Trim()
}

function Find-FtdiEntities {
    try {
        return @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object {
            $_.PNPDeviceID -match 'VID_0403.*PID_6001'
        })
    } catch {
        try {
            return @(Get-WmiObject Win32_PnPEntity -ErrorAction Stop | Where-Object {
                $_.PNPDeviceID -match 'VID_0403.*PID_6001'
            })
        } catch {
            return @()
        }
    }
}

function Detect-Port([object[]]$Entities) {
    $ports = @()
    foreach ($item in $Entities) {
        if ($item.Name -match '\((COM\d+)\)') { $ports += $Matches[1] }
    }
    return @($ports | Sort-Object -Unique)
}

$outcome = 'AUDIT_ERROR'
$serial = $null
try {
    Line '============================================================'
    Line 'i-Retail v0.5.30 - VENDOTEK WINDOWS FTDI READ-ONLY AUDIT'
    Line '============================================================'
    Line 'No bytes are written to Vendotek. No VTK and no payment.'

    $entities = @(Find-FtdiEntities)
    Line ("FTDI_ENTITY_COUNT={0}" -f $entities.Count)
    $n = 0
    foreach ($e in $entities) {
        $n++
        Line ("ENTITY[{0}].Name={1}" -f $n,(Safe $e.Name))
        Line ("ENTITY[{0}].PNPDeviceID={1}" -f $n,(Safe $e.PNPDeviceID))
        Line ("ENTITY[{0}].Status={1}" -f $n,(Safe $e.Status))
        Line ("ENTITY[{0}].ConfigManagerErrorCode={1}" -f $n,(Safe $e.ConfigManagerErrorCode))
    }

    if (-not $PortName) {
        $ports = @(Detect-Port $entities)
        if ($ports.Count -eq 1) { $PortName = $ports[0] }
        elseif ($ports.Count -gt 1) { throw ('Multiple FTDI COM ports: ' + ($ports -join ',')) }
        else { throw 'FTDI VID_0403 PID_6001 COM port not found.' }
    }
    Line ("COM_PORT={0}" -f $PortName)
    Line ("WINDOWS_PORTS={0}" -f (([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object) -join ','))

    try {
        $sp = Get-CimInstance Win32_SerialPort -Filter ("DeviceID='{0}'" -f $PortName) -ErrorAction Stop
        if ($null -ne $sp) {
            Line ("SERIAL.Caption={0}" -f (Safe $sp.Caption))
            Line ("SERIAL.PNPDeviceID={0}" -f (Safe $sp.PNPDeviceID))
            Line ("SERIAL.ProviderType={0}" -f (Safe $sp.ProviderType))
            Line ("SERIAL.MaxBaudRate={0}" -f (Safe $sp.MaxBaudRate))
            Line ("SERIAL.Status={0}" -f (Safe $sp.Status))
        }
    } catch {
        Line ("SERIAL_CIM_ERROR={0}" -f (Safe $_.Exception.Message))
    }

    foreach ($e in $entities) {
        $id = [string]$e.PNPDeviceID
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        try {
            $drv = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $_.DeviceID -eq $id }
            foreach ($d in @($drv)) {
                Line ("DRIVER.DeviceName={0}" -f (Safe $d.DeviceName))
                Line ("DRIVER.ProviderName={0}" -f (Safe $d.DriverProviderName))
                Line ("DRIVER.Version={0}" -f (Safe $d.DriverVersion))
                Line ("DRIVER.Date={0}" -f (Safe $d.DriverDate))
                Line ("DRIVER.InfName={0}" -f (Safe $d.InfName))
                Line ("DRIVER.IsSigned={0}" -f (Safe $d.IsSigned))
            }
        } catch {
            Line ("DRIVER_CIM_ERROR={0}" -f (Safe $_.Exception.Message))
        }

        try {
            $regPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\' + $id + '\Device Parameters'
            $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
            Line ("REG.PortName={0}" -f (Safe $props.PortName))
        } catch {
            Line ("REG_ERROR={0}" -f (Safe $_.Exception.Message))
        }
    }

    try {
        $modeOut = & mode $PortName 2>&1 | Out-String
        Line 'MODE_BEGIN'
        foreach ($line in ($modeOut -split "`r?`n")) { if ($line.Trim()) { Line ('MODE ' + $line.Trim()) } }
        Line 'MODE_END'
    } catch {
        Line ("MODE_ERROR={0}" -f (Safe $_.Exception.Message))
    }

    $serial = New-Object System.IO.Ports.SerialPort -ArgumentList @(
        $PortName,
        115200,
        [System.IO.Ports.Parity]::None,
        8,
        [System.IO.Ports.StopBits]::One
    )
    $serial.Handshake = [System.IO.Ports.Handshake]::None
    $serial.ReadTimeout = 100
    $serial.WriteTimeout = 1500
    $serial.DtrEnable = $false
    $serial.RtsEnable = $false
    $serial.Open()
    Line 'COM_OPEN_READONLY_OK baud=115200 data=8 parity=None stop=1 handshake=None'
    Line ("SIGNALS CTS={0} DSR={1} CD={2}" -f $serial.CtsHolding,$serial.DsrHolding,$serial.CDHolding)
    Line ("BUFFERS BytesToRead={0} BytesToWrite={1}" -f $serial.BytesToRead,$serial.BytesToWrite)
    Start-Sleep -Milliseconds 500
    Line ("BUFFERS_AFTER_500MS BytesToRead={0} BytesToWrite={1}" -f $serial.BytesToRead,$serial.BytesToWrite)

    $outcome = 'PASSIVE_FTDI_AUDIT_OK'
    Line ('OUTCOME=' + $outcome)
} catch {
    Line ("ERROR={0}" -f (Safe $_.Exception.Message))
    $outcome = 'PASSIVE_FTDI_AUDIT_ERROR'
} finally {
    if ($null -ne $serial) {
        try { if ($serial.IsOpen) { $serial.Close() } } catch {}
        try { $serial.Dispose() } catch {}
    }
    @(
        "OUTCOME=$outcome",
        "PORT=$PortName",
        'USB=FTDI FT232R VID_0403 PID_6001',
        'ACTION=READ_ONLY_DRIVER_AND_PORT_AUDIT',
        'VTK_WRITES=NONE',
        'FINANCIAL_COMMANDS=NONE'
    ) | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding ASCII
    $zip = "$out.zip"
    Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
    Write-Host "[SUCCESS] $zip"
    Write-Host "Outcome: $outcome"
}

if ($outcome -eq 'PASSIVE_FTDI_AUDIT_OK') { exit 0 } else { exit 1 }
