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
$root = Join-Path $RepoRoot "test_reports\s3_admin_auth_permission"
$out = Join-Path $root ("S3_ADMIN_AUTH_PERMISSION_" + $stamp)
$zip = $out + ".zip"
$tmp = Join-Path $env:TEMP ("iretail_s3adminauth_" + $stamp + "_" + $PID)

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

function Is-SensitiveKey([string]$Key,[bool]$RedactNames = $false) {
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    if ($RedactNames -and $Key -match '(?i)^(name|title|description)$') { return $true }

    return ($Key -match '(?i)(password$|secret$|token$|refresh_token$|pin$|device_code$|external_code$|^code$|code_device$|phone$|email$|first_name$|last_name$|patronymic$|full_name$|username$|address$|^inn$|serial$|serial_number$|fn_serial$|kkt_serial$|^mac$|^ip$|url_ofd$|account_id$|user_id$|pipo_id$|offline_shop_id$)')
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

function Invoke-Authentication([string]$Name,[string]$Path,[string[]]$Secrets) {
    $form = Join-Path $tmp ($Name + ".form")
    $raw = Join-Path $tmp ($Name + ".raw")

    Write-Text $form (Encode-Form @{
        username=[string]$config.login
        password=[string]$config.password
        client_id=[string]$config.client_id
        client_secret=[string]$config.client_secret
    })

    $meta = Invoke-CurlToFile ($baseUrl + $Path) $raw @(
        "--request","POST",
        "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
        "--header","Accept: application/json, */*",
        "--data-binary",("@" + $form)
    ) $Secrets

    $response=$null
    $parsed=$false
    $apiStatus=$null
    $token=""
    $refreshToken=""

    if (Test-Path -LiteralPath $raw) {
        try {
            $response = Get-Content -Raw -LiteralPath $raw -Encoding UTF8 | ConvertFrom-Json
            $parsed=$true

            if ($response.PSObject.Properties.Name -contains "status") {
                $apiStatus=[bool]$response.status
            }

            if ($null -ne $response.result) {
                if ($response.result.PSObject.Properties.Name -contains "access_token") {
                    $token=[string]$response.result.access_token
                }
                if ($response.result.PSObject.Properties.Name -contains "refresh_token") {
                    $refreshToken=[string]$response.result.refresh_token
                }
            }
        } catch {}
    }

    Save-Json (Join-Path $out ($Name + "_http.json")) $meta 5
    Save-Json (Join-Path $out ($Name + "_sanitized.json")) ([ordered]@{
        path=$Path
        curl_exit=$meta.curl_exit
        http_code=$meta.http_code
        json_parsed=$parsed
        api_status=$apiStatus
        access_token_present=(-not [string]::IsNullOrWhiteSpace($token))
        refresh_token_present=(-not [string]::IsNullOrWhiteSpace($refreshToken))
    }) 6

    return [pscustomobject]@{
        path=$Path
        meta=$meta
        response=$response
        parsed=$parsed
        api_status=$apiStatus
        token=$token
        refresh_token=$refreshToken
    }
}

function Invoke-ReadOnlyApi([string]$Name,[string]$Path,[string]$Token,[hashtable]$Fields,[string[]]$Secrets,[bool]$RedactNames=$false) {
    if ([string]::IsNullOrWhiteSpace($Token)) {
        Save-Json (Join-Path $out ($Name + "_skipped.json")) ([ordered]@{
            skipped=$true
            reason="missing access token"
            path=$Path
        }) 5

        return [pscustomobject]@{
            name=$Name
            path=$Path
            parsed=$false
            api_status=$null
            response=$null
            skipped=$true
        }
    }

    $payload=@{
        client_id=[string]$config.client_id
        client_secret=[string]$config.client_secret
        access_token=$Token
    }

    foreach ($key in $Fields.Keys) {
        $payload[$key]=$Fields[$key]
    }

    $form=Join-Path $tmp ($Name + ".form")
    $raw=Join-Path $tmp ($Name + ".raw")
    Write-Text $form (Encode-Form $payload)

    $meta=Invoke-CurlToFile ($baseUrl + $Path) $raw @(
        "--request","POST",
        "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
        "--header","Accept: application/json, */*",
        "--data-binary",("@" + $form)
    ) $Secrets

    $response=$null
    $parsed=$false
    $apiStatus=$null

    if (Test-Path -LiteralPath $raw) {
        try {
            $response=Get-Content -Raw -LiteralPath $raw -Encoding UTF8 | ConvertFrom-Json
            $parsed=$true
            if ($response.PSObject.Properties.Name -contains "status") {
                $apiStatus=[bool]$response.status
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
        name=$Name
        path=$Path
        parsed=$parsed
        api_status=$apiStatus
        response=$response
        skipped=$false
    }
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1)

$baseSecrets=@(
    [string]$config.login,
    [string]$config.password,
    [string]$config.client_secret,
    [string]$config.device_code
) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

try {
    Write-Text (Join-Path $out "00_git_state.txt") ("Branch=" + $branch + [Environment]::NewLine + "SHA=" + $sha + [Environment]::NewLine)

    Save-Json (Join-Path $out "01_scope.json") ([ordered]@{
        audit="S3 ordinary vs admin authentication permission audit"
        mode="READ_ONLY"
        profile_id=[string]$config.profile_id
        channel_id=[string]$config.channel_id
        mutating_calls=0
        admin_device_create_allowed=$false
        admin_device_update_allowed=$false
        repeat_activation_allowed=$false
        device_register_allowed=$false
        order_send_allowed=$false
    }) 6

    $ordinary=Invoke-Authentication "10_ordinary_auth" "user/authentication" $baseSecrets
    $admin=Invoke-Authentication "11_admin_auth" "user/admin-authentication" $baseSecrets

    $allSecrets=@($baseSecrets + @(
        [string]$ordinary.token,
        [string]$ordinary.refresh_token,
        [string]$admin.token,
        [string]$admin.refresh_token
    )) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique

    $ordinaryPermissions=Invoke-ReadOnlyApi "20_ordinary_permissions" "user/get-permissions" $ordinary.token @{} $allSecrets $false
    $adminPermissions=Invoke-ReadOnlyApi "21_admin_permissions" "user/get-permissions" $admin.token @{} $allSecrets $false

    $adminProfiles=Invoke-ReadOnlyApi "22_admin_profiles" "user/get-profile-list" $admin.token @{} $allSecrets $true

    $adminFind=$null
    if (-not [string]::IsNullOrWhiteSpace([string]$admin.token)) {
        $adminFind=Invoke-ReadOnlyApi "30_admin_device_find" "admin/device/find" $admin.token @{
            profile_id=[string]$config.profile_id
            page_size="100"
            page_number="1"
            alive="1"
        } $allSecrets $true
    } else {
        $adminFind=Invoke-ReadOnlyApi "30_admin_device_find" "admin/device/find" "" @{} $allSecrets $true
    }

    $summary=[ordered]@{
        audit="i-Retail S3 admin-auth permission audit"
        timestamp=$stamp
        git_branch=$branch
        git_sha=$sha
        network_actions="two authentication calls + read-only permissions/profile/admin-find only"
        mutating_calls=0
        ordinary_auth_api_status=$ordinary.api_status
        ordinary_token_present=(-not [string]::IsNullOrWhiteSpace([string]$ordinary.token))
        admin_auth_api_status=$admin.api_status
        admin_token_present=(-not [string]::IsNullOrWhiteSpace([string]$admin.token))
        tokens_equal=(-not [string]::IsNullOrWhiteSpace([string]$ordinary.token) -and [string]$ordinary.token -eq [string]$admin.token)
        ordinary_permissions_api_status=$ordinaryPermissions.api_status
        admin_permissions_api_status=$adminPermissions.api_status
        admin_profiles_api_status=$adminProfiles.api_status
        admin_device_find_api_status=$adminFind.api_status
        admin_device_find_skipped=$adminFind.skipped
        admin_device_create_allowed=$false
        admin_device_update_allowed=$false
        repeat_activation_allowed=$false
        device_register_allowed=$false
        order_send_allowed=$false
    }

    Save-Json (Join-Path $out "SUMMARY.json") $summary 10

    $unsafe=@()
    Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object { $_.Extension -match "^\.(txt|json)$" } | ForEach-Object {
        $content=Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue

        foreach ($secret in $allSecrets) {
            if ($null -ne $content -and -not [string]::IsNullOrEmpty($secret) -and $content.Contains($secret)) {
                $unsafe += $_.FullName
                break
            }
        }
    }

    if ($unsafe.Count -gt 0) {
        $names=@($unsafe | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object -Unique)
        throw ("Safety scan failed: secret value found in report: " + ($names -join ","))
    }

    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

    Write-Host "[SUCCESS] S3 admin-auth permission audit completed."
    Write-Host ("[REPORT] " + $zip)
    Write-Host ("[ORDINARY AUTH] status=" + [string]$summary.ordinary_auth_api_status + " token=" + [string]$summary.ordinary_token_present)
    Write-Host ("[ADMIN AUTH] status=" + [string]$summary.admin_auth_api_status + " token=" + [string]$summary.admin_token_present)
    Write-Host ("[TOKENS EQUAL] " + [string]$summary.tokens_equal)
    Write-Host ("[ORDINARY PERMISSIONS] status=" + [string]$summary.ordinary_permissions_api_status)
    Write-Host ("[ADMIN PERMISSIONS] status=" + [string]$summary.admin_permissions_api_status)
    Write-Host ("[ADMIN DEVICE FIND] status=" + [string]$summary.admin_device_find_api_status + " skipped=" + [string]$summary.admin_device_find_skipped)
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
