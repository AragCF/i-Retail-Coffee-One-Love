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
$root = Join-Path $RepoRoot "test_reports\s3_live_reference"
$out = Join-Path $root ("S3_LIVE_REF_" + $stamp)
$zip = $out + ".zip"
$tmp = Join-Path $env:TEMP ("iretail_s3ref_" + $stamp + "_" + $PID)

New-Item -ItemType Directory -Path $out -Force | Out-Null
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Text([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
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

function Is-SensitiveKey([string]$Key) {
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    return $Key -match '(?i)^(password|client_secret|secret|access_token|refresh_token|token|pin|device_code|external_code|code|phone|email|first_name|last_name|patronymic|full_name|username)$'
}

function Sanitize-Value($Value,[string]$Key = "") {
    if (Is-SensitiveKey $Key) {
        if ($null -eq $Value) { return $null }
        return "[REDACTED]"
    }

    if ($null -eq $Value) { return $null }

    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($k in $Value.Keys) {
            $result[[string]$k] = Sanitize-Value $Value[$k] ([string]$k)
        }
        return [pscustomobject]$result
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) { $items += ,(Sanitize-Value $item "") }
        return $items
    }

    if ($Value -is [pscustomobject] -or $Value.PSObject.Properties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($prop in $Value.PSObject.Properties) {
            $result[$prop.Name] = Sanitize-Value $prop.Value $prop.Name
        }
        return [pscustomobject]$result
    }

    return $Value
}

function Save-Json([string]$Path,$Value,[int]$Depth = 12) {
    Write-Text $Path (($Value | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine)
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1)

$baseSecrets = @(
    [string]$config.login,
    [string]$config.password,
    [string]$config.client_secret
) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

try {
    Write-Text (Join-Path $out "00_git_state.txt") ("Branch=" + $branch + [Environment]::NewLine + "SHA=" + $sha + [Environment]::NewLine)

    $safeConfig = [ordered]@{
        base_url=[string]$config.base_url
        client_id=[string]$config.client_id
        profile_id=[string]$config.profile_id
        channel_id=[string]$config.channel_id
        device_id=[string]$config.device_id
        login_present=(-not [string]::IsNullOrWhiteSpace([string]$config.login))
        password_present=(-not [string]::IsNullOrWhiteSpace([string]$config.password))
        client_secret_present=(-not [string]::IsNullOrWhiteSpace([string]$config.client_secret))
    }
    Save-Json (Join-Path $out "01_config_sanitized.json") $safeConfig 4

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
    $authParse = ""
    if (Test-Path -LiteralPath $authRaw) {
        try {
            $authObject = Get-Content -Raw -LiteralPath $authRaw -Encoding UTF8 | ConvertFrom-Json
            $authStatus = [bool]$authObject.status
            if ($null -ne $authObject.result -and $null -ne $authObject.result.access_token) {
                $token = [string]$authObject.result.access_token
            }
        } catch {
            $authParse = $_.Exception.GetType().Name
        }
    }

    Save-Json (Join-Path $out "03_auth_sanitized.json") ([ordered]@{
        http_code=$authMeta.http_code
        curl_exit=$authMeta.curl_exit
        api_status=$authStatus
        token_present=(-not [string]::IsNullOrWhiteSpace($token))
        parse_error=$authParse
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

    $requests = @(
        [pscustomobject]@{name="reference_order_status"; path="reference/get-order-status"; fields=@{}},
        [pscustomobject]@{name="reference_order_statuses"; path="reference/get-order-statuses"; fields=@{}},
        [pscustomobject]@{name="reference_order_payment_status"; path="reference/get-order-payment-status"; fields=@{}},
        [pscustomobject]@{name="reference_operation_statuses"; path="reference/get-statuses-operation"; fields=@{}},
        [pscustomobject]@{name="reference_operation_types"; path="reference/get-types-operation"; fields=@{}},
        [pscustomobject]@{name="reference_shift_statuses"; path="reference/get-statuses-shift"; fields=@{}},
        [pscustomobject]@{name="reference_currencies"; path="reference/get-currencies"; fields=@{}},
        [pscustomobject]@{name="reference_offer_types"; path="reference/get-types-offer"; fields=@{}},
        [pscustomobject]@{name="service_in"; path="service-in/get-service-in"; fields=@{}},
        [pscustomobject]@{name="service_in_list"; path="service-in/get-service-in-list"; fields=@{}},
        [pscustomobject]@{name="service_in_types"; path="service-in/get-service-in-types"; fields=@{}},
        [pscustomobject]@{name="active_shift"; path="iretail/shift/get-current-active-shift"; fields=@{device_id=[string]$config.device_id}},
        [pscustomobject]@{name="employees_by_channel"; path="iretail/employee/get-by-channel"; fields=@{channel_id=[string]$config.channel_id}},
        [pscustomobject]@{name="device_info"; path="iretail/device/get-device-info"; fields=@{device_id=[string]$config.device_id}},
        [pscustomobject]@{name="taxes"; path="iretail/tax/get"; fields=@{profile_id=[string]$config.profile_id;page_size="100";page_number="0"}}
    )

    $results = @()
    $index = 10

    foreach ($request in $requests) {
        $fields = @{}
        foreach ($key in $common.Keys) { $fields[$key] = $common[$key] }
        foreach ($key in $request.fields.Keys) { $fields[$key] = $request.fields[$key] }

        $formPath = Join-Path $tmp ($request.name + ".form")
        Write-Text $formPath (Encode-Form $fields)
        $rawPath = Join-Path $tmp ($request.name + ".raw")

        $meta = Invoke-CurlToFile ($baseUrl + $request.path) $rawPath @(
            "--request","POST",
            "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
            "--header","Accept: application/json, */*",
            "--data-binary",("@" + $formPath)
        ) $allSecrets

        $prefix = "{0:D2}_{1}" -f $index,$request.name
        Save-Json (Join-Path $out ($prefix + "_http.json")) $meta 5

        $parsed = $false
        $parseError = ""
        $safePayload = $null
        $bodySize = 0

        if (Test-Path -LiteralPath $rawPath) {
            $bodySize = (Get-Item -LiteralPath $rawPath).Length
            try {
                $obj = Get-Content -Raw -LiteralPath $rawPath -Encoding UTF8 | ConvertFrom-Json
                $safePayload = Sanitize-Value $obj ""
                Save-Json (Join-Path $out ($prefix + "_sanitized.json")) $safePayload 20
                $parsed = $true
            } catch {
                $parseError = $_.Exception.GetType().Name
                Save-Json (Join-Path $out ($prefix + "_non_json.json")) ([ordered]@{
                    body_saved=$false
                    body_size=$bodySize
                    parse_error=$parseError
                }) 4
            }
        }

        $results += [pscustomobject]@{
            name=$request.name
            path=$request.path
            http_code=$meta.http_code
            curl_exit=$meta.curl_exit
            json_parsed=$parsed
            body_size=$bodySize
            parse_error=$parseError
        }

        $index++
    }

    Save-Json (Join-Path $out "90_results.json") $results 8

    $summary = [ordered]@{
        audit="i-Retail S3 live read-only reference audit"
        timestamp=$stamp
        git_branch=$branch
        git_sha=$sha
        auth_http_code=$authMeta.http_code
        auth_api_status=$authStatus
        auth_token_present=(-not [string]::IsNullOrWhiteSpace($token))
        requested_endpoints=$requests.Count
        http_2xx=@($results | Where-Object { [int]$_.http_code -ge 200 -and [int]$_.http_code -lt 300 }).Count
        json_parsed=@($results | Where-Object { $_.json_parsed }).Count
        network_actions="authentication + semantically read-only metadata POSTs only"
        forbidden_calls=@(
            "iretail/order/synchronize",
            "iretail/device/register",
            "iretail/shift/open-shift",
            "iretail/shift/close-shift",
            "iretail/employee/authorize",
            "iretail/payment-in/create"
        )
        order_send_allowed=$false
    }
    Save-Json (Join-Path $out "SUMMARY.json") $summary 8

    $summaryLines = @(
        "i-Retail S3 live read-only reference audit",
        "Timestamp=" + $stamp,
        "GitBranch=" + $branch,
        "GitSHA=" + $sha,
        "AuthHTTP=" + $authMeta.http_code,
        "AuthApiStatus=" + $authStatus,
        "Endpoints=" + $requests.Count,
        "HTTP2xx=" + $summary.http_2xx,
        "JsonParsed=" + $summary.json_parsed,
        "OrderSendAllowed=NO"
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

    Write-Host "[SUCCESS] S3 live read-only reference audit completed."
    Write-Host ("[REPORT] " + $zip)
    Write-Host ("[AUTH] HTTP=" + $authMeta.http_code + " status=" + $authStatus)
    Write-Host ("[ENDPOINTS] " + $summary.http_2xx + "/" + $requests.Count + " HTTP 2xx")
    Write-Host ("[JSON] " + $summary.json_parsed + "/" + $requests.Count + " parsed")
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
