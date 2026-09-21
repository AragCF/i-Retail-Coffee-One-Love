param(
    [string]$RepoRoot = "",
    [switch]$ReadOnlyRecovery
)

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
$root = Join-Path $RepoRoot "test_reports\s3_device_register"
$prefix = "S3_DEVICE_REGISTER_PROBE_"
if ($ReadOnlyRecovery) { $prefix = "S3_DEVICE_REGISTER_RECOVERY_" }
$out = Join-Path $root ($prefix + $stamp)
$zip = $out + ".zip"
$tmp = Join-Path $env:TEMP ("iretail_s3reg_" + $stamp + "_" + $PID)

$localAppData = [Environment]::GetFolderPath("LocalApplicationData")
if ([string]::IsNullOrWhiteSpace($localAppData)) { throw "LocalApplicationData is unavailable" }
$markerDir = Join-Path $localAppData "CoffeeOneLove\iRetail\S3"
$localMarker = Join-Path $markerDir "device_register_probe_contract_1_0_1.json"
$repoMarker = Join-Path $root "DEVICE_REGISTER_PROBE_1_0_1.marker.json"

New-Item -ItemType Directory -Path $out -Force | Out-Null
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
New-Item -ItemType Directory -Path $root -Force | Out-Null

$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Text([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}

function Save-Json([string]$Path,$Value,[int]$Depth = 20) {
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

function Is-SensitiveKey([string]$Key,[bool]$RedactNames = $false) {
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    if ($RedactNames -and $Key -match '(?i)^(name|title|description)$') { return $true }
    return ($Key -match '(?i)(password$|secret$|token$|pin$|device_code$|external_code$|^code$|phone$|email$|first_name$|last_name$|patronymic$|full_name$|username$|address$|^inn$|serial$|serial_number$|fn_serial$|kkt_serial$|^mac$|^ip$|url_ofd$|account_id$|user_id$|offline_shop_id$)')
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
        foreach ($item in $Value) { $items += ,(Sanitize-Value $item "" $RedactNames) }
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

function Invoke-CurlRequest(
    [string]$Url,
    [string]$Output,
    [string[]]$Extra,
    [string[]]$Secrets,
    [bool]$AllowRedirect
) {
    $err = Join-Path $tmp ("curl_" + [Guid]::NewGuid().ToString("N") + ".err")
    $fmt = "http_code=%{http_code}|content_type=%{content_type}|time_total=%{time_total}|remote_ip=%{remote_ip}|url_effective=%{url_effective}"
    $args = @("--silent","--show-error","--connect-timeout","15","--max-time","45","--retry","0","--output",$Output,"--write-out",$fmt)
    if ($AllowRedirect) { $args += "--location" }
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

function Get-ResultItems($Response) {
    if ($null -eq $Response) { return @() }
    if ($Response.PSObject.Properties.Name -notcontains "result") { return @() }
    $result = $Response.result
    if ($null -eq $result) { return @() }

    if ($result -is [System.Collections.IEnumerable] -and -not ($result -is [string]) -and -not ($result -is [pscustomobject])) {
        return @($result)
    }
    if ($result -is [pscustomobject]) {
        if ($result.PSObject.Properties.Name -contains "rows") { return @($result.rows) }
        return @($result)
    }
    return @()
}

function Get-DeviceIds($Response) {
    $ids = @()
    foreach ($item in (Get-ResultItems $Response)) {
        if ($null -eq $item) { continue }
        if ($item.PSObject.Properties.Name -contains "id") {
            $value = 0
            if ([int]::TryParse([string]$item.id,[ref]$value) -and $value -gt 0) { $ids += $value }
        }
    }
    return @($ids | Sort-Object -Unique)
}

function Save-Marker([string]$Status,[string]$Outcome = "",$ReturnedDeviceId = $null,[string]$ReturnedTypeSlug = "") {
    $marker = [ordered]@{
        contract_version="1.0.1"
        status=$Status
        outcome=$Outcome
        timestamp=(Get-Date).ToString("o")
        git_branch=$branch
        git_sha=$sha
        returned_device_id=$ReturnedDeviceId
        returned_type_slug=$ReturnedTypeSlug
        automatic_retry_allowed=$false
    }
    Save-Json $repoMarker $marker 6
    Save-Json $localMarker $marker 6
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1)

if (-not $ReadOnlyRecovery) {
    if ((Test-Path -LiteralPath $localMarker) -or (Test-Path -LiteralPath $repoMarker)) {
        Write-Host "[BLOCKED] device/register probe contract 1.0.1 was already attempted or reserved."
        Write-Host ("[MARKER] " + $localMarker)
        Write-Host "[ACTION] Do not delete the marker for an automatic retry. Use the read-only recovery script instead."
        exit 40
    }
}

$redactionSecrets = @(
    [string]$config.login,
    [string]$config.password,
    [string]$config.client_secret,
    [string]$config.device_code
) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

try {
    Write-Text (Join-Path $out "00_git_state.txt") ("Branch=" + $branch + [Environment]::NewLine + "SHA=" + $sha + [Environment]::NewLine)

    Save-Json (Join-Path $out "01_contract.json") ([ordered]@{
        contract_version="1.0.1"
        approved=$true
        approval_scope="one controlled iretail/device/register call"
        automatic_retry_allowed=$false
        config_update_allowed=$false
        order_send_allowed=$false
        read_only_recovery=[bool]$ReadOnlyRecovery
    }) 5

    $authForm = Join-Path $tmp "auth.form"
    Write-Text $authForm (Encode-Form @{
        username=[string]$config.login
        password=[string]$config.password
        client_id=[string]$config.client_id
        client_secret=[string]$config.client_secret
    })

    $authRaw = Join-Path $tmp "auth.raw"
    $authMeta = Invoke-CurlRequest ($baseUrl + "user/authentication") $authRaw @(
        "--request","POST",
        "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
        "--header","Accept: application/json, */*",
        "--data-binary",("@" + $authForm)
    ) $redactionSecrets $true
    Save-Json (Join-Path $out "02_auth_http.json") $authMeta 5

    $token = ""
    $authStatus = $false
    if (Test-Path -LiteralPath $authRaw) {
        try {
            $authObject = Get-Content -Raw -LiteralPath $authRaw -Encoding UTF8 | ConvertFrom-Json
            $authStatus = [bool]$authObject.status
            if ($null -ne $authObject.result -and $authObject.result.PSObject.Properties.Name -contains "access_token") {
                $token = [string]$authObject.result.access_token
            }
        } catch {}
    }

    Save-Json (Join-Path $out "03_auth_sanitized.json") ([ordered]@{
        http_code=$authMeta.http_code
        api_status=$authStatus
        token_present=(-not [string]::IsNullOrWhiteSpace($token))
    }) 4

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Authentication did not produce access token; register was not attempted"
    }

    $requestSecrets = @($redactionSecrets + @($token)) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique
    $hardSecrets = @(
        [string]$config.password,
        [string]$config.client_secret,
        [string]$token
    ) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

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

        $meta = Invoke-CurlRequest ($baseUrl + $Path) $raw @(
            "--request","POST",
            "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
            "--header","Accept: application/json, */*",
            "--data-binary",("@" + $form)
        ) $requestSecrets $true

        $response = $null
        $parsed = $false
        $apiStatus = $null

        if (Test-Path -LiteralPath $raw) {
            try {
                $response = Get-Content -Raw -LiteralPath $raw -Encoding UTF8 | ConvertFrom-Json
                $parsed = $true
                if ($response.PSObject.Properties.Name -contains "status") { $apiStatus = [bool]$response.status }
                Save-Json (Join-Path $out ($Name + "_sanitized.json")) (Sanitize-Value $response "" $RedactNames) 20
            } catch {
                Save-Json (Join-Path $out ($Name + "_non_json.json")) ([ordered]@{
                    body_saved=$false
                    parse_error=$_.Exception.GetType().Name
                }) 5
            }
        }

        Save-Json (Join-Path $out ($Name + "_http.json")) $meta 5
        return [pscustomobject]@{
            response=$response
            parsed=$parsed
            api_status=$apiStatus
            http_code=$meta.http_code
            curl_exit=$meta.curl_exit
        }
    }

    function Snapshot-State([string]$Prefix,[int[]]$ExtraDeviceIds = @()) {
        $channel = Invoke-ReadOnlyApi ($Prefix + "_channel") "iretail/channel/get" @{channel_id=[string]$config.channel_id} $true
        $devices = Invoke-ReadOnlyApi ($Prefix + "_devices") "iretail/device/get-by-channel-id" @{channel_id=[string]$config.channel_id} $true

        if (-not $devices.parsed -or $devices.api_status -ne $true) {
            throw ("Read-only device list failed at " + $Prefix)
        }

        $ids = @(Get-DeviceIds $devices.response)
        $allIds = @($ids + $ExtraDeviceIds | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
        $checks = @()
        $n = 0

        foreach ($deviceId in ($allIds | Select-Object -First 25)) {
            $n++
            $info = Invoke-ReadOnlyApi ($Prefix + ("_device_{0:D2}_{1}_info" -f $n,$deviceId)) "iretail/device/get-device-info" @{device_id=[string]$deviceId} $true
            $shift = Invoke-ReadOnlyApi ($Prefix + ("_device_{0:D2}_{1}_shift" -f $n,$deviceId)) "iretail/shift/get-current-active-shift" @{device_id=[string]$deviceId} $true

            $shiftId = $null
            $shiftStatusId = $null
            $checkCounter = $null
            $cashierOpeningId = $null

            if ($shift.parsed -and $shift.api_status -eq $true -and $null -ne $shift.response.result) {
                $sr = $shift.response.result
                if ($sr.PSObject.Properties.Name -contains "id") { $shiftId = $sr.id }
                if ($sr.PSObject.Properties.Name -contains "status_id") { $shiftStatusId = $sr.status_id }
                if ($sr.PSObject.Properties.Name -contains "check_counter") { $checkCounter = $sr.check_counter }
                if ($sr.PSObject.Properties.Name -contains "cashier_opening_id") { $cashierOpeningId = $sr.cashier_opening_id }
            }

            $checks += [pscustomobject]@{
                device_id=$deviceId
                device_info_api_status=$info.api_status
                active_shift_api_status=$shift.api_status
                shift_id=$shiftId
                shift_status_id=$shiftStatusId
                check_counter=$checkCounter
                cashier_opening_id=$cashierOpeningId
            }
        }

        $snapshot = [ordered]@{
            prefix=$Prefix
            channel_api_status=$channel.api_status
            devices_api_status=$devices.api_status
            device_ids=$ids
            queried_device_ids=$allIds
            device_checks=$checks
        }
        Save-Json (Join-Path $out ($Prefix + "_snapshot.json")) $snapshot 12
        return [pscustomobject]$snapshot
    }

    if ($ReadOnlyRecovery) {
        $recovery = Snapshot-State "20_recovery"
        Save-Json (Join-Path $out "SUMMARY.json") ([ordered]@{
            audit="i-Retail S3 device/register read-only recovery"
            mode="READ_ONLY_RECOVERY"
            timestamp=$stamp
            git_branch=$branch
            git_sha=$sha
            register_calls=0
            register_retry_allowed=$false
            config_update_allowed=$false
            order_send_allowed=$false
            current_device_ids=$recovery.device_ids
            marker_present=((Test-Path -LiteralPath $localMarker) -or (Test-Path -LiteralPath $repoMarker))
        }) 10
    } else {
        $before = Snapshot-State "10_before"

        Save-Marker "REGISTER_CALL_RESERVED"
        $registerCallCount = 0
        if ($registerCallCount -ne 0) { throw "Internal guard: register call count is not zero" }
        $registerCallCount = 1
        Save-Marker "REGISTER_CALL_STARTED"

        $registerForm = Join-Path $tmp "register.form"
        Write-Text $registerForm (Encode-Form @{
            client_id=[string]$config.client_id
            client_secret=[string]$config.client_secret
            access_token=$token
            device_code=[string]$config.device_code
        })
        $registerRaw = Join-Path $tmp "register.raw"

        # Contract 1.0.1: exactly one request, no redirects and no curl retries.
        $registerMeta = Invoke-CurlRequest ($baseUrl + "iretail/device/register") $registerRaw @(
            "--request","POST",
            "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
            "--header","Accept: application/json, */*",
            "--data-binary",("@" + $registerForm)
        ) $requestSecrets $false
        Save-Json (Join-Path $out "30_register_http.json") $registerMeta 5

        $registerResponse = $null
        $registerParsed = $false
        $registerApiStatus = $null
        $returnedDeviceId = $null
        $returnedTypeSlug = ""
        $returnedChannelId = $null
        $counters = $null
        $returnedShift = $null

        if (Test-Path -LiteralPath $registerRaw) {
            try {
                $registerResponse = Get-Content -Raw -LiteralPath $registerRaw -Encoding UTF8 | ConvertFrom-Json
                $registerParsed = $true
                if ($registerResponse.PSObject.Properties.Name -contains "status") {
                    $registerApiStatus = [bool]$registerResponse.status
                }
                Save-Json (Join-Path $out "31_register_response_sanitized.json") (Sanitize-Value $registerResponse "" $true) 20

                if ($null -ne $registerResponse.result) {
                    $rr = $registerResponse.result
                    if ($rr.PSObject.Properties.Name -contains "device_id") { $returnedDeviceId = $rr.device_id }
                    if ($rr.PSObject.Properties.Name -contains "type_slug") { $returnedTypeSlug = [string]$rr.type_slug }
                    if ($rr.PSObject.Properties.Name -contains "channel_id") { $returnedChannelId = $rr.channel_id }
                    if ($rr.PSObject.Properties.Name -contains "counters") { $counters = $rr.counters }
                    if ($rr.PSObject.Properties.Name -contains "shift") { $returnedShift = $rr.shift }
                }
            } catch {
                Save-Json (Join-Path $out "31_register_response_non_json.json") ([ordered]@{
                    body_saved=$false
                    parse_error=$_.Exception.GetType().Name
                }) 5
            }
        }

        $outcome = "REGISTER_RESULT_UNCERTAIN"
        if ($registerMeta.curl_exit -eq 0 -and $registerParsed) {
            if ($registerApiStatus -eq $true) {
                $outcome = "REGISTER_RESPONSE_SUCCESS"
            } else {
                $outcome = "REGISTER_RESPONSE_REJECTED"
            }
        }

        Save-Marker "REGISTER_CALL_COMPLETED" $outcome $returnedDeviceId $returnedTypeSlug

        $extraIds = @()
        $returnedDeviceIdInt = 0
        if ([int]::TryParse([string]$returnedDeviceId,[ref]$returnedDeviceIdInt) -and $returnedDeviceIdInt -gt 0) {
            $extraIds += $returnedDeviceIdInt
        }

        $after = Snapshot-State "40_after" $extraIds

        $beforeIds = @($before.device_ids)
        $afterIds = @($after.device_ids)
        $newIds = @($afterIds | Where-Object { $beforeIds -notcontains $_ })

        Save-Json (Join-Path $out "SUMMARY.json") ([ordered]@{
            audit="i-Retail S3 controlled device/register probe"
            mode="CONTROLLED_REGISTER_PROBE"
            contract_version="1.0.1"
            timestamp=$stamp
            git_branch=$branch
            git_sha=$sha
            register_calls=$registerCallCount
            register_retry_allowed=$false
            config_update_allowed=$false
            order_send_allowed=$false
            register_outcome=$outcome
            register_http_code=$registerMeta.http_code
            register_curl_exit=$registerMeta.curl_exit
            register_api_status=$registerApiStatus
            returned_device_id=$returnedDeviceId
            returned_type_slug=$returnedTypeSlug
            returned_channel_id=$returnedChannelId
            returned_counters=(Sanitize-Value $counters)
            returned_shift=(Sanitize-Value $returnedShift)
            configured_device_id=[string]$config.device_id
            device_ids_before=$beforeIds
            device_ids_after=$afterIds
            new_device_ids=$newIds
            returned_device_is_new=($null -ne $returnedDeviceId -and ($beforeIds -notcontains $returnedDeviceIdInt))
            returned_type_is_cashbox=($returnedTypeSlug -eq "workplace_cashier" -or $returnedTypeSlug -eq "self_service_terminal")
            automatic_device_binding=$false
        }) 16
    }

    $unsafe = @()
    Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object { $_.Extension -match "^\.(txt|json)$" } | ForEach-Object {
        $content = Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
        foreach ($secret in $hardSecrets) {
            if ($null -ne $content -and -not [string]::IsNullOrEmpty($secret) -and $content.Contains($secret)) {
                $unsafe += $_.FullName
                break
            }
        }
    }
    if ($unsafe.Count -gt 0) {
        throw ("Safety scan failed: credential/token value found in report: " + (($unsafe | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object -Unique) -join ","))
    }

    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

    Write-Host "[SUCCESS] S3 device/register report created."
    Write-Host ("[REPORT] " + $zip)
    if ($ReadOnlyRecovery) {
        Write-Host "[MODE] READ_ONLY_RECOVERY"
    } else {
        $summaryNow = Get-Content -Raw -LiteralPath (Join-Path $out "SUMMARY.json") -Encoding UTF8 | ConvertFrom-Json
        Write-Host ("[REGISTER OUTCOME] " + $summaryNow.register_outcome)
        Write-Host ("[RETURNED DEVICE] " + [string]$summaryNow.returned_device_id)
        Write-Host ("[RETURNED TYPE] " + [string]$summaryNow.returned_type_slug)
        Write-Host ("[NEW DEVICE IDS] " + ((@($summaryNow.new_device_ids)) -join ","))
    }
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
