param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $RepoRoot = (Resolve-Path $RepoRoot).Path
}

$configPath = Join-Path $RepoRoot "app\src\main\assets\content\iretail-api.json"
if (-not (Test-Path -LiteralPath $configPath)) { throw "Missing config: $configPath" }
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw "curl.exe not found" }

$config = Get-Content -Raw -LiteralPath $configPath -Encoding UTF8 | ConvertFrom-Json
$baseUrl = ([string]$config.base_url).TrimEnd("/") + "/"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$root = Join-Path $RepoRoot "test_reports\s3_device_code_source"
$out = Join-Path $root ("S3_DEVICE_CODE_SOURCE_" + $stamp)
$zip = $out + ".zip"
$tmp = Join-Path $env:TEMP ("iretail_s3code_" + $stamp + "_" + $PID)

New-Item -ItemType Directory -Path $out -Force | Out-Null
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Text([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}

function Save-Json([string]$Path,$Value,[int]$Depth = 12) {
    Write-Text $Path (($Value | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine)
}

function Encode-Form([hashtable]$Fields) {
    $parts = @()
    foreach ($key in $Fields.Keys) {
        $parts += ([Net.WebUtility]::UrlEncode([string]$key) + "=" + [Net.WebUtility]::UrlEncode([string]$Fields[$key]))
    }
    return ($parts -join "&")
}

function Invoke-CurlJson([string]$Name,[string]$Path,[hashtable]$Fields,[hashtable]$Common,[string[]]$Secrets) {
    $payload = @{}
    foreach($k in $Common.Keys){ $payload[$k] = $Common[$k] }
    foreach($k in $Fields.Keys){ $payload[$k] = $Fields[$k] }

    $form = Join-Path $tmp ($Name + ".form")
    $raw = Join-Path $tmp ($Name + ".raw")
    Write-Text $form (Encode-Form $payload)

    $args = @(
        "--silent","--show-error","--location",
        "--connect-timeout","15","--max-time","45","--retry","0",
        "--request","POST",
        "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
        "--header","Accept: application/json, */*",
        "--data-binary",("@" + $form),
        "--output",$raw,
        ($baseUrl + $Path)
    )
    & curl.exe @args > $null
    $rc = $LASTEXITCODE
    if ($rc -ne 0) { throw ("curl failed for " + $Path + ": " + $rc) }
    if (-not (Test-Path -LiteralPath $raw)) { throw ("No response body for " + $Path) }

    $text = Get-Content -Raw -LiteralPath $raw -Encoding UTF8
    foreach($secret in $Secrets){
        if(-not [string]::IsNullOrEmpty($secret) -and $text.Contains($secret)){
            # Raw responses remain temporary only. Never persist them.
        }
    }
    return ($text | ConvertFrom-Json)
}

$configDeviceCode = [string]$config.device_code
$configDeviceId = [string]$config.device_id

try {
    $authForm = Join-Path $tmp "auth.form"
    Write-Text $authForm (Encode-Form @{
        username=[string]$config.login
        password=[string]$config.password
        client_id=[string]$config.client_id
        client_secret=[string]$config.client_secret
    })
    $authRaw = Join-Path $tmp "auth.raw"

    & curl.exe --silent --show-error --location --connect-timeout 15 --max-time 45 --retry 0 --request POST ^
        --header "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" ^
        --header "Accept: application/json, */*" ^
        --data-binary ("@" + $authForm) ^
        --output $authRaw ^
        ($baseUrl + "user/authentication") > $null
    if ($LASTEXITCODE -ne 0) { throw "Authentication curl failed" }

    $auth = Get-Content -Raw -LiteralPath $authRaw -Encoding UTF8 | ConvertFrom-Json
    $token = ""
    if ($null -ne $auth.result -and $auth.result.PSObject.Properties.Name -contains "access_token") {
        $token = [string]$auth.result.access_token
    }
    if ([string]::IsNullOrWhiteSpace($token)) { throw "Authentication did not produce access token" }

    $secrets = @(
        [string]$config.login,
        [string]$config.password,
        [string]$config.client_secret,
        [string]$config.device_code,
        $token
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $common = @{
        client_id=[string]$config.client_id
        client_secret=[string]$config.client_secret
        access_token=$token
    }

    $devicesResponse = Invoke-CurlJson "devices" "iretail/device/get-by-channel-id" @{
        channel_id=[string]$config.channel_id
    } $common $secrets

    $items = @()
    if ($null -ne $devicesResponse.result) {
        if ($devicesResponse.result -is [System.Collections.IEnumerable] -and -not ($devicesResponse.result -is [string]) -and -not ($devicesResponse.result -is [pscustomobject])) {
            $items = @($devicesResponse.result)
        } elseif ($devicesResponse.result.PSObject.Properties.Name -contains "rows") {
            $items = @($devicesResponse.result.rows)
        } else {
            $items = @($devicesResponse.result)
        }
    }

    $deviceIds = @()
    foreach($item in $items){
        if($null -eq $item){ continue }
        if($item.PSObject.Properties.Name -contains "id"){
            $v=0
            if([int]::TryParse([string]$item.id,[ref]$v) -and $v -gt 0){ $deviceIds += $v }
        }
    }
    $deviceIds = @($deviceIds | Sort-Object -Unique)

    $rows = @()
    foreach($deviceId in ($deviceIds | Select-Object -First 20)){
        $infoResponse = Invoke-CurlJson ("device_" + $deviceId) "iretail/device/get-device-info" @{
            device_id=[string]$deviceId
        } $common $secrets

        $obj = $null
        if ($null -ne $infoResponse.result) { $obj = $infoResponse.result }

        $serverCode = ""
        $externalCode = ""
        $deviceType = ""
        if($null -ne $obj){
            if($obj.PSObject.Properties.Name -contains "code"){ $serverCode=[string]$obj.code }
            if($obj.PSObject.Properties.Name -contains "external_code"){ $externalCode=[string]$obj.external_code }
            if($obj.PSObject.Properties.Name -contains "type"){ $deviceType=[string]$obj.type }
            elseif($obj.PSObject.Properties.Name -contains "type_slug"){ $deviceType=[string]$obj.type_slug }
        }

        $rows += [pscustomobject]@{
            device_id=$deviceId
            device_type=$deviceType
            server_code_present=(-not [string]::IsNullOrWhiteSpace($serverCode))
            server_code_length=$serverCode.Length
            server_code_matches_config_device_code=($serverCode -ne "" -and $serverCode -eq $configDeviceCode)
            server_code_equals_device_id=($serverCode -ne "" -and $serverCode -eq [string]$deviceId)
            external_code_present=(-not [string]::IsNullOrWhiteSpace($externalCode))
            external_code_length=$externalCode.Length
            external_code_matches_config_device_code=($externalCode -ne "" -and $externalCode -eq $configDeviceCode)
        }
    }

    $summary = [ordered]@{
        audit="i-Retail S3 device code source audit"
        timestamp=$stamp
        network_actions="authentication + read-only device list/info POSTs only"
        register_calls=0
        order_send_allowed=$false
        config_update_allowed=$false
        configured_device_code_equals_device_id=($configDeviceCode -eq $configDeviceId)
        configured_device_code_length=$configDeviceCode.Length
        configured_device_id_length=$configDeviceId.Length
        devices_found=$deviceIds.Count
        device_ids=$deviceIds
        device_code_observations=$rows
    }

    Save-Json (Join-Path $out "SUMMARY.json") $summary 10
    Save-Json (Join-Path $out "DEVICE_CODE_OBSERVATIONS.json") $rows 10

    $unsafe = @()
    Get-ChildItem -LiteralPath $out -File | ForEach-Object {
        $content = Get-Content -Raw -LiteralPath $_.FullName -Encoding UTF8
        foreach($secret in $secrets){
            if(-not [string]::IsNullOrEmpty($secret) -and $content.Contains($secret)){
                $unsafe += $_.Name
                break
            }
        }
    }
    if($unsafe.Count -gt 0){
        throw ("Safety scan failed: secret value in report: " + (($unsafe | Sort-Object -Unique) -join ","))
    }

    if(Test-Path -LiteralPath $zip){ Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

    Write-Host "[SUCCESS] S3 device-code source audit completed."
    Write-Host ("[REPORT] " + $zip)
    Write-Host ("[DEVICES] " + ($deviceIds -join ","))
    foreach($row in $rows){
        Write-Host ("[DEVICE " + $row.device_id + "] codePresent=" + $row.server_code_present + " codeLength=" + $row.server_code_length + " matchesConfig=" + $row.server_code_matches_config_device_code + " externalPresent=" + $row.external_code_present + " externalMatchesConfig=" + $row.external_code_matches_config_device_code)
    }
    exit 0
}
finally {
    if(Test-Path -LiteralPath $tmp){ Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
