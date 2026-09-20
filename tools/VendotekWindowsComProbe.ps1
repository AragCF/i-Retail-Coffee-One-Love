param(
    [string]$PortName = ''
)

$ErrorActionPreference = 'Stop'

$root = Join-Path $PSScriptRoot '..\vendotek_com_logs'
$root = [System.IO.Path]::GetFullPath($root)
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ("VENDOTEK_COM_{0}" -f $ts)
New-Item -ItemType Directory -Path $out -Force | Out-Null
$log = Join-Path $out '01_probe.txt'

function Line([string]$Text) {
    Write-Host $Text
    Add-Content -LiteralPath $log -Encoding ASCII -Value $Text
}

function Hex([byte[]]$Bytes) {
    return (($Bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Crc16Ccitt([byte[]]$Data) {
    [int]$crc = 0xFFFF
    foreach ($b in $Data) {
        $crc = $crc -bxor (([int]$b) -shl 8)
        for ($i = 0; $i -lt 8; $i++) {
            if (($crc -band 0x8000) -ne 0) {
                $crc = (($crc -shl 1) -bxor 0x1021) -band 0xFFFF
            } else {
                $crc = ($crc -shl 1) -band 0xFFFF
            }
        }
    }
    return $crc
}

function Append-Tlv([System.Collections.Generic.List[byte]]$List, [byte]$Tag, [byte[]]$Value) {
    if ($Value.Length -ge 128) { throw 'This probe only needs short TLV lengths.' }
    $List.Add($Tag)
    $List.Add([byte]$Value.Length)
    foreach ($b in $Value) { $List.Add([byte]$b) }
}

function Local-Time-Text {
    $now = Get-Date
    $offset = [TimeZoneInfo]::Local.GetUtcOffset($now)
    $sign = if ($offset.TotalMinutes -lt 0) { '-' } else { '+' }
    $hours = [Math]::Abs([int]$offset.Hours)
    $minutes = [Math]::Abs([int]$offset.Minutes)
    return $now.ToString("yyyyMMdd'T'HHmmss") + ('{0}{1:00}{2:00}' -f $sign, $hours, $minutes)
}

function Build-Frame([string]$SystemInfo) {
    $ascii = [Text.Encoding]::ASCII
    $app = [System.Collections.Generic.List[byte]]::new()
    Append-Tlv $app 0x01 ($ascii.GetBytes('IDL'))
    Append-Tlv $app 0x11 ($ascii.GetBytes((Local-Time-Text)))
    if ($SystemInfo) {
        Append-Tlv $app 0x12 ($ascii.GetBytes($SystemInfo))
    }

    [int]$length = 2 + $app.Count
    $pre = [System.Collections.Generic.List[byte]]::new()
    $pre.Add([byte]0x1F)
    $pre.Add([byte](($length -shr 8) -band 0xFF))
    $pre.Add([byte]($length -band 0xFF))
    $pre.Add([byte]0x96)
    $pre.Add([byte]0xFB)
    foreach ($b in $app) { $pre.Add([byte]$b) }

    [byte[]]$raw = $pre.ToArray()
    [int]$crc = Crc16Ccitt $raw
    $frame = [System.Collections.Generic.List[byte]]::new()
    foreach ($b in $raw) { $frame.Add([byte]$b) }
    $frame.Add([byte](($crc -shr 8) -band 0xFF))
    $frame.Add([byte]($crc -band 0xFF))
    return $frame.ToArray()
}

function Parse-Frame([byte[]]$Raw) {
    if ($Raw.Length -lt 7 -or $Raw[0] -ne 0x1F) { throw 'Invalid VTK frame.' }
    [int]$length = (([int]$Raw[1]) -shl 8) -bor ([int]$Raw[2])
    [int]$expectedTotal = $length + 5
    if ($Raw.Length -ne $expectedTotal) { throw "Frame length mismatch expected=$expectedTotal actual=$($Raw.Length)" }
    [int]$disc = (([int]$Raw[3]) -shl 8) -bor ([int]$Raw[4])
    [int]$expectedCrc = (([int]$Raw[$Raw.Length - 2]) -shl 8) -bor ([int]$Raw[$Raw.Length - 1])
    [byte[]]$withoutCrc = New-Object byte[] ($Raw.Length - 2)
    [Array]::Copy($Raw, 0, $withoutCrc, 0, $withoutCrc.Length)
    [int]$actualCrc = Crc16Ccitt $withoutCrc
    $crcOk = ($expectedCrc -eq $actualCrc)

    $tags = @{}
    [int]$p = 5
    [int]$end = 3 + $length
    while ($p -lt $end) {
        [int]$tag = $Raw[$p]; $p++
        if ($p -ge $end) { break }
        [int]$first = $Raw[$p]; $p++
        if (($first -band 0x80) -eq 0) {
            [int]$valueLength = $first
        } else {
            [int]$count = $first -band 0x7F
            if ($count -lt 1 -or $count -gt 2 -or ($p + $count) -gt $end) { break }
            [int]$valueLength = 0
            for ($i = 0; $i -lt $count; $i++) {
                $valueLength = ($valueLength -shl 8) -bor ([int]$Raw[$p]); $p++
            }
        }
        if (($p + $valueLength) -gt $end) { break }
        [byte[]]$value = New-Object byte[] $valueLength
        if ($valueLength -gt 0) { [Array]::Copy($Raw, $p, $value, 0, $valueLength) }
        $tags[$tag] = $value
        $p += $valueLength
    }

    $ascii = [Text.Encoding]::ASCII
    $message = if ($tags.ContainsKey(1)) { $ascii.GetString([byte[]]$tags[1]) } else { '' }
    $operation = if ($tags.ContainsKey(3)) { $ascii.GetString([byte[]]$tags[3]) } else { '' }
    $systemInfo = if ($tags.ContainsKey(0x12)) { $ascii.GetString([byte[]]$tags[0x12]) } else { '' }

    return [pscustomobject]@{
        Discriminator = $disc
        CrcOk = $crcOk
        Message = $message
        Operation = $operation
        SystemInfo = $systemInfo
        RawHex = Hex $Raw
    }
}

function Read-One-Frame([System.IO.Ports.SerialPort]$Port, [int]$TimeoutMs) {
    $pending = [System.Collections.Generic.List[byte]]::new()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        try {
            $value = $Port.ReadByte()
            if ($value -ge 0) { $pending.Add([byte]$value) }
        } catch [TimeoutException] {
        }

        while ($pending.Count -gt 0 -and $pending[0] -ne 0x1F) { $pending.RemoveAt(0) }
        if ($pending.Count -lt 3) { continue }
        [int]$length = (([int]$pending[1]) -shl 8) -bor ([int]$pending[2])
        [int]$total = $length + 5
        if ($length -lt 2 -or $total -gt 65540) {
            $pending.RemoveAt(0)
            continue
        }
        if ($pending.Count -lt $total) { continue }
        [byte[]]$frame = New-Object byte[] $total
        for ($i = 0; $i -lt $total; $i++) { $frame[$i] = $pending[$i] }
        return $frame
    }
    return $null
}

function Wait-For-Response([System.IO.Ports.SerialPort]$Port, [int]$TimeoutMs, [bool]$RequireSystemInfo) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        [int]$left = [Math]::Max(100, $TimeoutMs - [int]$sw.ElapsedMilliseconds)
        $raw = Read-One-Frame $Port ([Math]::Min(1000, $left))
        if ($null -eq $raw) { continue }
        $parsed = Parse-Frame $raw
        $infoText = if ($parsed.SystemInfo) { $parsed.SystemInfo } else { '-' }
        Line ("RX discriminator=0x{0:x4} crcOk={1} message={2} operation={3} systemInfo={4} raw={5}" -f $parsed.Discriminator, $parsed.CrcOk, $parsed.Message, $parsed.Operation, $infoText, $parsed.RawHex)
        if ($parsed.Discriminator -ne 0x97FB -or -not $parsed.CrcOk -or $parsed.Message -ne 'IDL') { continue }
        if ($RequireSystemInfo -and -not $parsed.SystemInfo) { continue }
        if (-not $RequireSystemInfo -and $parsed.SystemInfo) { continue }
        return $parsed
    }
    return $null
}

function Find-Vendotek-ComPort {
    $entities = @()
    try {
        $entities = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)
    } catch {
        try { $entities = @(Get-WmiObject Win32_PnPEntity -ErrorAction Stop) } catch { $entities = @() }
    }
    $matches = @($entities | Where-Object {
        $_.PNPDeviceID -match 'VID_0403.*PID_6001' -and $_.Name -match '\((COM\d+)\)'
    })
    $ports = @()
    foreach ($item in $matches) {
        if ($item.Name -match '\((COM\d+)\)') { $ports += $Matches[1] }
    }
    return @($ports | Sort-Object -Unique)
}

$outcome = 'FAILED'
$port = $null
try {
    Line '============================================================'
    Line 'i-Retail v0.5.28 - VENDOTEK DIRECT WINDOWS COM PROBE'
    Line '============================================================'
    Line 'Safety: IDL and STATUS only. No payment, VRP, FIN, ABR or DIS.'

    $expected = '1f001d96fb010349444c11143230323630313237543038343035332b30333030977e'
    [byte[]]$vector = New-Object byte[] ($expected.Length / 2)
    for ($i = 0; $i -lt $vector.Length; $i++) {
        $vector[$i] = [Convert]::ToByte($expected.Substring($i * 2, 2), 16)
    }
    [byte[]]$vectorBody = New-Object byte[] ($vector.Length - 2)
    [Array]::Copy($vector, 0, $vectorBody, 0, $vectorBody.Length)
    [int]$vectorCrc = Crc16Ccitt $vectorBody
    [int]$vectorExpectedCrc = (([int]$vector[$vector.Length - 2]) -shl 8) -bor ([int]$vector[$vector.Length - 1])
    if ($vectorCrc -ne $vectorExpectedCrc) { throw 'VTK CRC self-test failed.' }
    Line 'VTK_CODEC_SELFTEST_OK documentedIdlCrc=977e'

    $visiblePorts = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    Line ("WINDOWS_PORTS={0}" -f $(if ($visiblePorts) { $visiblePorts -join ',' } else { '<none>' }))

    if (-not $PortName) {
        $found = @(Find-Vendotek-ComPort)
        if ($found.Count -eq 0) { throw 'FTDI VID_0403 PID_6001 COM port was not found. Pass COMx explicitly if Windows shows it.' }
        if ($found.Count -gt 1) { throw ('Multiple matching COM ports found: ' + ($found -join ', ') + '. Pass COMx explicitly.') }
        $PortName = $found[0]
    }
    Line ("COM_PORT={0}" -f $PortName)

    $port = New-Object System.IO.Ports.SerialPort -ArgumentList @(
        $PortName,
        115200,
        [System.IO.Ports.Parity]::None,
        8,
        [System.IO.Ports.StopBits]::One
    )
    $port.Handshake = [System.IO.Ports.Handshake]::None
    $port.ReadTimeout = 100
    $port.WriteTimeout = 1500
    $port.DtrEnable = $false
    $port.RtsEnable = $false
    $port.Open()
    Line 'COM_OPEN_OK baud=115200 data=8 parity=None stop=1 flow=None'

    Start-Sleep -Milliseconds 250
    while ($port.BytesToRead -gt 0) { [void]$port.ReadByte() }

    $idl = Build-Frame ''
    Line ("IDL_TX bytes={0} hex={1}" -f $idl.Length, (Hex $idl))
    $port.Write($idl, 0, $idl.Length)
    $firstTx = [Diagnostics.Stopwatch]::StartNew()
    $idlResponse = Wait-For-Response $port 4000 $false
    if ($null -eq $idlResponse) { throw 'IDL response timeout.' }
    $operationText = if ($idlResponse.Operation) { $idlResponse.Operation } else { '-' }
    Line ("VTK_IDL_OK operation={0}" -f $operationText)

    while ($firstTx.ElapsedMilliseconds -lt 10100) { Start-Sleep -Milliseconds 100 }
    $status = Build-Frame 'STATUS'
    Line ("STATUS_TX bytes={0} hex={1}" -f $status.Length, (Hex $status))
    $port.Write($status, 0, $status.Length)
    $statusResponse = Wait-For-Response $port 5000 $true
    if ($null -eq $statusResponse) { throw 'STATUS response timeout.' }
    Line ("VTK_STATUS value={0}" -f $statusResponse.SystemInfo)

    $outcome = 'COM_VTK_OK'
    Line 'VENDOTEK_WINDOWS_COM_OK'
} catch {
    Line ("ERROR={0}" -f $_.Exception.Message)
    $outcome = 'COM_VTK_ERROR'
} finally {
    if ($null -ne $port) {
        try { if ($port.IsOpen) { $port.Close() } } catch {}
        try { $port.Dispose() } catch {}
    }
    @(
        "OUTCOME=$outcome",
        "PORT=$PortName",
        'USB=FTDI FT232R VID_0403 PID_6001',
        'SERIAL=115200_8N1_NO_FLOW',
        'COMMANDS=IDL_STATUS_ONLY',
        'FINANCIAL_COMMANDS=NONE'
    ) | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding ASCII
    $zip = "$out.zip"
    Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
    Write-Host "[SUCCESS] $zip"
    Write-Host "Outcome: $outcome"
}

if ($outcome -eq 'COM_VTK_OK') { exit 0 } else { exit 1 }
