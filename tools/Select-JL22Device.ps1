param(
    [string]$OutputFile,
    [string]$PreferredSerial = ""
)

$ErrorActionPreference = "Stop"

function Parse-AdbDevices {
    $rows = @()
    $raw = & adb devices -l 2>&1
    foreach ($line in $raw) {
        if ($line -match '^(\S+)\s+device(?:\s+(.*))?$') {
            $serial = $matches[1]
            $tail = $matches[2]
            $product = if ($tail -match '(?:^|\s)product:([^\s]+)') { $matches[1] } else { "" }
            $model = if ($tail -match '(?:^|\s)model:([^\s]+)') { $matches[1] } else { "" }
            $device = if ($tail -match '(?:^|\s)device:([^\s]+)') { $matches[1] } else { "" }
            $isJl22 = (
                $product -eq 'octopus_jetinno' -and
                $model -eq 'UniWin_M190' -and
                $device -eq 'octopus-jetinno'
            )
            $rows += [pscustomobject]@{
                Serial = $serial
                Product = $product
                Model = $model
                Device = $device
                IsJl22 = $isJl22
                Raw = $line
            }
        }
    }
    return @($rows)
}

$devices = Parse-AdbDevices
if ($devices.Count -eq 0) {
    Write-Host "[ERROR] ADB devices not found."
    & adb devices -l
    exit 12
}

$selected = $null

if ($PreferredSerial) {
    $preferred = @($devices | Where-Object { $_.Serial -eq $PreferredSerial })
    if ($preferred.Count -eq 1 -and $preferred[0].IsJl22) {
        $selected = $preferred[0]
        Write-Host "[OK] Explicit device matches JL22 signature: $($selected.Serial)"
    } elseif ($preferred.Count -eq 1) {
        Write-Host "[WARN] Explicit device does NOT match JL22 signature."
    } else {
        Write-Host "[WARN] Explicit device '$PreferredSerial' is not connected."
    }
}

if (-not $selected) {
    $matchesJl22 = @($devices | Where-Object { $_.IsJl22 })
    if ($matchesJl22.Count -eq 1) {
        $selected = $matchesJl22[0]
        Write-Host "[OK] JL22 detected automatically: $($selected.Serial)"
    }
}

if (-not $selected) {
    Write-Host ""
    Write-Host "Android devices found:"
    for ($i = 0; $i -lt $devices.Count; $i++) {
        $d = $devices[$i]
        $mark = if ($d.IsJl22) { " [JL22 signature]" } else { "" }
        Write-Host ("  [{0}] {1}  product:{2}  model:{3}  device:{4}{5}" -f ($i + 1), $d.Serial, $d.Product, $d.Model, $d.Device, $mark)
    }
    Write-Host ""
    while (-not $selected) {
        $answer = Read-Host ("Select device number [1-{0}]" -f $devices.Count)
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $devices.Count) {
            $selected = $devices[$number - 1]
        } else {
            Write-Host "[WARN] Invalid number."
        }
    }
}

Write-Host ("[INFO] Selected: {0}" -f $selected.Raw)
if (-not $selected.IsJl22) {
    Write-Host "[WARN] Selected device does not match the known JL22 signature."
    Write-Host "[WARN] Expected: product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno"
}

$parent = Split-Path -Parent $OutputFile
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
Set-Content -LiteralPath $OutputFile -Value $selected.Serial -Encoding ASCII -NoNewline
exit 0
