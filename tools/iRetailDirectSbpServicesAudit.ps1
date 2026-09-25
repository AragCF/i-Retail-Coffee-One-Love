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
$root = Join-Path $RepoRoot "test_reports\sbp_direct_services"
$out = Join-Path $root ("SBP_DIRECT_SERVICES_" + $stamp)
$tmp = Join-Path $env:TEMP ("iretail_sbp_services_" + $stamp + "_" + $PID)
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

function Is-SensitiveKey([string]$Key) {
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    return ($Key -match '(?i)(password$|secret$|token$|pin$|device_code$|external_code$|phone$|email$|username$|address$|^inn$|serial$|serial_number$|^mac$|^ip$|account_id$|user_id$|view_token$|tech_password$)')
}

function Sanitize-Value($Value,[string]$Key = "") {
    if (Is-SensitiveKey $Key) {
        if ($null -eq $Value) { return $null }
        return "[REDACTED]"
    }
    if ($null -eq $Value) { return $null }

    if ($Value -is [System.Collections.IDictionary]) {
        $dict=[ordered]@{}
        foreach($k in $Value.Keys){$dict[[string]$k]=Sanitize-Value $Value[$k] ([string]$k)}
        return [pscustomobject]$dict
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items=@()
        foreach($item in $Value){$items += ,(Sanitize-Value $item "")}
        return $items
    }
    if ($Value -is [pscustomobject]) {
        $obj=[ordered]@{}
        foreach($prop in $Value.PSObject.Properties){$obj[$prop.Name]=Sanitize-Value $prop.Value $prop.Name}
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
    if(Test-Path -LiteralPath $err) {
        $stderr = Redact-Text (Get-Content -Raw -LiteralPath $err -ErrorAction SilentlyContinue) $Secrets
        Remove-Item -LiteralPath $err -Force -ErrorAction SilentlyContinue
    }

    $meta=[ordered]@{curl_exit=$rc;http_code="";content_type="";time_total="";url_effective="";stderr=$stderr.Trim()}
    foreach($part in ($line -split "\|")) {
        if($part -match "^([^=]+)=(.*)$" -and $meta.Contains($matches[1])){$meta[$matches[1]]=$matches[2]}
    }
    return [pscustomobject]$meta
}

function Html-ToText([string]$Html) {
    $text=[Regex]::Replace($Html,'(?is)<script.*?</script>',' ')
    $text=[Regex]::Replace($text,'(?is)<style.*?</style>',' ')
    $text=[Regex]::Replace($text,'(?is)<[^>]+>',' ')
    $text=[Net.WebUtility]::HtmlDecode($text)
    return [Regex]::Replace($text,'\s+',' ').Trim()
}

function Find-Context([string]$Page,[string]$Text,[string]$Needle) {
    $idx=$Text.IndexOf($Needle,[StringComparison]::OrdinalIgnoreCase)
    if($idx -lt 0){return $null}
    $start=[Math]::Max(0,$idx-900)
    $len=[Math]::Min(3200,$Text.Length-$start)
    return ($Page+" | "+$Needle+" | "+$Text.Substring($start,$len))
}

function Get-ResultObject($Response) {
    if($null -eq $Response){return $null}
    if($Response.PSObject.Properties.Name -notcontains "result"){return $null}
    return $Response.result
}

function Collect-ServiceRows($Value,[System.Collections.Generic.List[object]]$Target) {
    if($null -eq $Value){return}
    if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [pscustomobject])) {
        foreach($item in $Value){Collect-ServiceRows $item $Target}
        return
    }
    if($Value -is [pscustomobject]) {
        if($Value.PSObject.Properties.Name -contains "slug") {
            $row=[ordered]@{slug=[string]$Value.slug}
            foreach($field in @("id","title","name","enabled")) {
                if($Value.PSObject.Properties.Name -contains $field){$row[$field]=$Value.$field}
            }
            $Target.Add([pscustomobject]$row)
        }
        foreach($prop in $Value.PSObject.Properties) {
            if($prop.Name -ne "slug"){Collect-ServiceRows $prop.Value $Target}
        }
    }
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

    # 1. Current public API documentation: exact methods that survived in current docs.
    $docPages=@(
        "app-controllers-iretail-ordercontroller.html",
        "app-controllers-iretail-paymentincontroller.html",
        "app-controllers-iretail-channelcontroller.html"
    )
    $contexts=New-Object System.Collections.Generic.List[string]
    $docMeta=@()
    foreach($page in $docPages) {
        $raw=Join-Path $tmp $page
        $meta=Invoke-CurlToFile ($docBase+"/"+$page) $raw @() $baseSecrets
        $docMeta += [pscustomobject]@{page=$page;http_code=$meta.http_code;curl_exit=$meta.curl_exit}
        if(Test-Path -LiteralPath $raw) {
            $text=Html-ToText (Get-Content -Raw -LiteralPath $raw -Encoding UTF8)
            foreach($needle in @(
                "/api/iretail/channel/get-available-services-in",
                "/api/iretail/channel/get-payments-in",
                "/api/iretail/payment-in/create",
                "/api/iretail/payment-in/get-status",
                "/api/iretail/order/get-payment-data",
                "payment_link",
                "qr_code",
                "process_input"
            )) {
                $ctx=Find-Context $page $text $needle
                if($null -ne $ctx){$contexts.Add($ctx)}
            }
        }
    }
    Save-Json (Join-Path $out "01_doc_pages.json") $docMeta 6
    Write-Text (Join-Path $out "02_contract_contexts.txt") (($contexts -join ([Environment]::NewLine+[Environment]::NewLine))+[Environment]::NewLine)

    # 2. Authenticate for read-only live metadata.
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

    Save-Json (Join-Path $out "03_auth_sanitized.json") ([ordered]@{
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
        $parsed=$false
        $apiStatus=$null
        if(Test-Path -LiteralPath $raw) {
            try {
                $response=Get-Content -Raw -LiteralPath $raw -Encoding UTF8 | ConvertFrom-Json
                if($response.PSObject.Properties.Name -contains "status"){$apiStatus=[bool]$response.status}
                Save-Json (Join-Path $out ($Name+"_sanitized.json")) (Sanitize-Value $response) 24
                $parsed=$true
            } catch {
                Save-Json (Join-Path $out ($Name+"_parse_error.json")) ([ordered]@{error=$_.Exception.GetType().Name}) 4
            }
        }
        return [pscustomobject]@{name=$Name;path=$Path;meta=$meta;response=$response;parsed=$parsed;api_status=$apiStatus}
    }

    # 3. These calls are semantically read-only.
    $available=Invoke-ReadOnlyApi "10_channel_available_services" "iretail/channel/get-available-services-in" @{
        channel_id=[string]$config.channel_id
    }
    $used=Invoke-ReadOnlyApi "11_profile_used_services" "service-in/get-used" @{
        profile_id=[string]$config.profile_id
    }
    $all=Invoke-ReadOnlyApi "12_all_services" "service-in/get-service-in-list" @{}
    $payments=Invoke-ReadOnlyApi "13_recent_payments_in" "iretail/channel/get-payments-in" @{
        channel_id=[string]$config.channel_id
        page_number="0"
        page_size="25"
    }

    $availableRows=New-Object System.Collections.Generic.List[object]
    Collect-ServiceRows (Get-ResultObject $available.response) $availableRows
    $usedRows=New-Object System.Collections.Generic.List[object]
    Collect-ServiceRows (Get-ResultObject $used.response) $usedRows
    $allRows=New-Object System.Collections.Generic.List[object]
    Collect-ServiceRows (Get-ResultObject $all.response) $allRows

    $availableArray=@($availableRows.ToArray())
    $usedArray=@($usedRows.ToArray())
    $allArray=@($allRows.ToArray())

    $availableSbp=@($availableArray | Where-Object {$_.slug -match '(?i)^sbp($|_)'})
    $usedSbp=@($usedArray | Where-Object {$_.slug -match '(?i)^sbp($|_)'})
    $knownSbp=@($allArray | Where-Object {$_.slug -match '(?i)^sbp($|_)'})

    Save-Json (Join-Path $out "20_available_sbp_services.json") $availableSbp 10
    Save-Json (Join-Path $out "21_used_sbp_services.json") $usedSbp 10
    Save-Json (Join-Path $out "22_known_sbp_services.json") $knownSbp 10

    $docText=$contexts -join " "
    $summary=[ordered]@{
        audit="Direct JL22 SBP service availability read-only audit"
        timestamp=$stamp
        git_branch=$branch
        git_sha=$sha
        channel_id=[string]$config.channel_id
        profile_id=[string]$config.profile_id
        kozen_used=$false
        smartsky_used=$false
        aoa_used=$false
        payment_created=$false
        order_created=$false
        payment_in_created=$false
        docs_create_payment_for_order_present=($docText -match '(?i)create-payment-for-order')
        docs_payment_in_create_present=($docText -match '(?i)/api/iretail/payment-in/create')
        docs_payment_in_get_status_present=($docText -match '(?i)/api/iretail/payment-in/get-status')
        docs_order_get_payment_data_present=($docText -match '(?i)/api/iretail/order/get-payment-data')
        docs_payment_link_present=($docText -match '(?i)payment_link')
        docs_qr_code_present=($docText -match '(?i)qr_code')
        available_api_status=$available.api_status
        available_sbp_count=$availableSbp.Count
        available_sbp=$availableSbp
        used_sbp_count=$usedSbp.Count
        used_sbp=$usedSbp
        known_sbp_count=$knownSbp.Count
        recent_payments_api_status=$payments.api_status
        network_actions="public apiDoc GET + auth + read-only available-services/used-services/service-list/payments-in"
        forbidden_calls=@(
            "iretail/payment-in/create",
            "order/create",
            "order/pay",
            "iretail/order/synchronize",
            "iretail/payment-in/revert"
        )
    }
    Save-Json (Join-Path $out "SUMMARY.json") $summary 16

    $lines=@(
        "Direct JL22 SBP service availability read-only audit",
        "Timestamp="+$stamp,
        "KozenUsed=NO",
        "SmartSkyUsed=NO",
        "AOAUsed=NO",
        "FinancialMutation=NO",
        "DocsCreatePaymentForOrder="+$summary.docs_create_payment_for_order_present,
        "DocsPaymentInCreate="+$summary.docs_payment_in_create_present,
        "DocsPaymentInGetStatus="+$summary.docs_payment_in_get_status_present,
        "DocsOrderGetPaymentData="+$summary.docs_order_get_payment_data_present,
        "DocsPaymentLink="+$summary.docs_payment_link_present,
        "DocsQrCode="+$summary.docs_qr_code_present,
        "AvailableSbpCount="+$summary.available_sbp_count,
        "UsedSbpCount="+$summary.used_sbp_count,
        "KnownSbpCount="+$summary.known_sbp_count
    )
    Write-Text (Join-Path $out "SUMMARY.txt") (($lines -join [Environment]::NewLine)+[Environment]::NewLine)

    # 4. Hard secret scan.
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

    Write-Host "[SUCCESS] Direct SBP service availability audit completed."
    Write-Host ("[REPORT] "+$zip)
    Write-Host ("[SBP] available="+$availableSbp.Count+" used="+$usedSbp.Count+" known="+$knownSbp.Count)
    Write-Host "[SAFETY] No payment/order created. Kozen/SmartSky/AOA not used."
    exit 0
}
finally {
    if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
}
