$ErrorActionPreference = 'Continue'

$root = Join-Path $PSScriptRoot '..\vendotek_wifi_logs'
$root = [System.IO.Path]::GetFullPath($root)
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $root ("VENDOTEK_SERVICE_WIFI_{0}" -f $ts)
New-Item -ItemType Directory -Path $out -Force | Out-Null

function Save-Netsh([string[]]$Args, [string]$File) {
    try {
        $text = & netsh @Args 2>&1 | Out-String
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

Write-Host '============================================================'
Write-Host 'i-Retail v0.5.26 - VENDOTEK SERVICE WI-FI DISCOVERY'
Write-Host '============================================================'
Write-Host 'READ-ONLY Windows Wi-Fi scan.'
Write-Host 'No connection is made to any network.'
Write-Host 'No Vendotek setting is changed.'
Write-Host 'No VTK message and no financial command is sent.'
Write-Host '============================================================'
Write-Host ''

$interfaces = Save-Netsh @('wlan','show','interfaces') (Join-Path $out '01_wlan_interfaces.txt')
$drivers = Save-Netsh @('wlan','show','drivers') (Join-Path $out '02_wlan_drivers.txt')

if ($interfaces -match '(?i)(There is no wireless interface|Беспроводн.*интерфейс.*отсутств|Wireless AutoConfig Service.*not running)') {
    'NO_WLAN_ADAPTER_OR_SERVICE' | Set-Content -LiteralPath (Join-Path $out 'OUTCOME.txt') -Encoding UTF8
    @(
        'OUTCOME=NO_WLAN_ADAPTER_OR_SERVICE',
        'Windows did not expose an active WLAN interface to netsh.',
        'No terminal setting was changed.'
    ) | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8
    Write-Host '[ERROR] Windows WLAN interface/service is unavailable.'
    Write-Host "Evidence folder: $out"
    exit 2
}

Write-Host 'STEP 1/3'
Write-Host 'Turn OFF only the Vendotek terminal.'
Write-Host 'Leave it without power for about 10 seconds.'
[void](Read-Host 'Press Enter while Vendotek is still OFF')

$baselineText = Save-Netsh @('wlan','show','networks','mode=bssid') (Join-Path $out '03_baseline_vendotek_off.txt')
$baselineSsids = Get-SsidsFromText $baselineText

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
    $text = (& netsh wlan show networks mode=bssid 2>&1 | Out-String)
    Add-Content -LiteralPath $scanLog -Encoding UTF8 -Value "===== SCAN $i @ $stamp ====="
    Add-Content -LiteralPath $scanLog -Encoding UTF8 -Value $text
    foreach ($ssid in (Get-SsidsFromText $text)) { [void]$allAfter.Add($ssid) }
    Write-Progress -Activity 'Scanning Wi-Fi after Vendotek power-on' -Status "Scan $i / 24" -PercentComplete ([int](100*$i/24))
    Start-Sleep -Seconds 3
}
Write-Progress -Activity 'Scanning Wi-Fi after Vendotek power-on' -Completed

$afterSsids = @($allAfter | Sort-Object -Unique)
$candidates = @($afterSsids | Where-Object { $baselineSsids -notcontains $_ })

$baselineSsids | Set-Content -LiteralPath (Join-Path $out '05_baseline_ssids.txt') -Encoding UTF8
$afterSsids | Set-Content -LiteralPath (Join-Path $out '06_after_power_on_ssids.txt') -Encoding UTF8
$candidates | Set-Content -LiteralPath (Join-Path $out '07_candidate_new_ssids.txt') -Encoding UTF8

$outcome = if ($candidates.Count -gt 0) { 'CANDIDATE_SSID_FOUND' } else { 'NO_NEW_SSID_SEEN' }
$outcome | Set-Content -LiteralPath (Join-Path $out 'OUTCOME.txt') -Encoding UTF8

$summary = New-Object System.Collections.Generic.List[string]
[void]$summary.Add("OUTCOME=$outcome")
[void]$summary.Add('')
[void]$summary.Add('BASELINE SSIDs (Vendotek OFF):')
if ($baselineSsids.Count -eq 0) { [void]$summary.Add('  <none parsed>') } else { foreach ($s in $baselineSsids) { [void]$summary.Add("  $s") } }
[void]$summary.Add('')
[void]$summary.Add('ALL SSIDs SEEN AFTER VENDOTEK POWER-ON:')
if ($afterSsids.Count -eq 0) { [void]$summary.Add('  <none parsed>') } else { foreach ($s in $afterSsids) { [void]$summary.Add("  $s") } }
[void]$summary.Add('')
[void]$summary.Add('NEW SSID CANDIDATES:')
if ($candidates.Count -eq 0) { [void]$summary.Add('  <none>') } else { foreach ($s in $candidates) { [void]$summary.Add("  $s") } }
[void]$summary.Add('')
[void]$summary.Add('SAFETY: passive scan only; no Wi-Fi association; no VTK command; no payment.')
$summary | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8

Write-Host ''
Write-Host 'STEP 3/3'
Write-Host "Result: $outcome"
if ($candidates.Count -gt 0) {
    Write-Host 'New SSID candidate(s):'
    $candidates | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host 'No SSID appeared that was absent from the OFF baseline.'
}

$zip = "$out.zip"
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[SUCCESS] $zip"
Write-Host 'No connection was made and no terminal setting was changed.'
