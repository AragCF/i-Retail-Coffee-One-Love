param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location -LiteralPath $repo
$expected = '0.5.128-device-binding'
$serial = $null
$canPublish = $false
$report = [ordered]@{
    schema = 'iretail.device-binding.smoke.v1'
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    version = $expected
    source_commit = $null
    result = 'NOT_STARTED'
    installed = $false
    hardware = 'JL22_SIGNATURE_REQUIRED'
    android_api = $null
    apk_sha256 = $null
    activation_sent_by_script = $false
    financial_commands_sent_by_script = $false
    application_financial_gate = 'CLOSED_IN_THIS_RELEASE'
    data_cleared = $false
    raw_logs_in_report = $false
    binding = $null
    catalog = $null
    channel = $null
}
function Invoke-AdbChecked {
    param([string[]]$Arguments)
    $lines = @(& adb -s $script:serial @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'ADB_COMMAND_FAILED' }
    return $lines
}
function Assert-Target {
    $devices = @(& adb devices -l 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'ADB_LIST_FAILED' }
    $row = @($devices | Where-Object { $_ -match ('^' + [regex]::Escape($script:serial) + '\s+device(?:\s|$)') })
    if ($row.Count -ne 1) { throw 'SELECTED_DEVICE_NOT_READY' }
    $raw = [string]$row[0]
    foreach ($part in @('product:octopus_jetinno','model:UniWin_M190','device:octopus-jetinno')) {
        if ($raw -notmatch ('(?:^|\s)' + [regex]::Escape($part) + '(?:\s|$)')) { throw 'WRONG_DEVICE_SIGNATURE' }
    }
}
try {
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) { throw 'ADB_NOT_FOUND' }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'GIT_NOT_FOUND' }
    $gradle = Get-Content -LiteralPath (Join-Path $repo 'app\build.gradle') -Raw
    if ($gradle -notmatch ('versionName\s+''' + [regex]::Escape($expected) + '''')) { throw 'WRONG_PROJECT_VERSION' }
    & git diff HEAD --quiet -- app
    if ($LASTEXITCODE -ne 0) { throw 'UNCOMMITTED_APP_CHANGES' }
    $head = [string](& git rev-parse HEAD | Select-Object -First 1)
    if ($LASTEXITCODE -eq 0 -and $head -match '^[0-9a-f]{40}$') { $report.source_commit = $head }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('iretail-binding-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\Select-JL22Device.ps1') -OutputFile $temp
        if ($LASTEXITCODE -ne 0) { throw 'DEVICE_SELECTION_FAILED' }
        $serial = (Get-Content -LiteralPath $temp -Raw).Trim()
        if ($serial -notmatch '^[A-Za-z0-9._:\-]+$') { throw 'INVALID_ADB_SERIAL' }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
    Assert-Target
    $report.hardware = 'JL22_SIGNATURE_VERIFIED'
    $report.result = 'BUILDING'
    Write-Host '[1/5] Building locally with your existing signing key. No clean/uninstall.'
    & (Join-Path $repo 'BUILD_WINDOWS_CLI.bat')
    if ($LASTEXITCODE -ne 0) { throw 'BUILD_FAILED' }
    $apk = Join-Path $repo 'app\build\outputs\apk\debug\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apk)) { throw 'APK_NOT_FOUND' }
    $report.apk_sha256 = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Target
    Write-Host '[2/5] Installing with data preservation: adb install -r.'
    $install = @(& adb -s $serial install -r $apk 2>&1)
    if ($LASTEXITCODE -ne 0) {
        if (($install -join "`n") -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
            Write-Host '[ERROR] Signing keys differ. STOP. Do not uninstall or clear application data.'
            throw 'SIGNING_KEY_MISMATCH'
        }
        throw 'INSTALL_FAILED'
    }
    $report.installed = $true
    $api = ((Invoke-AdbChecked @('shell','getprop','ro.build.version.sdk')) -join '').Trim()
    if ($api -match '^\d{1,3}$') { $report.android_api = [int]$api }
    Write-Host '[3/5] Opening the native binding wizard. Real POS is explicitly disabled.'
    $null = Invoke-AdbChecked @('shell','am','start','-W','-n','com.coffeeonelove.iretail/.ui.MainActivity','--es','machine_mode','standalone','--ez','persist_machine_mode','true','--ez','real_pos_enabled','false')
    Write-Host ''
    Write-Host 'ON JL22: enter the Retail account credentials, API client credentials, device ID and a NEW PIN.'
    Write-Host 'The earlier PIN must be reissued in the personal account before use.'
    Write-Host 'The script never submits an activation code. Confirm activation on the JL22 screen only.'
    Write-Host 'If the result is uncertain, do not retry and do not clear data.'
    Write-Host 'If settings are pending, use Retry settings, not Repeat activation.'
    Write-Host ''
    $null = Read-Host 'After the on-screen result, press Enter here to collect the safe report'
    Assert-Target
    Write-Host '[4/5] Extracting only fixed fields. Raw logs, credentials and UI text are not saved.'
    $pidNumber = $null
    $ps = Invoke-AdbChecked @('shell','ps')
    foreach ($line in $ps) {
        $columns = ([string]$line).Trim() -split '\s+'
        if ($columns.Count -ge 3 -and $columns[-1] -eq 'com.coffeeonelove.iretail' -and $columns[1] -match '^\d+$') {
            $pidNumber = $columns[1]
        }
    }
    if ($null -ne $pidNumber) {
        $lines = Invoke-AdbChecked @('logcat','-d','-t','1000','-v','brief','IretailBinding:I','IretailCatalog:I','IretailChannelConfig:I','*:S')
        $stages = @('UNBOUND','REJECTED','REGISTERING','RESPONSE_RECEIVED','BOUND','CONFIGURED','READY','STORAGE_LOCKED')
        foreach ($line in $lines) {
            $s = [string]$line
            if ($s -notmatch ('\(\s*' + [regex]::Escape($pidNumber) + '\s*\):')) { continue }
            if ($s -match 'IretailBinding.*STATE stage=([A-Z_]+) busy=(true|false) ready=(true|false) legacyUnresolved=(true|false)$') {
                if ($stages -contains $Matches[1]) {
                    $report.binding = [ordered]@{stage=$Matches[1]; busy=($Matches[2] -eq 'true'); ready=($Matches[3] -eq 'true'); legacy_unresolved=($Matches[4] -eq 'true')}
                }
            }
            if ($s -match 'IretailCatalog.*REFRESH success=(true|false).* products=(\d+) offers=(\d+) categories=(\d+) channel=(\d+)\s') {
                $report.catalog = [ordered]@{success=($Matches[1] -eq 'true'); products=[int]$Matches[2]; offers=[int]$Matches[3]; categories=[int]$Matches[4]; channel_id=[int]$Matches[5]}
            }
            if ($s -match 'IretailChannelConfig.*REFRESH success=(true|false).* channel=(\d+) services=(\d+)\s') {
                $report.channel = [ordered]@{success=($Matches[1] -eq 'true'); channel_id=[int]$Matches[2]; services=[int]$Matches[3]}
            }
        }
    }
    if ($null -eq $report.binding) { $report.result = 'NO_BINDING_STATE_IN_CURRENT_PROCESS_LOG' }
    elseif ($report.binding.ready) { $report.result = 'BINDING_READY_OBSERVED' }
    elseif ($report.binding.legacy_unresolved) { $report.result = 'PREVIOUS_OPERATION_BLOCKS_BINDING' }
    else { $report.result = 'BINDING_NOT_READY' }
    $canPublish = $true
} catch {
    $reason = [string]$_.Exception.Message
    if ($reason -match '^[A-Z_]{3,80}$') { $report.result = $reason } else { $report.result = 'LOCAL_TOOL_FAILED' }
    Write-Host ('[ERROR] ' + $report.result)
    Write-Host 'No automatic uninstall, account reset, activation retry or payment is performed.'
}
$dir = Join-Path $repo 'reports\device-binding'
$null = New-Item -ItemType Directory -Path $dir -Force
$path = Join-Path $dir ('BINDING_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.json')
$json = $report | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('[REPORT] ' + $path)
Write-Host ('[RESULT] ' + $report.result)
if ($canPublish) {
    Write-Host '[5/5] Publishing the single constructed report and its checksum through the existing project publisher.'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\Publish-TestArtifact.ps1') -RepoRoot $repo -ArtifactPath $path -CommitPrefix 'test: device binding safe acceptance'
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[WARN] Publication did not complete. The report remains in the local repository; send this JSON only.'
        exit 2
    }
    exit 0
}
exit 1
