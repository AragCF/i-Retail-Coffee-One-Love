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
$root = Join-Path $RepoRoot "test_reports\s3_device_service"
$out = Join-Path $root ("S3_DEVICE_SERVICE_" + $stamp)
$zip = $out + ".zip"
$tmp = Join-Path $env:TEMP ("iretail_s3ds_" + $stamp + "_" + $PID)

New-Item -ItemType Directory -Path $out -Force | Out-Null
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Text([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}

function Save-Json([string]$Path,$Value,[int]$Depth = 16) {
    Write-Text $Path (($Value | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine)
}

function Encode-Form([hashtable]$Fields) {
    $parts = @()
    foreach ($key in $Fields.Keys) {
        $parts += ([Net.WebUtility]::UrlEncode([string]$key) + "=" + [Net.WebUtility]::UrlEncode([string]$Fields[$key]))
    }
    return ($parts -join "&")
}

function Redact-Text([string]$Text,[string[]]$Secrets) {
    if ($null -eq $Text) { return "" }
    $result = $Text
    foreach ($secret in $Secrets) {
        if (-not [string]::IsNullOrEmpty($secret)) {
            $result = $result.Replace($secret,"[REDACTED]")
        }
    }
    return $result
}

function Invoke-CurlToFile([string]$Url,[string]$Output,[string[]]$Extra,[string[]]$Secrets) {
    $err = Join-Path $tmp ("curl_" + [Guid]::NewGuid().ToString("N") + ".err")
    $fmt = "http_code=%{http_code}|content_type=%{content_type}|time_total=%{time_total}|remote_ip=%{remote_ip}|url_effective=%{url_effective}"
    $args = @("--silent","--show-error","--location","--connect-timeout","15","--max-time","45","--output",$Output,"--write-out",$fmt)
    if ($null -ne $Extra) { $args += $Extra }
    $args += $Url

    $line = (& curl.exe @args 2> $err | Out-String).Trim()
    $rc = $LASTEXITCODE
    $stderr = ""

    if (Test-Path -LiteralPath $err) {
        $stderr = Redact-Text (Get-Content -Raw -LiteralPath $err -ErrorAction SilentlyContinue) $Secrets
        Remove-Item -LiteralPath $err -Force -ErrorAction SilentlyContinue
    }

    $meta = [ordered]@{
        curl_exit=$rc
        http_code=""
        content_type=""
        time_total=""
        remote_ip=""
        url_effective=""
        stderr=$stderr.Trim()
    }
    foreach ($part in ($line -split "\|")) {
        if ($part -match "^([^=]+)=(.*)$" -and $meta.Contains($matches[1])) {
            $meta[$matches[1]] = $matches[2]
        }
    }
    return [pscustomobject]$meta
}

function Is-SensitiveKey([string]$Key,[bool]$RedactNames = $false) {
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    if ($RedactNames -and $Key -match '(?i)^(name|title|description)$') { return $true }
    return ($Key -match '(?i)^(password|client_secret|secret|access_token|refresh_token|token|pin|device_code|external_code|code|phone|email|first_name|last_name|patronymic|full_name|username|address|inn|serial|serial_number|fn_serial|kkt_serial|mac|ip|url_ofd)$')
}

function Sanitize-Value($Value,[string]$Key = "",[bool]$RedactNames = $false) {
    if (Is-SensitiveKey $Key $RedactNames) {
        if ($null -eq $Value) { return $null }
        return "[REDACTED]"
    }

    if ($null -eq $Value) { return $null }

    if ($Value -is [System.Collections.IDictionary]) {
        $dict = [ordered]@{}
        foreach ($k in $Value.Keys) {
            $dict[[string]$k] = Sanitize-Value $Value[$k] ([string]$k) $RedactNames
        }
        return [pscustomobject]$dict
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(Sanitize-Value $item "" $RedactNames)
        }
        return $items
    }

    if ($Value -is [pscustomobject]) {
        $obj = [ordered]@{}
        foreach ($prop in $Value.PSObject.Properties) {
            $obj[$prop.Name] = Sanitize-Value $prop.Value $prop.Name $RedactNames
        }
        return [pscustomobject]$obj
    }

    return $Value
}

function Get-ResultItems($Response) {
    if ($null -eq $Response) { return @() }
    if ($Response.PSObject.Properties.Name -notcontains "result") { return @() }

    $result = $Response.result
    if ($null -eq $result) { return @() }

    if ($result -is [System.Collections.IEnumerable] -and -not ($result -is [string]) -and -not ($result -is [pscustomobject])) {
        return @($result)
    }

    if ($result -is [pscustomobject]) {
        if ($result.PSObject.Properties.Name -contains "rows") {
            return @($result.rows)
        }
        return @($result)
    }

    return @()
}

function Get-DeviceIds($Response) {
    $ids = @()
    foreach ($item in (Get-ResultItems $Response)) {
        if ($null -eq $item) { continue }
        if ($item.PSObject.Properties.Name -contains "id") {
            $idText = [string]$item.id
            $idValue = 0
            if ([int]::TryParse($idText,[ref]$idValue) -and $idValue -gt 0) {
                $ids += $idValue
            }
        }
    }
    return @($ids | Sort-Object -Unique)
}

function Add-SlugItems($Value,[System.Collections.Generic.List[object]]$List) {
    if ($null -eq $Value) { return }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [pscustomobject])) {
        foreach ($item in $Value) { Add-SlugItems $item $List }
        return
    }

    if ($Value -is [pscustomobject]) {
        if ($Value.PSObject.Properties.Name -contains "slug") {
            $entry = [ordered]@{ slug=[string]$Value.slug }
            if ($Value.PSObject.Properties.Name -contains "id") { $entry.id=$Value.id }
            if ($Value.PSObject.Properties.Name -contains "title") { $entry.title=$Value.title }
            $List.Add([pscustomobject]$entry)
        }
        foreach ($prop in $Value.PSObject.Properties) {
            if ($prop.Name -ne "slug") { Add-SlugItems $prop.Value $List }
        }
    }
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1)

$baseSecrets = @(
    [string]$config.login,
    [string]$config.password,
    [string]$config.client_secret,
    [string]$config.device_code
) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

try {
    Write-Text (Join-Path $out "00_git_state.txt") ("Branch=" + $branch + [Environment]::NewLine + "SHA=" + $sha + [Environment]::NewLine)

    $safeConfig = [ordered]@{
        base_url=[string]$config.base_url
        client_id=[string]$config.client_id
        profile_id=[string]$config.profile_id
        channel_id=[string]$config.channel_id
        configured_device_id=[string]$config.device_id
        device_code_present=(-not [string]::IsNullOrWhiteSpace([string]$config.device_code))
    }
    Save-Json (Join-Path $out "01_config_sanitized.json") $safeConfig 5

    $authForm = Join-Path $tmp "auth.form"
    Write-Text $authForm (Encode-Form @{
        username=[string]$config.login
        password=[string]$config.password
        client_id=[string]$config.client_id
        client_secret=[string]$config.client_secret
    })

    $authRaw = Join-Path $tmp "auth.json"
    $authMeta = Invoke-CurlToFile ($baseUrl + "user/authentication") $authRaw @(
        "--request","POST",
        "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
        "--header","Accept: application/json, */*",
        "--data-binary",("@" + $authForm)
    ) $baseSecrets
    Save-Json (Join-Path $out "02_auth_http.json") $authMeta 5

    $token = ""
    $authStatus = $false
    if (Test-Path -LiteralPath $authRaw) {
        $authObject = Get-Content -Raw -LiteralPath $authRaw -Encoding UTF8 | ConvertFrom-Json
        $authStatus = [bool]$authObject.status
        if ($null -ne $authObject.result -and $null -ne $authObject.result.access_token) {
            $token = [string]$authObject.result.access_token
        }
    }

    Save-Json (Join-Path $out "03_auth_sanitized.json") ([ordered]@{
        http_code=$authMeta.http_code
        api_status=$authStatus
        token_present=(-not [string]::IsNullOrWhiteSpace($token))
    }) 4

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Authentication did not produce access token"
    }

    $allSecrets = @($baseSecrets + @($token)) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique
    $common = @{
        client_id=[string]$config.client_id
        client_secret=[string]$config.client_secret
        access_token=$token
    }

    function Invoke-ReadOnlyApi([string]$Name,[string]$Path,[hashtable]$Fields,[bool]$RedactNames = $false) {
        $payload = @{}
        foreach ($key in $common.Keys) { $payload[$key] = $common[$key] }
        foreach ($key in $Fields.Keys) { $payload[$key] = $Fields[$key] }

        $form = Join-Path $tmp ($Name + ".form")
        $raw = Join-Path $tmp ($Name + ".raw")
        Write-Text $form (Encode-Form $payload)

        $meta = Invoke-CurlToFile ($baseUrl + $Path) $raw @(
            "--request","POST",
            "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
            "--header","Accept: application/json, */*",
            "--data-binary",("@" + $form)
        ) $allSecrets

        Save-Json (Join-Path $out ($Name + "_http.json")) $meta 5

        $response = $null
        $parsed = $false
        $apiStatus = $null
        $bodySize = 0

        if (Test-Path -LiteralPath $raw) {
            $bodySize = (Get-Item -LiteralPath $raw).Length
            try {
                $response = Get-Content -Raw -LiteralPath $raw -Encoding UTF8 | ConvertFrom-Json
                if ($response.PSObject.Properties.Name -contains "status") { $apiStatus = [bool]$response.status }
                $safe = Sanitize-Value $response "" $RedactNames
                Save-Json (Join-Path $out ($Name + "_sanitized.json")) $safe 20
                $parsed = $true
            } catch {
                Save-Json (Join-Path $out ($Name + "_non_json.json")) ([ordered]@{
                    body_saved=$false
                    body_size=$bodySize
                    parse_error=$_.Exception.GetType().Name
                }) 5
            }
        }

        return [pscustomobject]@{
            name=$Name
            path=$Path
            meta=$meta
            response=$response
            parsed=$parsed
            api_status=$apiStatus
            body_size=$bodySize
        }
    }

    $results = @()

    $channel = Invoke-ReadOnlyApi "10_channel" "iretail/channel/get" @{channel_id=[string]$config.channel_id} $true
    $results += $channel

    $devices = Invoke-ReadOnlyApi "11_devices_by_channel" "iretail/device/get-by-channel-id" @{channel_id=[string]$config.channel_id} $true
    $results += $devices

    $serviceProfile = Invoke-ReadOnlyApi "12_service_in_profile" "service-in/get-service-in" @{profile_id=[string]$config.profile_id} $false
    $results += $serviceProfile

    $serviceUsed = Invoke-ReadOnlyApi "13_service_in_used" "service-in/get-used" @{profile_id=[string]$config.profile_id} $false
    $results += $serviceUsed

    $serviceTypes = Invoke-ReadOnlyApi "14_service_in_types" "service-in/get-service-in-types" @{} $false
    $results += $serviceTypes

    $deviceIds = @(Get-DeviceIds $devices.response)
    $deviceIdsLimited = @($deviceIds | Select-Object -First 20)

    $deviceChecks = @()
    $counter = 20

    foreach ($deviceId in $deviceIdsLimited) {
        $infoName = ("{0:D2}_device_{1}_info" -f $counter,$deviceId)
        $deviceInfo = Invoke-ReadOnlyApi $infoName "iretail/device/get-device-info" @{device_id=[string]$deviceId} $true
        $results += $deviceInfo
        $counter++

        $shiftName = ("{0:D2}_device_{1}_shift" -f $counter,$deviceId)
        $shift = Invoke-ReadOnlyApi $shiftName "iretail/shift/get-current-active-shift" @{device_id=[string]$deviceId} $true
        $results += $shift
        $counter++

        $shiftId = $null
        $shiftStatusId = $null
        $checkCounter = $null
        $cashierOpeningId = $null

        if ($null -ne $shift.response -and $shift.api_status -eq $true -and $null -ne $shift.response.result) {
            $sr = $shift.response.result
            if ($sr.PSObject.Properties.Name -contains "id") { $shiftId = $sr.id }
            if ($sr.PSObject.Properties.Name -contains "status_id") { $shiftStatusId = $sr.status_id }
            if ($sr.PSObject.Properties.Name -contains "check_counter") { $checkCounter = $sr.check_counter }
            if ($sr.PSObject.Properties.Name -contains "cashier_opening_id") { $cashierOpeningId = $sr.cashier_opening_id }
        }

        $deviceChecks += [pscustomobject]@{
            device_id=$deviceId
            device_info_api_status=$deviceInfo.api_status
            active_shift_api_status=$shift.api_status
            shift_id=$shiftId
            shift_status_id=$shiftStatusId
            check_counter=$checkCounter
            cashier_opening_id=$cashierOpeningId
        }
    }

    Save-Json (Join-Path $out "80_device_checks.json") $deviceChecks 10

    $profileServiceItems = New-Object System.Collections.Generic.List[object]
    if ($null -ne $serviceProfile.response) { Add-SlugItems $serviceProfile.response.result $profileServiceItems }

    $usedServiceItems = New-Object System.Collections.Generic.List[object]
    if ($null -ne $serviceUsed.response) { Add-SlugItems $serviceUsed.response.result $usedServiceItems }

    $configuredDeviceIdValue = 0
    [void][int]::TryParse([string]$config.device_id,[ref]$configuredDeviceIdValue)
    $configuredDeviceFound = ($deviceIds -contains $configuredDeviceIdValue)

    $profileServiceArray = $profileServiceItems.ToArray()
    $usedServiceArray = $usedServiceItems.ToArray()

    $summary = [ordered]@{
        audit="i-Retail S3 device/service reconciliation"
        timestamp=$stamp
        git_branch=$branch
        git_sha=$sha
        auth_http_code=$authMeta.http_code
        auth_api_status=$authStatus
        configured_device_id=[string]$config.device_id
        channel_id=[string]$config.channel_id
        profile_id=[string]$config.profile_id
        devices_found=$deviceIds.Count
        devices_checked=$deviceIdsLimited.Count
        device_ids=$deviceIdsLimited
        configured_device_found=$configuredDeviceFound
        device_checks=$deviceChecks
        profile_services=$profileServiceArray
        used_services=$usedServiceArray
        order_send_allowed=$false
        automatic_device_selection=$false
        network_actions="authentication + semantically read-only reconciliation POSTs only"
    }
    Save-Json (Join-Path $out "SUMMARY.json") $summary 16

    $resultRows = @($results | ForEach-Object {
        [pscustomobject]@{
            name=$_.name
            path=$_.path
            http_code=$_.meta.http_code
            curl_exit=$_.meta.curl_exit
            json_parsed=$_.parsed
            api_status=$_.api_status
            body_size=$_.body_size
        }
    })
    Save-Json (Join-Path $out "90_results.json") $resultRows 10

    $summaryLines = @(
        "i-Retail S3 device/service reconciliation",
        "Timestamp=" + $stamp,
        "GitBranch=" + $branch,
        "GitSHA=" + $sha,
        "ConfiguredDeviceId=" + [string]$config.device_id,
        "DevicesFound=" + $deviceIds.Count,
        "DevicesChecked=" + $deviceIdsLimited.Count,
        "ConfiguredDeviceFound=" + $configuredDeviceFound,
        "ProfileServiceSlugs=" + ((@($profileServiceItems | ForEach-Object { $_.slug }) | Sort-Object -Unique) -join ","),
        "UsedServiceSlugs=" + ((@($usedServiceItems | ForEach-Object { $_.slug }) | Sort-Object -Unique) -join ","),
        "OrderSendAllowed=NO",
        "AutomaticDeviceSelection=NO"
    )
    Write-Text (Join-Path $out "SUMMARY.txt") (($summaryLines -join [Environment]::NewLine) + [Environment]::NewLine)

    $unsafe = @()
    Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object { $_.Extension -match "^\.(txt|json)$" } | ForEach-Object {
        $content = Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
        foreach ($secret in $allSecrets) {
            if ($null -ne $content -and -not [string]::IsNullOrEmpty($secret) -and $content.Contains($secret)) {
                $unsafe += $_.FullName
                break
            }
        }
    }

    if ($unsafe.Count -gt 0) {
        throw "Safety scan failed: secret-like value found in report"
    }

    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

    Write-Host "[SUCCESS] S3 device/service reconciliation completed."
    Write-Host ("[REPORT] " + $zip)
    Write-Host ("[DEVICES] found=" + $deviceIds.Count + " checked=" + $deviceIdsLimited.Count + " configuredFound=" + $configuredDeviceFound)
    Write-Host ("[PROFILE SERVICES] " + ((@($profileServiceItems | ForEach-Object { $_.slug }) | Sort-Object -Unique) -join ","))
    Write-Host ("[USED SERVICES] " + ((@($usedServiceItems | ForEach-Object { $_.slug }) | Sort-Object -Unique) -join ","))
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
