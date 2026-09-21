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
$root = Join-Path $RepoRoot "test_reports\s3_admin_device_inventory"
$out = Join-Path $root ("S3_ADMIN_DEVICE_INVENTORY_" + $stamp)
$zip = $out + ".zip"
$tmp = Join-Path $env:TEMP ("iretail_s3admininv_" + $stamp + "_" + $PID)

New-Item -ItemType Directory -Path $out -Force | Out-Null
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
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

function Invoke-CurlToFile([string]$Url,[string]$Output,[string[]]$Extra,[string[]]$Secrets) {
    $err = Join-Path $tmp ("curl_" + [Guid]::NewGuid().ToString("N") + ".err")
    $fmt = "http_code=%{http_code}|content_type=%{content_type}|time_total=%{time_total}|remote_ip=%{remote_ip}|url_effective=%{url_effective}"
    $args = @("--silent","--show-error","--location","--connect-timeout","15","--max-time","45","--retry","0","--output",$Output,"--write-out",$fmt)
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
    return ($Key -match '(?i)(password$|secret$|token$|pin$|device_code$|external_code$|^code$|code_device$|phone$|email$|first_name$|last_name$|patronymic$|full_name$|username$|address$|^inn$|serial$|serial_number$|fn_serial$|kkt_serial$|^mac$|^ip$|url_ofd$|account_id$|user_id$|offline_shop_id$)')
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
        foreach ($container in @("rows","items","data")) {
            if ($result.PSObject.Properties.Name -contains $container) {
                return @($result.$container)
            }
        }
        return @($result)
    }

    return @()
}

function Get-NestedValue($Object,[string[]]$Paths) {
    if ($null -eq $Object) { return $null }

    foreach ($path in $Paths) {
        $current = $Object
        $ok = $true
        foreach ($part in ($path -split '\.')) {
            if ($null -eq $current -or $current.PSObject.Properties.Name -notcontains $part) {
                $ok = $false
                break
            }
            $current = $current.$part
        }
        if ($ok -and $null -ne $current) { return $current }
    }
    return $null
}

function Get-DeviceId($Object) {
    if ($null -eq $Object) { return $null }
    foreach ($key in @("id","device_id")) {
        if ($Object.PSObject.Properties.Name -contains $key) {
            $value = 0
            if ([int]::TryParse([string]$Object.$key,[ref]$value) -and $value -gt 0) {
                return $value
            }
        }
    }
    return $null
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1)

$redactionSecrets = @(
    [string]$config.login,
    [string]$config.password,
    [string]$config.client_secret,
    [string]$config.device_code
) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

try {
    Write-Text (Join-Path $out "00_git_state.txt") ("Branch=" + $branch + [Environment]::NewLine + "SHA=" + $sha + [Environment]::NewLine)

    Save-Json (Join-Path $out "01_scope.json") ([ordered]@{
        audit="S3 admin device inventory"
        mode="READ_ONLY"
        profile_id=[string]$config.profile_id
        channel_id=[string]$config.channel_id
        configured_device_id=[string]$config.device_id
        mutating_calls=0
        device_create_allowed=$false
        device_update_allowed=$false
        repeat_activation_allowed=$false
        device_remove_allowed=$false
        order_send_allowed=$false
    }) 6

    $authForm = Join-Path $tmp "auth.form"
    Write-Text $authForm (Encode-Form @{
        username=[string]$config.login
        password=[string]$config.password
        client_id=[string]$config.client_id
        client_secret=[string]$config.client_secret
    })

    $authRaw = Join-Path $tmp "auth.raw"
    $authMeta = Invoke-CurlToFile ($baseUrl + "user/authentication") $authRaw @(
        "--request","POST",
        "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
        "--header","Accept: application/json, */*",
        "--data-binary",("@" + $authForm)
    ) $redactionSecrets

    Save-Json (Join-Path $out "02_auth_http.json") $authMeta 5

    $token = ""
    $authStatus = $false
    if (Test-Path -LiteralPath $authRaw) {
        try {
            $auth = Get-Content -Raw -LiteralPath $authRaw -Encoding UTF8 | ConvertFrom-Json
            $authStatus = [bool]$auth.status
            if ($null -ne $auth.result -and $auth.result.PSObject.Properties.Name -contains "access_token") {
                $token = [string]$auth.result.access_token
            }
        } catch {}
    }

    Save-Json (Join-Path $out "03_auth_sanitized.json") ([ordered]@{
        http_code=$authMeta.http_code
        api_status=$authStatus
        token_present=(-not [string]::IsNullOrWhiteSpace($token))
    }) 4

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Authentication did not produce access token"
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

        $meta = Invoke-CurlToFile ($baseUrl + $Path) $raw @(
            "--request","POST",
            "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
            "--header","Accept: application/json, */*",
            "--data-binary",("@" + $form)
        ) $requestSecrets

        Save-Json (Join-Path $out ($Name + "_http.json")) $meta 5

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

        return [pscustomobject]@{
            name=$Name
            path=$Path
            meta=$meta
            response=$response
            parsed=$parsed
            api_status=$apiStatus
        }
    }

    $results = @()

    $count = Invoke-ReadOnlyApi "10_admin_count_channel" "admin/device/get-count-device-in-channel" @{
        channel_id=[string]$config.channel_id
    } $false
    $results += $count

    $find = Invoke-ReadOnlyApi "11_admin_find_profile" "admin/device/find" @{
        profile_id=[string]$config.profile_id
        page_size="100"
        page_number="1"
        alive="1"
    } $true
    $results += $find

    $involved = Invoke-ReadOnlyApi "12_admin_devices_in_orders" "admin/device/get-list-device-involved-in-orders" @{
        profile_id=[string]$config.profile_id
    } $true
    $results += $involved

    $items = @(Get-ResultItems $find.response)
    $ids = @()
    foreach ($item in $items) {
        $id = Get-DeviceId $item
        if ($null -ne $id) { $ids += $id }
    }
    $ids = @($ids | Sort-Object -Unique)

    $configuredId = 0
    [void][int]::TryParse([string]$config.device_id,[ref]$configuredId)
    $candidateIds = @($ids)
    if ($configuredId -gt 0 -and $candidateIds -notcontains $configuredId) {
        $candidateIds += $configuredId
    }
    if ($candidateIds -notcontains 3476) { $candidateIds += 3476 }
    $candidateIds = @($candidateIds | Sort-Object -Unique | Select-Object -First 60)

    $inventory = @()

    foreach ($deviceId in $candidateIds) {
        $info = Invoke-ReadOnlyApi ("20_admin_device_" + $deviceId) "admin/device/get-device-info" @{
            device_id=[string]$deviceId
        } $true
        $results += $info

        $obj = $null
        if ($info.parsed -and $null -ne $info.response -and $info.response.PSObject.Properties.Name -contains "result") {
            $obj = $info.response.result
        }

        $typeSlug = Get-NestedValue $obj @("type_slug","type.slug","device_type.slug")
        $typeId = Get-NestedValue $obj @("type_id","type.id","device_type.id")
        $channelId = Get-NestedValue $obj @("channel_id","channel.id")
        $statusSlug = Get-NestedValue $obj @("status_slug","status.slug")
        $statusId = Get-NestedValue $obj @("status_id","status.id")
        $conditionSlug = Get-NestedValue $obj @("condition_slug","condition.slug")
        $conditionId = Get-NestedValue $obj @("condition_id","condition.id")
        $ownOrders = Get-NestedValue $obj @("own_orders")
        $fiscalMode = Get-NestedValue $obj @("fiscal_mode")
        $code = [string](Get-NestedValue $obj @("code"))
        $externalCode = [string](Get-NestedValue $obj @("external_code"))
        $innerId = Get-NestedValue $obj @("inner_id","device_inner_id")
        $alive = Get-NestedValue $obj @("alive","is_alive")
        $removed = Get-NestedValue $obj @("removed","is_removed")

        $inventory += [pscustomobject]@{
            device_id=$deviceId
            api_status=$info.api_status
            found=($null -ne $obj)
            type_slug=$typeSlug
            type_id=$typeId
            channel_id=$channelId
            status_slug=$statusSlug
            status_id=$statusId
            condition_slug=$conditionSlug
            condition_id=$conditionId
            own_orders=$ownOrders
            fiscal_mode=$fiscalMode
            inner_id=$innerId
            alive=$alive
            removed=$removed
            code_present=(-not [string]::IsNullOrWhiteSpace($code))
            code_length=$code.Length
            external_code_present=(-not [string]::IsNullOrWhiteSpace($externalCode))
            external_code_length=$externalCode.Length
            is_configured_device=($deviceId -eq $configuredId)
            is_known_coffee_machine=($deviceId -eq 3476)
            is_cashbox_type=([string]$typeSlug -eq "workplace_cashier" -or [string]$typeSlug -eq "self_service_terminal")
        }
    }

    Save-Json (Join-Path $out "80_inventory.json") $inventory 12

    $cashboxes = @($inventory | Where-Object { $_.is_cashbox_type -eq $true })
    $configuredRow = @($inventory | Where-Object { $_.is_configured_device -eq $true } | Select-Object -First 1)
    $coffeeRow = @($inventory | Where-Object { $_.is_known_coffee_machine -eq $true } | Select-Object -First 1)

    $countValue = $null
    if ($count.parsed -and $null -ne $count.response -and $count.response.PSObject.Properties.Name -contains "result") {
        $countValue = $count.response.result
    }

    $involvedIds = @()
    foreach ($item in (Get-ResultItems $involved.response)) {
        $id = Get-DeviceId $item
        if ($null -ne $id) { $involvedIds += $id }
    }
    $involvedIds = @($involvedIds | Sort-Object -Unique)

    $summary = [ordered]@{
        audit="i-Retail S3 admin device inventory"
        timestamp=$stamp
        git_branch=$branch
        git_sha=$sha
        profile_id=[string]$config.profile_id
        channel_id=[string]$config.channel_id
        configured_device_id=$configuredId
        network_actions="authentication + read-only admin device find/count/info/list POSTs only"
        mutating_calls=0
        device_create_allowed=$false
        device_update_allowed=$false
        repeat_activation_allowed=$false
        device_remove_allowed=$false
        order_send_allowed=$false
        admin_count_in_channel=$countValue
        admin_find_device_ids=$ids
        queried_device_ids=$candidateIds
        devices_involved_in_orders=$involvedIds
        cashbox_device_ids=@($cashboxes | ForEach-Object { $_.device_id })
        cashbox_types=@($cashboxes | ForEach-Object { $_.type_slug })
        cashbox_count=$cashboxes.Count
        configured_device_found=($configuredRow.Count -gt 0 -and $configuredRow[0].found -eq $true)
        configured_device_type=if($configuredRow.Count -gt 0){$configuredRow[0].type_slug}else{$null}
        known_coffee_machine_found=($coffeeRow.Count -gt 0 -and $coffeeRow[0].found -eq $true)
        known_coffee_machine_type=if($coffeeRow.Count -gt 0){$coffeeRow[0].type_slug}else{$null}
        inventory=$inventory
    }

    Save-Json (Join-Path $out "SUMMARY.json") $summary 20

    $resultRows = @($results | ForEach-Object {
        [pscustomobject]@{
            name=$_.name
            path=$_.path
            http_code=$_.meta.http_code
            curl_exit=$_.meta.curl_exit
            json_parsed=$_.parsed
            api_status=$_.api_status
        }
    })
    Save-Json (Join-Path $out "90_results.json") $resultRows 10

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
        $names = @($unsafe | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object -Unique)
        throw ("Safety scan failed: credential/token found in report: " + ($names -join ","))
    }

    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

    Write-Host "[SUCCESS] S3 admin-device inventory audit completed."
    Write-Host ("[REPORT] " + $zip)
    Write-Host ("[ADMIN COUNT CHANNEL] " + [string]$countValue)
    Write-Host ("[ADMIN FIND IDS] " + ($ids -join ","))
    Write-Host ("[CASHBOX IDS] " + ((@($cashboxes | ForEach-Object { $_.device_id })) -join ","))
    Write-Host ("[CASHBOX TYPES] " + ((@($cashboxes | ForEach-Object { $_.type_slug })) -join ","))
    Write-Host ("[CONFIGURED " + $configuredId + "] found=" + $summary.configured_device_found + " type=" + [string]$summary.configured_device_type)
    Write-Host ("[COFFEE 3476] found=" + $summary.known_coffee_machine_found + " type=" + [string]$summary.known_coffee_machine_type)
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
