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
$docBase = "https://my.i-retail.com/api/apidoc/actual"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$root = Join-Path $RepoRoot "test_reports\sbp_direct_server"
$out = Join-Path $root ("SBP_DIRECT_SERVER_" + $stamp)
$pagesDir = Join-Path $out "api_docs"
$tmp = Join-Path $env:TEMP ("iretail_sbp_direct_" + $stamp + "_" + $PID)
$zip = $out + ".zip"

New-Item -ItemType Directory -Path $out -Force | Out-Null
New-Item -ItemType Directory -Path $pagesDir -Force | Out-Null
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
    $r = $Text
    foreach ($secret in $Secrets) {
        if (-not [string]::IsNullOrEmpty($secret)) { $r = $r.Replace($secret,"[REDACTED]") }
    }
    return $r
}

function Is-SensitiveKey([string]$Key) {
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    return ($Key -match '(?i)(password$|secret$|token$|pin$|device_code$|external_code$|^code$|phone$|email$|username$|address$|^inn$|serial$|serial_number$|^mac$|^ip$|account_id$|user_id$)')
}

function Sanitize-Value($Value,[string]$Key = "") {
    if (Is-SensitiveKey $Key) {
        if ($null -eq $Value) { return $null }
        return "[REDACTED]"
    }
    if ($null -eq $Value) { return $null }

    if ($Value -is [System.Collections.IDictionary]) {
        $dict = [ordered]@{}
        foreach ($k in $Value.Keys) { $dict[[string]$k] = Sanitize-Value $Value[$k] ([string]$k) }
        return [pscustomobject]$dict
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) { $items += ,(Sanitize-Value $item "") }
        return $items
    }
    if ($Value -is [pscustomobject]) {
        $obj = [ordered]@{}
        foreach ($prop in $Value.PSObject.Properties) { $obj[$prop.Name] = Sanitize-Value $prop.Value $prop.Name }
        return [pscustomobject]$obj
    }
    return $Value
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

    $meta = [ordered]@{curl_exit=$rc;http_code="";content_type="";time_total="";url_effective="";stderr=$stderr.Trim()}
    foreach ($part in ($line -split "\|")) {
        if ($part -match "^([^=]+)=(.*)$" -and $meta.Contains($matches[1])) { $meta[$matches[1]]=$matches[2] }
    }
    return [pscustomobject]$meta
}

function Html-ToText([string]$Html) {
    $text = [Regex]::Replace($Html,'(?is)<script.*?</script>',' ')
    $text = [Regex]::Replace($text,'(?is)<style.*?</style>',' ')
    $text = [Regex]::Replace($text,'(?is)<[^>]+>',' ')
    $text = [Net.WebUtility]::HtmlDecode($text)
    return [Regex]::Replace($text,'\s+',' ').Trim()
}

function Add-Contexts([string]$Page,[string]$Text,[string[]]$Needles,[System.Collections.Generic.List[string]]$Target) {
    foreach ($needle in $Needles) {
        $startAt = 0
        $count = 0
        while ($count -lt 8) {
            $idx = $Text.IndexOf($needle,$startAt,[StringComparison]::OrdinalIgnoreCase)
            if ($idx -lt 0) { break }
            $start = [Math]::Max(0,$idx-650)
            $len = [Math]::Min(1900,$Text.Length-$start)
            $Target.Add(($Page + " | " + $needle + " | " + $Text.Substring($start,$len)))
            $startAt = $idx + [Math]::Max(1,$needle.Length)
            $count++
        }
    }
}

function Add-SlugItems($Value,[System.Collections.Generic.List[object]]$List) {
    if ($null -eq $Value) { return }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [pscustomobject])) {
        foreach ($item in $Value) { Add-SlugItems $item $List }
        return
    }
    if ($Value -is [pscustomobject]) {
        if ($Value.PSObject.Properties.Name -contains "slug") {
            $entry=[ordered]@{slug=[string]$Value.slug}
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
    Write-Text (Join-Path $out "00_git_state.txt") ("Branch="+$branch+[Environment]::NewLine+"SHA="+$sha+[Environment]::NewLine)

    # A. Download only public API documentation pages. No business mutation.
    $docPages = @(
        "app-controllers-iretail-ordercontroller.html",
        "app-controllers-iretail-paymentincontroller.html",
        "app-controllers-iretail-channelcontroller.html",
        "app-controllers-serviceincontroller.html"
    )
    $docResults=@()
    $contexts = New-Object System.Collections.Generic.List[string]
    $needles=@(
        "create-payment-for-order",
        "get-available-services-in",
        "payment-in/create",
        "service_in_slug",
        "service_in_id",
        "sbp_low_risk",
        "sbp",
        "payin_payout",
        "qr",
        "payment_url",
        "confirmation_url",
        "expires",
        "status"
    )

    foreach ($page in $docPages) {
        $dst=Join-Path $pagesDir $page
        $meta=Invoke-CurlToFile ($docBase+"/"+$page) $dst @() $baseSecrets
        $size=0
        if(Test-Path -LiteralPath $dst){$size=(Get-Item -LiteralPath $dst).Length}
        $docResults += [pscustomobject]@{page=$page;http_code=$meta.http_code;curl_exit=$meta.curl_exit;size=$size}
        if(Test-Path -LiteralPath $dst) {
            $html=Get-Content -Raw -LiteralPath $dst -Encoding UTF8 -ErrorAction SilentlyContinue
            if($null -ne $html) { Add-Contexts $page (Html-ToText $html) $needles $contexts }
        }
    }
    Save-Json (Join-Path $out "01_doc_pages.json") $docResults 6
    Write-Text (Join-Path $out "02_doc_contexts.txt") (($contexts -join ([Environment]::NewLine+[Environment]::NewLine))+[Environment]::NewLine)

    # B. Authenticate only for read-only reference/service queries.
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

    $token=""
    $authStatus=$false
    if(Test-Path -LiteralPath $authRaw) {
        $authObject=Get-Content -Raw -LiteralPath $authRaw -Encoding UTF8 | ConvertFrom-Json
        $authStatus=[bool]$authObject.status
        if($null -ne $authObject.result -and $null -ne $authObject.result.access_token) {$token=[string]$authObject.result.access_token}
    }
    Save-Json (Join-Path $out "03_auth_sanitized.json") ([ordered]@{
        http_code=$authMeta.http_code;api_status=$authStatus;token_present=(-not [string]::IsNullOrWhiteSpace($token))
    }) 4
    if([string]::IsNullOrWhiteSpace($token)){throw "Authentication did not produce access token"}

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
        $parsed=$false
        $apiStatus=$null
        if(Test-Path -LiteralPath $raw) {
            try {
                $response=Get-Content -Raw -LiteralPath $raw -Encoding UTF8 | ConvertFrom-Json
                if($response.PSObject.Properties.Name -contains "status"){$apiStatus=[bool]$response.status}
                Save-Json (Join-Path $out ($Name+"_sanitized.json")) (Sanitize-Value $response) 20
                $parsed=$true
            } catch {
                Save-Json (Join-Path $out ($Name+"_parse_error.json")) ([ordered]@{error=$_.Exception.GetType().Name}) 4
            }
        }
        return [pscustomobject]@{name=$Name;path=$Path;meta=$meta;response=$response;parsed=$parsed;api_status=$apiStatus}
    }

    $results=@()
    $serviceList=Invoke-ReadOnlyApi "10_service_in_list" "service-in/get-service-in-list" @{}
    $results += $serviceList
    $serviceProfile=Invoke-ReadOnlyApi "11_service_in_profile" "service-in/get-service-in" @{profile_id=[string]$config.profile_id}
    $results += $serviceProfile
    $serviceUsed=Invoke-ReadOnlyApi "12_service_in_used" "service-in/get-used" @{profile_id=[string]$config.profile_id}
    $results += $serviceUsed
    $serviceTypes=Invoke-ReadOnlyApi "13_service_in_types" "service-in/get-service-in-types" @{}
    $results += $serviceTypes
    $channel=Invoke-ReadOnlyApi "14_channel" "iretail/channel/get" @{channel_id=[string]$config.channel_id}
    $results += $channel

    $allSlugs=New-Object System.Collections.Generic.List[object]
    foreach($rr in @($serviceList,$serviceProfile,$serviceUsed)) {
        if($null -ne $rr.response){Add-SlugItems $rr.response.result $allSlugs}
    }
    $slugArray=@($allSlugs.ToArray())
    $interesting=@($slugArray | Where-Object {
        $_.slug -match '(?i)(^sbp$|sbp_low_risk|payin_payout|online|external_plastic)'
    })
    Save-Json (Join-Path $out "20_interesting_services.json") $interesting 10

    $resultRows=@($results | ForEach-Object {
        [pscustomobject]@{
            name=$_.name;path=$_.path;http_code=$_.meta.http_code;curl_exit=$_.meta.curl_exit;
            json_parsed=$_.parsed;api_status=$_.api_status
        }
    })
    Save-Json (Join-Path $out "90_results.json") $resultRows 8

    $docText=$contexts -join " "
    $summary=[ordered]@{
        audit="SBP direct JL22 server contract read-only audit"
        timestamp=$stamp
        git_branch=$branch
        git_sha=$sha
        kozen_required=$false
        kozen_used=$false
        aoa_used=$false
        smartsky_used=$false
        payment_created=$false
        payment_in_created=$false
        order_created=$false
        docs_create_payment_for_order=($docText -match '(?i)create-payment-for-order')
        docs_get_available_services_in=($docText -match '(?i)get-available-services-in')
        docs_payment_in_create=($docText -match '(?i)payment-in/create')
        sbp_slug_seen=(@($slugArray | Where-Object {$_.slug -eq "sbp"}).Count -gt 0)
        sbp_low_risk_slug_seen=(@($slugArray | Where-Object {$_.slug -eq "sbp_low_risk"}).Count -gt 0)
        payin_payout_slug_seen=(@($slugArray | Where-Object {$_.slug -eq "payin_payout"}).Count -gt 0)
        network_actions="public apiDoc GET + authentication + service/channel read-only POSTs"
        forbidden_calls=@(
            "iretail/order/create-payment-for-order",
            "iretail/payment-in/create",
            "order/create",
            "order/pay",
            "iretail/order/synchronize"
        )
    }
    Save-Json (Join-Path $out "SUMMARY.json") $summary 10

    $summaryLines=@(
        "SBP direct JL22 server contract read-only audit",
        "Timestamp="+$stamp,
        "KozenRequired=NO",
        "KozenUsed=NO",
        "AOAUsed=NO",
        "SmartSkyUsed=NO",
        "PaymentCreated=NO",
        "DocsCreatePaymentForOrder="+$summary.docs_create_payment_for_order,
        "DocsGetAvailableServicesIn="+$summary.docs_get_available_services_in,
        "DocsPaymentInCreate="+$summary.docs_payment_in_create,
        "SbpSlugSeen="+$summary.sbp_slug_seen,
        "SbpLowRiskSlugSeen="+$summary.sbp_low_risk_slug_seen,
        "PayinPayoutSlugSeen="+$summary.payin_payout_slug_seen
    )
    Write-Text (Join-Path $out "SUMMARY.txt") (($summaryLines -join [Environment]::NewLine)+[Environment]::NewLine)

    # C. Hard safety scan: credentials/tokens must never enter the report.
    $hardSecrets=@([string]$config.password,[string]$config.client_secret,[string]$token) | Where-Object {-not [string]::IsNullOrEmpty($_)} | Select-Object -Unique
    $unsafe=@()
    Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object {$_.Extension -match "^\.(txt|json)$"} | ForEach-Object {
        $content=Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
        foreach($secret in $hardSecrets) {
            if($null -ne $content -and $content.Contains($secret)){$unsafe += $_.FullName;break}
        }
    }
    if($unsafe.Count -gt 0){throw "Safety scan failed: secret/token value found in report"}

    if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

    Write-Host "[SUCCESS] Direct SBP server read-only audit completed."
    Write-Host ("[REPORT] "+$zip)
    Write-Host "[SAFETY] Kozen/SmartSky/AOA not used. No payment/order was created."
    Write-Host ("[SERVICES] sbp="+$summary.sbp_slug_seen+" sbp_low_risk="+$summary.sbp_low_risk_slug_seen+" payin_payout="+$summary.payin_payout_slug_seen)
    exit 0
}
finally {
    if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
}
