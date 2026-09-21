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
$sourceDeviceId = 3476

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$root = Join-Path $RepoRoot "test_reports\s3_external_register"
$prefix = "S3_EXTERNAL_REGISTER_PROBE_"
if ($ReadOnlyRecovery) { $prefix = "S3_EXTERNAL_REGISTER_RECOVERY_" }
$out = Join-Path $root ($prefix + $stamp)
$zip = $out + ".zip"
$tmp = Join-Path $env:TEMP ("iretail_s3extreg_" + $stamp + "_" + $PID)

$localAppData = [Environment]::GetFolderPath("LocalApplicationData")
if ([string]::IsNullOrWhiteSpace($localAppData)) { throw "LocalApplicationData is unavailable" }
$markerDir = Join-Path $localAppData "CoffeeOneLove\iRetail\S3"
$localMarker = Join-Path $markerDir "external_system_register_probe_contract_1_0_0.json"
$repoMarker = Join-Path $root "EXTERNAL_SYSTEM_REGISTER_PROBE_1_0_0.marker.json"

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
            if ([int]::TryParse([string]$item.id,[ref]$value) -and $value -gt 0) {
                $ids += $value
            }
        }
    }
    return @($ids | Sort-Object -Unique)
}

function Save-Marker(
    [string]$Status,
    [string]$Outcome = "",
    $ReturnedDeviceId = $null,
    [string]$ReturnedTypeSlug = ""
) {
    $marker = [ordered]@{
        contract_version="1.0.0"
        method="iretail/device/register-external-system"
        source_device_id=$sourceDeviceId
        status=$Status
        outcome=$Outcome
        timestamp=(Get-Date).ToString("o")
        git_branch=$branch
        git_sha=$sha
        returned_device_id=$ReturnedDeviceId
        returned_type_slug=$ReturnedTypeSlug
        automatic_retry_allowed=$false
    }

    Save-Json $repoMarker $marker 8
    Save-Json $localMarker $marker 8
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1)

if (-not $ReadOnlyRecovery) {
    if ((Test-Path -LiteralPath $localMarker) -or (Test-Path -LiteralPath $repoMarker)) {
        Write-Host "[BLOCKED] register-external-system probe was already attempted or reserved."
        Write-Host ("[MARKER] " + $localMarker)
        Write-Host "[ACTION] Do not delete markers for an automatic retry. Use the read-only recovery script."
        exit 40
    }
}

$baseRedactionSecrets = @(
    [string]$config.login,
    [string]$config.password,
    [string]$config.client_secret,
    [string]$config.device_code
) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

try {
    Write-Text (Join-Path $out "00_git_state.txt") ("Branch=" + $branch + [Environment]::NewLine + "SHA=" + $sha + [Environment]::NewLine)

    Save-Json (Join-Path $out "01_contract.json") ([ordered]@{
        contract_version="1.0.0"
        approved=$true
        approval_scope="one controlled iretail/device/register-external-system call"
        source_device_id=$sourceDeviceId
        automatic_retry_allowed=$false
        config_update_allowed=$false
        order_send_allowed=$false
        read_only_recovery=[bool]$ReadOnlyRecovery
    }) 8

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
    ) $baseRedactionSecrets $true

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
        throw "Authentication did not produce access token; external register was not attempted"
    }

    $requestSecrets = @($baseRedactionSecrets + @($token)) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

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
                if ($response.PSObject.Properties.Name -contains "status") {
                    $apiStatus = [bool]$response.status
                }
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
        $devices = Invoke-ReadOnlyApi ($Prefix + "_devices") "iretail/device/get-by-channel-id" @{
            channel_id=[string]$config.channel_id
        } $true

        if (-not $devices.parsed -or $devices.api_status -ne $true) {
            throw ("Read-only device list failed at " + $Prefix)
        }

        $ids = @(Get-DeviceIds $devices.response)
        $allIds = @($ids + $ExtraDeviceIds | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
        $checks = @()

        foreach ($deviceId in ($allIds | Select-Object -First 25)) {
            $info = Invoke-ReadOnlyApi ($Prefix + "_device_" + $deviceId + "_info") "iretail/device/get-device-info" @{
                device_id=[string]$deviceId
            } $true

            $shift = Invoke-ReadOnlyApi ($Prefix + "_device_" + $deviceId + "_shift") "iretail/shift/get-current-active-shift" @{
                device_id=[string]$deviceId
            } $true

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
            audit="i-Retail S3 external-system register read-only recovery"
            mode="READ_ONLY_RECOVERY"
            contract_version="1.0.0"
            timestamp=$stamp
            git_branch=$branch
            git_sha=$sha
            external_register_calls=0
            external_register_retry_allowed=$false
            config_update_allowed=$false
            order_send_allowed=$false
            current_device_ids=$recovery.device_ids
            marker_present=((Test-Path -LiteralPath $localMarker) -or (Test-Path -LiteralPath $repoMarker))
        }) 10
    } else {
        $before = Snapshot-State "10_before"

        if ($before.device_ids -notcontains $sourceDeviceId) {
            throw ("Source coffee machine device not found in channel: " + $sourceDeviceId)
        }

        $sourceInfo = Invoke-ReadOnlyApi "20_source_device_info" "iretail/device/get-device-info" @{
            device_id=[string]$sourceDeviceId
        } $true

        if (-not $sourceInfo.parsed -or $sourceInfo.api_status -ne $true -or $null -eq $sourceInfo.response.result) {
            throw "Could not read source device info; external register was not attempted"
        }

        $sourceObject = $sourceInfo.response.result
        if ($sourceObject.PSObject.Properties.Name -notcontains "external_code") {
            throw "Source device has no external_code field; external register was not attempted"
        }

        $externalCode = [string]$sourceObject.external_code
        if ([string]::IsNullOrWhiteSpace($externalCode)) {
            throw "Source device external_code is empty; external register was not attempted"
        }

        Save-Json (Join-Path $out "21_external_code_evidence.json") ([ordered]@{
            source_device_id=$sourceDeviceId
            external_code_present=$true
            external_code_length=$externalCode.Length
            external_code_value_saved=$false
        }) 5

        $externalSecrets = @($requestSecrets + @($externalCode)) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

        Save-Marker "EXTERNAL_REGISTER_CALL_RESERVED"

        $externalRegisterCallCount = 0
        if ($externalRegisterCallCount -ne 0) { throw "Internal guard: external register call count is not zero" }
        $externalRegisterCallCount = 1
        Save-Marker "EXTERNAL_REGISTER_CALL_STARTED"

        $registerForm = Join-Path $tmp "external_register.form"
        Write-Text $registerForm (Encode-Form @{
            client_id=[string]$config.client_id
            client_secret=[string]$config.client_secret
            access_token=$token
            external_code=$externalCode
        })

        $registerRaw = Join-Path $tmp "external_register.raw"

        # Contract 1.0.0: exactly one request, no redirects and no curl retries.
        $registerMeta = Invoke-CurlRequest ($baseUrl + "iretail/device/register-external-system") $registerRaw @(
            "--request","POST",
            "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
            "--header","Accept: application/json, */*",
            "--data-binary",("@" + $registerForm)
        ) $externalSecrets $false

        Save-Json (Join-Path $out "30_external_register_http.json") $registerMeta 5

        $registerResponse = $null
        $registerParsed = $false
        $registerApiStatus = $null
        $returnedDeviceId = $null
        $returnedTypeSlug = ""
        $returnedChannelId = $null
        $returnedDeviceInnerId = $null
        $returnedCounters = $null

        if (Test-Path -LiteralPath $registerRaw) {
            try {
                $registerResponse = Get-Content -Raw -LiteralPath $registerRaw -Encoding UTF8 | ConvertFrom-Json
                $registerParsed = $true

                if ($registerResponse.PSObject.Properties.Name -contains "status") {
                    $registerApiStatus = [bool]$registerResponse.status
                }

                Save-Json (Join-Path $out "31_external_register_response_sanitized.json") (Sanitize-Value $registerResponse "" $true) 20

                $rr = $registerResponse
                if ($registerResponse.PSObject.Properties.Name -contains "result") {
                    $rr = $registerResponse.result
                }

                if ($null -ne $rr) {
                    if ($rr.PSObject.Properties.Name -contains "device_id") { $returnedDeviceId = $rr.device_id }
                    if ($rr.PSObject.Properties.Name -contains "type_slug") { $returnedTypeSlug = [string]$rr.type_slug }
                    if ($rr.PSObject.Properties.Name -contains "channel_id") { $returnedChannelId = $rr.channel_id }
                    if ($rr.PSObject.Properties.Name -contains "device_inner_id") { $returnedDeviceInnerId = $rr.device_inner_id }
                    if ($rr.PSObject.Properties.Name -contains "counters") { $returnedCounters = $rr.counters }
                }
            } catch {
                Save-Json (Join-Path $out "31_external_register_response_non_json.json") ([ordered]@{
                    body_saved=$false
                    parse_error=$_.Exception.GetType().Name
                }) 5
            }
        }

        $outcome = "EXTERNAL_REGISTER_RESULT_UNCERTAIN"
        if ($registerMeta.curl_exit -eq 0 -and $registerParsed) {
            if ($registerApiStatus -eq $true) {
                $outcome = "EXTERNAL_REGISTER_RESPONSE_SUCCESS"
            } elseif ($registerApiStatus -eq $false) {
                $outcome = "EXTERNAL_REGISTER_RESPONSE_REJECTED"
            } elseif ($null -ne $returnedDeviceId) {
                $outcome = "EXTERNAL_REGISTER_RESPONSE_SUCCESS_NO_STATUS_WRAPPER"
            }
        }

        Save-Marker "EXTERNAL_REGISTER_CALL_COMPLETED" $outcome $returnedDeviceId $returnedTypeSlug

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
            audit="i-Retail S3 controlled register-external-system probe"
            mode="CONTROLLED_EXTERNAL_REGISTER_PROBE"
            contract_version="1.0.0"
            timestamp=$stamp
            git_branch=$branch
            git_sha=$sha
            source_device_id=$sourceDeviceId
            source_external_code_present=$true
            source_external_code_length=$externalCode.Length
            source_external_code_saved=$false
            external_register_calls=$externalRegisterCallCount
            external_register_retry_allowed=$false
            config_update_allowed=$false
            order_send_allowed=$false
            external_register_outcome=$outcome
            register_http_code=$registerMeta.http_code
            register_curl_exit=$registerMeta.curl_exit
            register_api_status=$registerApiStatus
            returned_device_id=$returnedDeviceId
            returned_type_slug=$returnedTypeSlug
            returned_channel_id=$returnedChannelId
            returned_device_inner_id=$returnedDeviceInnerId
            returned_counters=(Sanitize-Value $returnedCounters)
            device_ids_before=$beforeIds
            device_ids_after=$afterIds
            new_device_ids=$newIds
            returned_device_is_new=($null -ne $returnedDeviceId -and ($beforeIds -notcontains $returnedDeviceIdInt))
            returned_type_is_cashbox=($returnedTypeSlug -eq "workplace_cashier" -or $returnedTypeSlug -eq "self_service_terminal")
            automatic_device_binding=$false
        }) 16

        $unsafe = @()
        Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object { $_.Extension -match "^\.(txt|json)$" } | ForEach-Object {
            $content = Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
            foreach ($secret in $externalSecrets) {
                if ($null -ne $content -and -not [string]::IsNullOrEmpty($secret) -and $content.Contains($secret)) {
                    $unsafe += $_.FullName
                    break
                }
            }
        }

        if ($unsafe.Count -gt 0) {
            $names = @($unsafe | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object -Unique)
            throw ("Safety scan failed: credential/token/external_code value found in report: " + ($names -join ","))
        }
    }

    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

    Write-Host "[SUCCESS] S3 register-external-system report created."
    Write-Host ("[REPORT] " + $zip)

    if ($ReadOnlyRecovery) {
        Write-Host "[MODE] READ_ONLY_RECOVERY"
    } else {
        $summaryNow = Get-Content -Raw -LiteralPath (Join-Path $out "SUMMARY.json") -Encoding UTF8 | ConvertFrom-Json
        Write-Host ("[REGISTER OUTCOME] " + [string]$summaryNow.external_register_outcome)
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
