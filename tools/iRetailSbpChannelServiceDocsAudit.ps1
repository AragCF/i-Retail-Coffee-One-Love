param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $RepoRoot = (Resolve-Path $RepoRoot).Path
}

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw "curl.exe not found" }

$docBase = "https://my.i-retail.com/api/apidoc/actual"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$root = Join-Path $RepoRoot "test_reports\sbp_channel_service_docs"
$out = Join-Path $root ("SBP_CHANNEL_SERVICE_DOCS_" + $stamp)
$tmp = Join-Path $env:TEMP ("iretail_sbp_docs_" + $stamp + "_" + $PID)
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

function Invoke-CurlToFile([string]$Url,[string]$Output) {
    $fmt = "http_code=%{http_code}|content_type=%{content_type}|time_total=%{time_total}|url_effective=%{url_effective}"
    $line = (& curl.exe --silent --show-error --location --connect-timeout 15 --max-time 45 --output $Output --write-out $fmt $Url | Out-String).Trim()
    $rc = $LASTEXITCODE
    $meta=[ordered]@{curl_exit=$rc;http_code="";content_type="";time_total="";url_effective=""}
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

function Add-Contexts([string]$Page,[string]$Text,[string[]]$Needles,[System.Collections.Generic.List[object]]$Target) {
    foreach($needle in $Needles) {
        $startAt=0
        $count=0
        while($count -lt 12) {
            $idx=$Text.IndexOf($needle,$startAt,[StringComparison]::OrdinalIgnoreCase)
            if($idx -lt 0){break}
            $start=[Math]::Max(0,$idx-1000)
            $len=[Math]::Min(3600,$Text.Length-$start)
            $Target.Add([pscustomobject]@{
                page=$Page
                term=$needle
                context=$Text.Substring($start,$len)
            })
            $startAt=$idx+[Math]::Max(1,$needle.Length)
            $count++
        }
    }
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1).Trim()
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1).Trim()

try {
    Write-Text (Join-Path $out "00_git_state.txt") ("Branch="+$branch+[Environment]::NewLine+"SHA="+$sha+[Environment]::NewLine)

    $indexPath=Join-Path $tmp "index.html"
    $indexMeta=Invoke-CurlToFile ($docBase+"/index.html") $indexPath
    Save-Json (Join-Path $out "01_index_http.json") $indexMeta 5
    if($indexMeta.http_code -ne "200"){throw "API documentation index HTTP="+$indexMeta.http_code}

    $indexHtml=Get-Content -Raw -LiteralPath $indexPath -Encoding UTF8
    $links=New-Object System.Collections.Generic.List[string]
    foreach($m in [Regex]::Matches($indexHtml,'href\s*=\s*["'']([^"'']+\.html)["'']','IgnoreCase')) {
        $href=[string]$m.Groups[1].Value
        $leaf=[IO.Path]::GetFileName($href)
        if($leaf -match '(?i)(channel|servicein|service-in|shop|paymentin|payment-in|payin|profile|admin)') {
            if(-not $links.Contains($leaf)){$links.Add($leaf)}
        }
    }

    # Known pages are added even if index markup changes.
    foreach($leaf in @(
        "app-controllers-iretail-channelcontroller.html",
        "app-controllers-serviceincontroller.html",
        "app-controllers-iretail-paymentincontroller.html",
        "app-controllers-admin-channelcontroller.html",
        "app-controllers-admin-shopcontroller.html",
        "app-controllers-admin-profilecontroller.html"
    )) {
        if(-not $links.Contains($leaf)){$links.Add($leaf)}
    }

    $needles=@(
        "get-available-services-in",
        "service_in_id",
        "service_in_slug",
        "shop_verified",
        "user_verified",
        "offline_shop_id",
        "pipo_id",
        "verify",
        "verification",
        "enable",
        "enabled",
        "update",
        "edit",
        "save",
        "create",
        "service-in",
        "sbp",
        "sbp_low_risk",
        "payment-in"
    )

    $contexts=New-Object System.Collections.Generic.List[object]
    $pages=New-Object System.Collections.Generic.List[object]

    foreach($leaf in $links) {
        $dst=Join-Path $tmp $leaf
        $meta=Invoke-CurlToFile ($docBase+"/"+$leaf) $dst
        $size=0
        if(Test-Path -LiteralPath $dst){$size=(Get-Item -LiteralPath $dst).Length}
        $pages.Add([pscustomobject]@{page=$leaf;http_code=$meta.http_code;curl_exit=$meta.curl_exit;size=$size})

        if($meta.http_code -eq "200" -and Test-Path -LiteralPath $dst) {
            $html=Get-Content -Raw -LiteralPath $dst -Encoding UTF8 -ErrorAction SilentlyContinue
            if($null -ne $html) {
                Add-Contexts $leaf (Html-ToText $html) $needles $contexts
            }
        }
    }

    Save-Json (Join-Path $out "02_pages.json") $pages.ToArray() 8
    Save-Json (Join-Path $out "03_contexts.json") $contexts.ToArray() 12

    $ctxArray=@($contexts.ToArray())
    $routeCandidates=New-Object System.Collections.Generic.List[object]

    foreach($ctx in $ctxArray) {
        $text=[string]$ctx.context
        foreach($m in [Regex]::Matches($text,'/api/[a-z0-9_\-/]+','IgnoreCase')) {
            $route=[string]$m.Value
            if($route -match '(?i)(channel|service|shop|payment|profile|admin)') {
                $routeCandidates.Add([pscustomobject]@{page=$ctx.page;term=$ctx.term;route=$route})
            }
        }
    }

    $routes=@($routeCandidates.ToArray() | Sort-Object route,page,term -Unique)
    Save-Json (Join-Path $out "04_route_candidates.json") $routes 10

    $summary=[ordered]@{
        audit="SBP channel/service public documentation audit"
        timestamp=$stamp
        git_branch=$branch
        git_sha=$sha
        documentation_only=$true
        authentication_used=$false
        working_api_calls=0
        mutating_calls=0
        pages_discovered=$links.Count
        pages_http_200=@($pages.ToArray() | Where-Object {$_.http_code -eq "200"}).Count
        contexts_found=$ctxArray.Count
        route_candidates=$routes
        network_actions="public API documentation GET only"
    }
    Save-Json (Join-Path $out "SUMMARY.json") $summary 16

    $lines=@(
        "SBP channel/service public documentation audit",
        "Timestamp="+$stamp,
        "DocumentationOnly=YES",
        "AuthenticationUsed=NO",
        "WorkingApiCalls=0",
        "MutatingCalls=0",
        "PagesDiscovered="+$links.Count,
        "PagesHTTP200="+$summary.pages_http_200,
        "ContextsFound="+$ctxArray.Count,
        "RouteCandidates="+$routes.Count
    )
    Write-Text (Join-Path $out "SUMMARY.txt") (($lines -join [Environment]::NewLine)+[Environment]::NewLine)

    if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

    Write-Host "[SUCCESS] SBP channel/service documentation audit completed."
    Write-Host ("[REPORT] "+$zip)
    Write-Host ("[DOCS] pages="+$links.Count+" http200="+$summary.pages_http_200+" contexts="+$ctxArray.Count+" routes="+$routes.Count)
    Write-Host "[SAFETY] Public documentation GET only. No authentication or working API calls."
    exit 0
}
finally {
    if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
}
