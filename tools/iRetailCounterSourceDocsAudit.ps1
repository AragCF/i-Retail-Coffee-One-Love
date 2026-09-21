param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $RepoRoot = (Resolve-Path $RepoRoot).Path
}

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw "curl.exe not found in PATH"
}

$docBase = "https://my.i-retail.com/api/apidoc/actual"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$root = Join-Path $RepoRoot "test_reports\s3_counter_sources"
$out = Join-Path $root ("S3_COUNTER_SOURCES_" + $stamp)
$pagesDir = Join-Path $out "pages"
$zip = $out + ".zip"

New-Item -ItemType Directory -Path $pagesDir -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Text([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}

function Invoke-DocGet([string]$Url,[string]$Output) {
    $fmt = "http_code=%{http_code}|content_type=%{content_type}|time_total=%{time_total}|url_effective=%{url_effective}"
    $line = (& curl.exe --silent --show-error --location --connect-timeout 15 --max-time 45 --output $Output --write-out $fmt $Url | Out-String).Trim()
    $rc = $LASTEXITCODE
    $meta = [ordered]@{curl_exit=$rc;http_code="";content_type="";time_total="";url_effective=""}
    foreach($part in ($line -split "\|")) {
        if($part -match "^([^=]+)=(.*)$" -and $meta.Contains($matches[1])) {
            $meta[$matches[1]] = $matches[2]
        }
    }
    return [pscustomobject]$meta
}

function Html-ToText([string]$Html) {
    $text = [Regex]::Replace($Html, '(?is)<script.*?</script>', ' ')
    $text = [Regex]::Replace($text, '(?is)<style.*?</style>', ' ')
    $text = [Regex]::Replace($text, '(?is)<[^>]+>', ' ')
    $text = [Net.WebUtility]::HtmlDecode($text)
    return [Regex]::Replace($text, '\s+', ' ').Trim()
}

function Classify-Endpoint([string]$Path) {
    $p = $Path.ToLowerInvariant()
    if ($p -match '/(register|create|open|close|authorize|pay|synchronize|update|delete|remove|set|save)(-|/|$)') {
        return "state_change_name_candidate"
    }
    if ($p -match '/(get|list|info|current|last|status|find|search)(-|/|$)' -or $p -match '/get-') {
        return "read_only_name_candidate"
    }
    return "unknown_name_candidate"
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1)
Write-Text (Join-Path $out "00_git_state.txt") ("Branch=" + $branch + [Environment]::NewLine + "SHA=" + $sha + [Environment]::NewLine)

$indexPath = Join-Path $out "01_index.html"
$indexMeta = Invoke-DocGet ($docBase + "/index.html") $indexPath
Write-Text (Join-Path $out "02_index_http.json") (($indexMeta | ConvertTo-Json -Depth 4) + [Environment]::NewLine)

if ($indexMeta.curl_exit -ne 0 -or $indexMeta.http_code -ne "200") {
    throw "Could not fetch API documentation index"
}

$index = Get-Content -Raw -LiteralPath $indexPath -Encoding UTF8
$hrefs = [Regex]::Matches($index, 'href="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

$pages = @()
foreach($href in $hrefs) {
    $h = [string]$href
    $clean = ($h -replace '^\./','').TrimStart('/')
    if ($clean -match '(?i)^app-controllers-iretail-.*controller\.html$') {
        $pages += $clean
    }
}
$pages = @($pages | Sort-Object -Unique)

Write-Text (Join-Path $out "03_discovered_iretail_pages.txt") (($pages -join [Environment]::NewLine) + [Environment]::NewLine)

if ($pages.Count -eq 0) {
    throw "No iretail controller documentation pages were discovered from index.html"
}

$downloaded = @()
foreach($page in $pages) {
    $url = $docBase.TrimEnd('/') + "/" + $page
    $dst = Join-Path $pagesDir $page
    $meta = Invoke-DocGet $url $dst
    $size = 0
    if(Test-Path -LiteralPath $dst) { $size = (Get-Item -LiteralPath $dst).Length }
    $downloaded += [pscustomobject]@{
        page=$page
        http_code=$meta.http_code
        curl_exit=$meta.curl_exit
        content_type=$meta.content_type
        size=$size
    }
}
Write-Text (Join-Path $out "04_downloaded_pages.json") (($downloaded | ConvertTo-Json -Depth 5) + [Environment]::NewLine)

$counterTerms = @(
    "order_counter",
    "operation_counter",
    "refund_counter",
    "check_counter",
    "counters"
)

$allEndpoints = @()
$hits = @()
$contexts = New-Object System.Collections.Generic.List[string]

Get-ChildItem -LiteralPath $pagesDir -File | ForEach-Object {
    $html = Get-Content -Raw -LiteralPath $_.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
    if($null -eq $html){ return }

    $text = Html-ToText $html
    $endpointMatches = [Regex]::Matches($text, '(?i)/api/iretail/[A-Za-z0-9_./-]+')
    $pageEndpoints = @()

    foreach($em in $endpointMatches) {
        $path = $em.Value.TrimEnd('.',';',',',':',')',']','}')
        $pageEndpoints += [pscustomobject]@{
            path=$path
            index=$em.Index
            classification=(Classify-Endpoint $path)
        }
        $allEndpoints += [pscustomobject]@{
            page=$_.Name
            path=$path
            classification=(Classify-Endpoint $path)
        }
    }

    foreach($term in $counterTerms) {
        $termRegex = New-Object Text.RegularExpressions.Regex(("\b" + [Regex]::Escape($term) + "\b"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $termMatches = $termRegex.Matches($text)
        $limit = [Math]::Min($termMatches.Count, 8)

        for($i = 0; $i -lt $limit; $i++) {
            $m = $termMatches[$i]
            $nearest = $null
            $nearestDistance = [int]::MaxValue

            foreach($ep in $pageEndpoints) {
                $distance = [Math]::Abs([int]$m.Index - [int]$ep.index)
                if($ep.index -le $m.Index) {
                    $distance = [Math]::Floor($distance / 2)
                }
                if($distance -lt $nearestDistance) {
                    $nearestDistance = $distance
                    $nearest = $ep
                }
            }

            $start = [Math]::Max(0,$m.Index - 900)
            $len = [Math]::Min(2200,$text.Length - $start)
            $context = $text.Substring($start,$len)

            $endpointPath = ""
            $classification = "no_endpoint_detected"
            if($null -ne $nearest) {
                $endpointPath = [string]$nearest.path
                $classification = [string]$nearest.classification
            }

            $hits += [pscustomobject]@{
                page=$_.Name
                term=$term
                nearest_endpoint=$endpointPath
                endpoint_name_classification=$classification
                distance=$nearestDistance
            }

            $contexts.Add(
                "PAGE=" + $_.Name +
                " | TERM=" + $term +
                " | ENDPOINT=" + $endpointPath +
                " | CLASS=" + $classification +
                [Environment]::NewLine + $context
            )
        }
    }
}

$uniqueEndpoints = @(
    $allEndpoints |
    Sort-Object page,path -Unique
)
$uniqueHits = @(
    $hits |
    Sort-Object page,term,nearest_endpoint -Unique
)

Write-Text (Join-Path $out "05_all_discovered_endpoints.json") (($uniqueEndpoints | ConvertTo-Json -Depth 6) + [Environment]::NewLine)
Write-Text (Join-Path $out "06_counter_hits.json") (($uniqueHits | ConvertTo-Json -Depth 6) + [Environment]::NewLine)
Write-Text (Join-Path $out "07_counter_contexts.txt") (($contexts -join ([Environment]::NewLine + [Environment]::NewLine + "----" + [Environment]::NewLine + [Environment]::NewLine)) + [Environment]::NewLine)

$readOnlyCandidates = @(
    $uniqueHits |
    Where-Object { $_.endpoint_name_classification -eq "read_only_name_candidate" -and -not [string]::IsNullOrWhiteSpace($_.nearest_endpoint) } |
    Select-Object page,term,nearest_endpoint |
    Sort-Object nearest_endpoint,term -Unique
)
$stateChangeCandidates = @(
    $uniqueHits |
    Where-Object { $_.endpoint_name_classification -eq "state_change_name_candidate" -and -not [string]::IsNullOrWhiteSpace($_.nearest_endpoint) } |
    Select-Object page,term,nearest_endpoint |
    Sort-Object nearest_endpoint,term -Unique
)

Write-Text (Join-Path $out "08_read_only_name_candidates.json") (($readOnlyCandidates | ConvertTo-Json -Depth 5) + [Environment]::NewLine)
Write-Text (Join-Path $out "09_state_change_name_candidates.json") (($stateChangeCandidates | ConvertTo-Json -Depth 5) + [Environment]::NewLine)

$failedPages = @($downloaded | Where-Object { $_.curl_exit -ne 0 -or $_.http_code -ne "200" })
$summary = [ordered]@{
    audit="i-Retail S3 counter source documentation audit"
    timestamp=$stamp
    git_branch=$branch
    git_sha=$sha
    index_http=$indexMeta.http_code
    discovered_iretail_pages=$pages.Count
    downloaded_pages=@($downloaded | Where-Object { $_.http_code -eq "200" }).Count
    failed_pages=$failedPages.Count
    unique_counter_hits=$uniqueHits.Count
    read_only_name_candidates=$readOnlyCandidates.Count
    state_change_name_candidates=$stateChangeCandidates.Count
    network_actions="documentation GET only"
    working_api_calls=0
    device_register_called=$false
    order_synchronize_called=$false
}
Write-Text (Join-Path $out "SUMMARY.json") (($summary | ConvertTo-Json -Depth 6) + [Environment]::NewLine)
Write-Text (Join-Path $out "SUMMARY.txt") ((@(
    "i-Retail S3 counter source documentation audit",
    "Timestamp=" + $stamp,
    "GitBranch=" + $branch,
    "GitSHA=" + $sha,
    "IndexHTTP=" + $indexMeta.http_code,
    "DiscoveredIRetailPages=" + $pages.Count,
    "DownloadedPages=" + @($downloaded | Where-Object { $_.http_code -eq "200" }).Count,
    "FailedPages=" + $failedPages.Count,
    "UniqueCounterHits=" + $uniqueHits.Count,
    "ReadOnlyNameCandidates=" + $readOnlyCandidates.Count,
    "StateChangeNameCandidates=" + $stateChangeCandidates.Count,
    "NetworkActions=DOCUMENTATION_GET_ONLY",
    "WorkingApiCalls=0",
    "DeviceRegisterCalled=NO",
    "OrderSynchronizeCalled=NO"
) -join [Environment]::NewLine) + [Environment]::NewLine)

if($failedPages.Count -gt 0) {
    Write-Text (Join-Path $out "10_failed_pages.json") (($failedPages | ConvertTo-Json -Depth 5) + [Environment]::NewLine)
}

if(Test-Path -LiteralPath $zip){ Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

Write-Host "[SUCCESS] S3 counter-source documentation audit completed."
Write-Host ("[REPORT] " + $zip)
Write-Host ("[PAGES] discovered=" + $pages.Count + " downloaded=" + @($downloaded | Where-Object { $_.http_code -eq "200" }).Count)
Write-Host ("[COUNTER HITS] " + $uniqueHits.Count)
Write-Host ("[READ-ONLY NAME CANDIDATES] " + $readOnlyCandidates.Count)
Write-Host ("[STATE-CHANGE NAME CANDIDATES] " + $stateChangeCandidates.Count)
exit 0
