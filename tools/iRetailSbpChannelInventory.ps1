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
$root = Join-Path $RepoRoot "test_reports\sbp_channel_inventory"
$out = Join-Path $root ("SBP_CHANNEL_INVENTORY_" + $stamp)
$tmp = Join-Path $env:TEMP ("iretail_sbp_channels_" + $stamp + "_" + $PID)
$zip = $out + ".zip"

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
    $r = $Text
    foreach ($secret in $Secrets) {
        if (-not [string]::IsNullOrEmpty($secret)) { $r = $r.Replace($secret,"[REDACTED]") }
    }
    return $r
}

function Invoke-CurlToFile([string]$Url,[string]$Output,[string[]]$Extra,[string[]]$Secrets) {
    $err = Join-Path $tmp ("curl_" + [Guid]::NewGuid().ToString("N") + ".err")
    $fmt = "http_code=%{http_code}|content_type=%{content_type}|time_total=%{time_total}|url_effective=%{url_effective}"
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

    $meta=[ordered]@{curl_exit=$rc;http_code="";content_type="";time_total="";url_effective="";stderr=$stderr.Trim()}
    foreach($part in ($line -split "\|")) {
        if($part -match "^([^=]+)=(.*)$" -and $meta.Contains($matches[1])){$meta[$matches[1]]=$matches[2]}
    }
    return [pscustomobject]$meta
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1).Trim()
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1).Trim()

$baseSecrets=@(
    [string]$config.login,
    [string]$config.password,
    [string]$config.client_secret,
    [string]$config.device_code
) | Where-Object {-not [string]::IsNullOrEmpty($_)} | Select-Object -Unique

try {
    Write-Text (Join-Path $out "00_git_state.txt") ("Branch="+$branch+[Environment]::NewLine+"SHA="+$sha+[Environment]::NewLine)

    $authForm=Join-Path $tmp "auth.form"
    Write-Text $authForm (Encode-Form @{
        username=[string]$config.login
        password=[string]$config.password
        client_id=[string]$config.client_id
        client_secret=[string]$config.client_secret
    })
    $authRaw=Join-Path $tmp "auth.json"
    $authMeta=Invoke-CurlToFile ($baseUrl+"user/authentication") $authRaw @(
        "--request","POST",
        "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
        "--header","Accept: application/json, */*",
        "--data-binary",("@"+$authForm)
    ) $baseSecrets

    $auth=Get-Content -Raw -LiteralPath $authRaw -Encoding UTF8 | ConvertFrom-Json
    $token=""
    if($null -ne $auth.result -and $null -ne $auth.result.access_token){$token=[string]$auth.result.access_token}
    if([string]::IsNullOrWhiteSpace($token)){throw "Authentication did not produce access token"}

    Save-Json (Join-Path $out "01_auth_sanitized.json") ([ordered]@{
        http_code=$authMeta.http_code
        api_status=[bool]$auth.status
        token_present=$true
    }) 4

    $allSecrets=@($baseSecrets+@($token)) | Where-Object {-not [string]::IsNullOrEmpty($_)} | Select-Object -Unique
    $common=@{client_id=[string]$config.client_id;client_secret=[string]$config.client_secret;access_token=$token}

    function Invoke-ReadOnlyApi([string]$Name,[string]$Path,[hashtable]$Fields) {
        $payload=@{}
        foreach($key in $common.Keys){$payload[$key]=$common[$key]}
        foreach($key in $Fields.Keys){$payload[$key]=$Fields[$key]}

        $form=Join-Path $tmp ($Name+".form")
        $raw=Join-Path $tmp ($Name+".raw")
        Write-Text $form (Encode-Form $payload)
        $meta=Invoke-CurlToFile ($baseUrl+$Path) $raw @(
            "--request","POST",
            "--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
            "--header","Accept: application/json, */*",
            "--data-binary",("@"+$form)
        ) $allSecrets

        $response=$null
        if(Test-Path -LiteralPath $raw) {
            try { $response=Get-Content -Raw -LiteralPath $raw -Encoding UTF8 | ConvertFrom-Json }
            catch { }
        }
        return [pscustomobject]@{name=$Name;path=$Path;meta=$meta;response=$response}
    }

    # 1. Enumerate every channel in the configured profile.
    $channelsResp=Invoke-ReadOnlyApi "10_channels" "iretail/channel/get-channels" @{
        profile_id=[string]$config.profile_id
    }
    if($null -eq $channelsResp.response -or $channelsResp.response.status -ne $true) {
        throw "iretail/channel/get-channels did not return status=true"
    }

    $channelItems=@()
    $result=$channelsResp.response.result
    if($result -is [System.Collections.IEnumerable] -and -not ($result -is [string]) -and -not ($result -is [pscustomobject])) {
        $channelItems=@($result)
    } elseif($result -is [pscustomobject] -and $result.PSObject.Properties.Name -contains "rows") {
        $channelItems=@($result.rows)
    } elseif($null -ne $result) {
        $channelItems=@($result)
    }

    $inventory=New-Object System.Collections.Generic.List[object]
    $limit=50
    $checked=0

    foreach($ch in $channelItems) {
        if($checked -ge $limit){break}
        if($null -eq $ch -or $ch.PSObject.Properties.Name -notcontains "id"){continue}

        $channelId=[string]$ch.id
        if([string]::IsNullOrWhiteSpace($channelId)){continue}

        $detailResp=Invoke-ReadOnlyApi ("20_channel_"+$channelId) "iretail/channel/get" @{
            channel_id=$channelId
        }
        $servicesResp=Invoke-ReadOnlyApi ("30_services_"+$channelId) "iretail/channel/get-available-services-in" @{
            channel_id=$channelId
        }

        $detail=$null
        if($null -ne $detailResp.response -and $detailResp.response.status -eq $true){$detail=$detailResp.response.result}
        $serviceResult=$null
        if($null -ne $servicesResp.response -and $servicesResp.response.status -eq $true){$serviceResult=$servicesResp.response.result}

        $serviceRows=@()
        $userVerified=$null
        $shopVerified=$null
        if($null -ne $serviceResult) {
            if($serviceResult.PSObject.Properties.Name -contains "user_verified"){$userVerified=$serviceResult.user_verified}
            if($serviceResult.PSObject.Properties.Name -contains "shop_verified"){$shopVerified=$serviceResult.shop_verified}
            if($serviceResult.PSObject.Properties.Name -contains "services" -and $null -ne $serviceResult.services) {
                foreach($svc in @($serviceResult.services)) {
                    if($null -eq $svc){continue}
                    $serviceId=$null
                    $serviceSlug=$null
                    $serviceTitle=$null
                    $serviceEnabled=$null
                    if($svc.PSObject.Properties.Name -contains "id"){$serviceId=$svc.id}
                    if($svc.PSObject.Properties.Name -contains "slug"){$serviceSlug=[string]$svc.slug}
                    if($svc.PSObject.Properties.Name -contains "title"){$serviceTitle=[string]$svc.title}
                    if($svc.PSObject.Properties.Name -contains "enabled"){$serviceEnabled=$svc.enabled}
                    $serviceRows += [pscustomobject]@{
                        id=$serviceId
                        slug=$serviceSlug
                        title=$serviceTitle
                        enabled=$serviceEnabled
                    }
                }
            }
        }

        $channelName=$null
        $channelTypeId=$null
        $channelStatusId=$null
        $channelEnable=$null
        $relatedEnabled=$null
        $relatedStatusId=$null
        $offlineShopPresent=$false
        if($null -ne $detail) {
            if($detail.PSObject.Properties.Name -contains "name"){$channelName=[string]$detail.name}
            if($detail.PSObject.Properties.Name -contains "type_id"){$channelTypeId=$detail.type_id}
            if($detail.PSObject.Properties.Name -contains "status_id"){$channelStatusId=$detail.status_id}
            if($detail.PSObject.Properties.Name -contains "enable"){$channelEnable=$detail.enable}
            if($detail.PSObject.Properties.Name -contains "related" -and $null -ne $detail.related) {
                $rel=$detail.related
                if($rel.PSObject.Properties.Name -contains "enabled"){$relatedEnabled=$rel.enabled}
                if($rel.PSObject.Properties.Name -contains "status_id"){$relatedStatusId=$rel.status_id}
                if($rel.PSObject.Properties.Name -contains "offline_shop_id"){$offlineShopPresent=($null -ne $rel.offline_shop_id)}
            }
        }

        $sbpRows=@($serviceRows | Where-Object {$_.slug -match '(?i)^sbp($|_)'})
        $inventory.Add([pscustomobject]@{
            channel_id=$channelId
            channel_name=$channelName
            configured_channel=($channelId -eq [string]$config.channel_id)
            type_id=$channelTypeId
            status_id=$channelStatusId
            channel_enable=$channelEnable
            related_enabled=$relatedEnabled
            related_status_id=$relatedStatusId
            offline_shop_present=$offlineShopPresent
            user_verified=$userVerified
            shop_verified=$shopVerified
            service_count=$serviceRows.Count
            service_slugs=@($serviceRows | ForEach-Object {$_.slug})
            sbp_count=$sbpRows.Count
            sbp_services=$sbpRows
            channel_http=$detailResp.meta.http_code
            services_http=$servicesResp.meta.http_code
        })

        $checked++
    }

    $rows=@($inventory.ToArray())
    Save-Json (Join-Path $out "20_channel_inventory.json") $rows 16

    $sbpChannels=@($rows | Where-Object {$_.sbp_count -gt 0})
    $verifiedChannels=@($rows | Where-Object {$_.shop_verified -eq $true})
    $enabledChannels=@($rows | Where-Object {$_.channel_enable -eq $true -or $_.related_enabled -eq $true})
    $configured=@($rows | Where-Object {$_.configured_channel})

    $summary=[ordered]@{
        audit="Direct SBP profile channel inventory"
        timestamp=$stamp
        git_branch=$branch
        git_sha=$sha
        profile_id=[string]$config.profile_id
        configured_channel_id=[string]$config.channel_id
        kozen_used=$false
        smartsky_used=$false
        aoa_used=$false
        adb_used=$false
        financial_mutation=$false
        channels_returned=$channelItems.Count
        channels_checked=$rows.Count
        channels_with_sbp=$sbpChannels.Count
        channels_with_sbp_rows=$sbpChannels
        shop_verified_channels=$verifiedChannels.Count
        enabled_channels=$enabledChannels.Count
        configured_channel=$configured
        network_actions="authentication + iretail/channel/get-channels + channel/get + channel/get-available-services-in"
    }
    Save-Json (Join-Path $out "SUMMARY.json") $summary 16

    $lines=@(
        "Direct SBP profile channel inventory",
        "Timestamp="+$stamp,
        "ProfileId="+[string]$config.profile_id,
        "ConfiguredChannelId="+[string]$config.channel_id,
        "KozenUsed=NO",
        "SmartSkyUsed=NO",
        "AOAUsed=NO",
        "ADBUsed=NO",
        "FinancialMutation=NO",
        "ChannelsReturned="+$channelItems.Count,
        "ChannelsChecked="+$rows.Count,
        "ChannelsWithSBP="+$sbpChannels.Count,
        "ShopVerifiedChannels="+$verifiedChannels.Count,
        "EnabledChannels="+$enabledChannels.Count
    )
    Write-Text (Join-Path $out "SUMMARY.txt") (($lines -join [Environment]::NewLine)+[Environment]::NewLine)

    # Hard secret scan.
    $hardSecrets=@([string]$config.password,[string]$config.client_secret,[string]$token) | Where-Object {-not [string]::IsNullOrEmpty($_)} | Select-Object -Unique
    $unsafe=@()
    Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object {$_.Extension -match "^\.(txt|json)$"} | ForEach-Object {
        $body=Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
        foreach($secret in $hardSecrets) {
            if($null -ne $body -and $body.Contains($secret)){$unsafe += $_.FullName;break}
        }
    }
    if($unsafe.Count -gt 0){throw "Safety scan failed: credential/token value found in report"}

    if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

    Write-Host "[SUCCESS] SBP channel inventory completed."
    Write-Host ("[REPORT] "+$zip)
    Write-Host ("[CHANNELS] checked="+$rows.Count+" sbp="+$sbpChannels.Count+" verified="+$verifiedChannels.Count+" enabled="+$enabledChannels.Count)
    Write-Host "[SAFETY] No payment/order/channel configuration was changed."
    exit 0
}
finally {
    if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
}
