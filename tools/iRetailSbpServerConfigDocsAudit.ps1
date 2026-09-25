param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $RepoRoot = (Resolve-Path $RepoRoot).Path
}

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw "curl.exe not found"
}

$docBase = "https://my.i-retail.com/api/apidoc/actual"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$root = Join-Path $RepoRoot "test_reports\sbp_server_config_docs"
$out = Join-Path $root ("SBP_SERVER_CONFIG_DOCS_" + $stamp)
$pagesDir = Join-Path $out "pages"
$zip = $out + ".zip"

New-Item -ItemType Directory -Path $out -Force | Out-Null
New-Item -ItemType Directory -Path $pagesDir -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Text([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}

function Save-Json([string]$Path,$Value,[int]$Depth = 16) {
    Write-Text $Path (($Value | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine)
}

function Invoke-Doc([string]$Name) {
    $dst = Join-Path $pagesDir $Name
    $fmt = "http_code=%{http_code}|content_type=%{content_type}|time_total=%{time_total}|url_effective=%{url_effective}"
    $line = (& curl.exe --silent --show-error --location --connect-timeout 15 --max-time 45 --output $dst --write-out $fmt ($docBase + "/" + $Name) | Out-String).Trim()
    $rc = $LASTEXITCODE

    $meta=[ordered]@{page=$Name;curl_exit=$rc;http_code="";content_type="";time_total="";url_effective="";size=0}
    foreach($part in ($line -split "\|")) {
        if($part -match "^([^=]+)=(.*)$" -and $meta.Contains($matches[1])){$meta[$matches[1]]=$matches[2]}
    }
    if(Test-Path -LiteralPath $dst){$meta.size=(Get-Item -LiteralPath $dst).Length}
    return [pscustomobject]$meta
}

function Html-ToText([string]$Html) {
    $text=[Regex]::Replace($Html,'(?is)<script.*?</script>',' ')
    $text=[Regex]::Replace($text,'(?is)<style.*?</style>',' ')
    $text=[Regex]::Replace($text,'(?is)<[^>]+>',' ')
    $text=[Net.WebUtility]::HtmlDecode($text)
    return [Regex]::Replace($text,'\s+',' ').Trim()
}

function Add-Contexts([string]$Page,[string]$Text,[string[]]$Needles,[System.Collections.Generic.List[string]]$Target) {
    foreach($needle in $Needles) {
        $startAt=0
        $count=0
        while($count -lt 12) {
            $idx=$Text.IndexOf($needle,$startAt,[StringComparison]::OrdinalIgnoreCase)
            if($idx -lt 0){break}
            $start=[Math]::Max(0,$idx-1000)
            $len=[Math]::Min(3600,$Text.Length-$start)
            $Target.Add(($Page+" | "+$needle+" | "+$Text.Substring($start,$len)))
            $startAt=$idx+[Math]::Max(1,$needle.Length)
            $count++
        }
    }
}

function Extract-MethodList([string]$Page,[string]$Text) {
    $result=New-Object System.Collections.Generic.List[object]
    $rx=[Regex]'(?i)(/api/[a-z0-9_\-/]+)'
    foreach($m in $rx.Matches($Text)) {
        $route=$m.Groups[1].Value
        if($route -match '(?i)(channel|shop|service|profile|trade-point|payment-in|pipo)') {
            $result.Add([pscustomobject]@{page=$Page;route=$route})
        }
    }
    return $result.ToArray()
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1).Trim()
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1).Trim()
Write-Text (Join-Path $out "00_git_state.txt") ("Branch="+$branch+[Environment]::NewLine+"SHA="+$sha+[Environment]::NewLine)

# Candidate controller pages from the current navigation tree.
$pages=@(
    "app-controllers-admin-channelcontroller.html",
    "app-controllers-admin-serviceincontroller.html",
    "app-controllers-admin-servicecontroller.html",
    "app-controllers-admin-onlineshopcontroller.html",
    "app-controllers-admin-tradepointcontroller.html",
    "app-controllers-admin-profilecontroller.html",
    "app-controllers-admin-profilesettingscontroller.html",
    "app-controllers-admin-settingcontroller.html",
    "app-controllers-channelcontroller.html",
    "app-controllers-onlineshopcontroller.html",
    "app-controllers-tradepointcontroller.html",
    "app-controllers-serviceincontroller.html",
    "app-controllers-iretail-channelcontroller.html",
    "app-controllers-iretail-paymentincontroller.html",
    "app-controllers-iretail-pipo-inputcontroller.html"
)

$needles=@(
    "verify",
    "verified",
    "verification",
    "enable",
    "enabled",
    "disable",
    "active",
    "service_in",
    "service-in",
    "service group",
    "groups",
    "shop",
    "online shop",
    "offline_shop",
    "offline shop",
    "lock_service",
    "PayIn-PayOut",
    "sbp",
    "sbp_low_risk",
    "process_input",
    "create",
    "update",
    "save",
    "edit",
    "attach",
    "bind",
    "activate"
)

$pageResults=@()
$contexts=New-Object System.Collections.Generic.List[string]
$routes=New-Object System.Collections.Generic.List[object]

foreach($page in $pages) {
    $meta=Invoke-Doc $page
    $pageResults += $meta

    if($meta.curl_exit -eq 0 -and $meta.http_code -eq "200") {
        $path=Join-Path $pagesDir $page
        $html=Get-Content -Raw -LiteralPath $path -Encoding UTF8 -ErrorAction SilentlyContinue
        if($null -ne $html) {
            $text=Html-ToText $html
            Add-Contexts $page $text $needles $contexts
            foreach($route in (Extract-MethodList $page $text)){$routes.Add($route)}
        }
    }
}

Save-Json (Join-Path $out "01_pages.json") $pageResults 8
Write-Text (Join-Path $out "02_contexts.txt") (($contexts -join ([Environment]::NewLine+[Environment]::NewLine))+[Environment]::NewLine)

$uniqueRoutes=@($routes.ToArray() | Sort-Object page,route -Unique)
Save-Json (Join-Path $out "03_routes.json") $uniqueRoutes 8

$mutatingCandidates=@($uniqueRoutes | Where-Object {
    $_.route -match '(?i)/(create|update|save|edit|delete|enable|disable|verify|activate|bind|attach)(/|$|-)' -or
    $_.route -match '(?i)(shop|service).*(create|update|save|edit|enable|verify)'
})
Save-Json (Join-Path $out "04_mutating_candidates.json") $mutatingCandidates 8

$successful=@($pageResults | Where-Object {$_.http_code -eq "200"})
$summary=[ordered]@{
    audit="SBP server configuration documentation audit"
    timestamp=$stamp
    git_branch=$branch
    git_sha=$sha
    network_actions="public API documentation GET only"
    authenticated_calls=0
    financial_mutation=$false
    config_mutation=$false
    requested_pages=$pages.Count
    successful_pages=$successful.Count
    routes_found=$uniqueRoutes.Count
    mutating_candidates=$mutatingCandidates.Count
}
Save-Json (Join-Path $out "SUMMARY.json") $summary 8

$summaryLines=@(
    "SBP server configuration documentation audit",
    "Timestamp="+$stamp,
    "PublicDocsOnly=YES",
    "AuthenticatedCalls=0",
    "FinancialMutation=NO",
    "ConfigMutation=NO",
    "RequestedPages="+$pages.Count,
    "SuccessfulPages="+$successful.Count,
    "RoutesFound="+$uniqueRoutes.Count,
    "MutatingCandidates="+$mutatingCandidates.Count
)
Write-Text (Join-Path $out "SUMMARY.txt") (($summaryLines -join [Environment]::NewLine)+[Environment]::NewLine)

if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

Write-Host "[SUCCESS] SBP server configuration documentation audit completed."
Write-Host ("[REPORT] "+$zip)
Write-Host ("[DOCS] successful="+$successful.Count+"/"+$pages.Count+" routes="+$uniqueRoutes.Count+" mutationCandidates="+$mutatingCandidates.Count)
Write-Host "[SAFETY] Public documentation GET only. No authenticated or mutating API calls."
exit 0
