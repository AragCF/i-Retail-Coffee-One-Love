$ErrorActionPreference = 'Continue'

$root = Join-Path $PSScriptRoot '..\vendotek_wifi_logs'
$root = [System.IO.Path]::GetFullPath($root)
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ("VENDOTEK_SERVICE_WIFI_{0}" -f $ts)
New-Item -ItemType Directory -Path $out -Force | Out-Null

function Save-Netsh([string[]]$NetshArgs, [string]$File) {
    try {
        $text = & netsh @NetshArgs 2>&1 | Out-String
    } catch {
        $text = "ERROR: $($_.Exception.Message)"
    }
    $text | Set-Content -LiteralPath $File -Encoding UTF8
    return $text
}

function Get-SsidsFromText([string]$Text) {
    $items = @()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*SSID\s+\d+\s*:\s*(.*?)\s*$') {
            $value = $Matches[1].Trim()
            if ($value) { $items += $value }
        }
    }
    return @($items | Sort-Object -Unique)
}

function Finish-Archive([string]$Outcome) {
    $zip = "$out.zip"
    if (-not (Test-Path (Join-Path $out 'OUTCOME.txt'))) {
        $Outcome | Set-Content -LiteralPath (Join-Path $out 'OUTCOME.txt') -Encoding UTF8
    }
    Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
    Write-Host "[SUCCESS] $zip"
    return $zip
}

Write-Host '============================================================'
Write-Host 'i-Retail v0.5.26.1 - VENDOTEK SERVICE WI-FI DISCOVERY'
Write-Host '============================================================'
Write-Host 'READ-ONLY Windows Wi-Fi scan.'
Write-Host 'No connection is made to any network.'
Write-Host 'No Vendotek setting is changed.'
Write-Host 'No VTK message and no financial command is sent.'
Write-Host '============================================================'
Write-Host ''

# Keep this script ASCII-only. Windows PowerShell 5.1 on older localized
# Windows systems may misread UTF-8 source files without BOM before parsing.
$interfaces = Save-Netsh -NetshArgs @('wlan','show','interfaces') -File (Join-Path $out '01_wlan_interfaces.txt')
$drivers = Save-Netsh -NetshArgs @('wlan','show','drivers') -File (Join-Path $out '02_wlan_drivers.txt')

Write-Host 'STEP 1/3'
Write-Host 'Turn OFF only the Vendotek terminal.'
Write-Host 'Leave it without power for about 10 seconds.'
[void](Read-Host 'Press Enter while Vendotek is still OFF')

$baselineText = Save-Netsh -NetshArgs @('wlan','show','networks','mode=bssid') -File (Join-Path $out '03_baseline_vendotek_off.txt')
$baselineSsids = @(Get-SsidsFromText $baselineText)

Write-Host ''
Write-Host 'STEP 2/3'
Write-Host 'Power ON only the Vendotek terminal now.'
Write-Host 'Do not connect Windows to any new Wi-Fi network.'
[void](Read-Host 'Press Enter immediately after powering Vendotek ON')

$allAfter = New-Object System.Collections.Generic.List[string]
$scanLog = Join-Path $out '04_scans_vendotek_on.txt'
if (Test-Path $scanLog) { Remove-Item $scanLog -Force }

for ($i = 1; $i -le 24; $i++) {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    try {
        $text = (& netsh wlan show networks mode=bssid 2>&1 | Out-String)
    } catch {
        $text = "ERROR: $($_.Exception.Message)"
    }
    Add-Content -LiteralPath $scanLog -Encoding UTF8 -Value "===== SCAN $i @ $stamp ====="
    Add-Content -LiteralPath $scanLog -Encoding UTF8 -Value $text
    foreach ($ssid in (Get-SsidsFromText $text)) {
        [void]$allAfter.Add($ssid)
    }
    Write-Progress -Activity 'Scanning Wi-Fi after Vendotek power-on' -Status "Scan $i / 24" -PercentComplete ([int](100 * $i / 24))
    Start-Sleep -Seconds 3
}
Write-Progress -Activity 'Scanning Wi-Fi after Vendotek power-on' -Completed

$afterSsids = @($allAfter | Sort-Object -Unique)
$candidates = @($afterSsids | Where-Object { $baselineSsids -notcontains $_ })

$baselineSsids | Set-Content -LiteralPath (Join-Path $out '05_baseline_ssids.txt') -Encoding UTF8
$afterSsids | Set-Content -LiteralPath (Join-Path $out '06_after_power_on_ssids.txt') -Encoding UTF8
$candidates | Set-Content -LiteralPath (Join-Path $out '07_candidate_new_ssids.txt') -Encoding UTF8

if ($baselineSsids.Count -eq 0 -and $afterSsids.Count -eq 0) {
    $outcome = 'NO_SSIDS_PARSED'
} elseif ($candidates.Count -gt 0) {
    $outcome = 'CANDIDATE_SSID_FOUND'
} else {
    $outcome = 'NO_NEW_SSID_SEEN'
}
$outcome | Set-Content -LiteralPath (Join-Path $out 'OUTCOME.txt') -Encoding UTF8

$summary = New-Object System.Collections.Generic.List[string]
[void]$summary.Add("OUTCOME=$outcome")
[void]$summary.Add('')
[void]$summary.Add('BASELINE SSIDs (Vendotek OFF):')
if ($baselineSsids.Count -eq 0) {
    [void]$summary.Add('  NONE_PARSED')
} else {
    foreach ($s in $baselineSsids) { [void]$summary.Add("  $s") }
}
[void]$summary.Add('')
[void]$summary.Add('ALL SSIDs SEEN AFTER VENDOTEK POWER-ON:')
if ($afterSsids.Count -eq 0) {
    [void]$summary.Add('  NONE_PARSED')
} else {
    foreach ($s in $afterSsids) { [void]$summary.Add("  $s") }
}
[void]$summary.Add('')
[void]$summary.Add('NEW SSID CANDIDATES:')
if ($candidates.Count -eq 0) {
    [void]$summary.Add('  NONE')
} else {
    foreach ($s in $candidates) { [void]$summary.Add("  $s") }
}
[void]$summary.Add('')
[void]$summary.Add('NOTE: a newly seen SSID is only a candidate until correlated with Vendotek power state/BSSID.')
[void]$summary.Add('SAFETY: passive scan only; no Wi-Fi association; no VTK command; no payment.')
$summary | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8

Write-Host ''
Write-Host 'STEP 3/3'
Write-Host "Result: $outcome"
if ($candidates.Count -gt 0) {
    Write-Host 'New SSID candidate(s):'
    $candidates | ForEach-Object { Write-Host "  $_" }
} elseif ($outcome -eq 'NO_SSIDS_PARSED') {
    Write-Host 'No SSID lines were parsed. Review the captured netsh output in the ZIP.'
} else {
    Write-Host 'No SSID appeared that was absent from the OFF baseline.'
}

[void](Finish-Archive $outcome)
Write-Host 'No connection was made and no terminal setting was changed.'
