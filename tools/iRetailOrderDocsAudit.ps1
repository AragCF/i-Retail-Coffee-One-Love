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
$root = Join-Path $RepoRoot "test_reports\s3_order_contract"
$out = Join-Path $root ("S3_ORDER_DOCS_" + $stamp)
$zip = $out + ".zip"
New-Item -ItemType Directory -Path $out -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $out "pages") -Force | Out-Null

$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Text([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}

function Curl([string]$Url,[string]$Output) {
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

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1)
Write-Text (Join-Path $out "00_git_state.txt") ("Branch=" + $branch + [Environment]::NewLine + "SHA=" + $sha + [Environment]::NewLine)

$indexPath = Join-Path $out "index.html"
$indexMeta = Curl ($docBase + "/index.html") $indexPath
Write-Text (Join-Path $out "01_index_http.json") (($indexMeta | ConvertTo-Json -Depth 4) + [Environment]::NewLine)
if ($indexMeta.curl_exit -ne 0 -or $indexMeta.http_code -ne "200") {
    throw "Could not fetch API documentation index"
}

$index = Get-Content -Raw -LiteralPath $indexPath -Encoding UTF8
$hrefs = [Regex]::Matches($index, 'href="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

$candidates = @()
foreach($href in $hrefs) {
    $h = [string]$href
    if ($h -match '(?i)ordercontroller\.html$' -or $h -match '(?i)iretail.*order.*\.html$') {
        $candidates += $h
    }
}
$candidates = @($candidates | Sort-Object -Unique)

Write-Text (Join-Path $out "02_candidate_pages.txt") (($candidates -join [Environment]::NewLine) + [Environment]::NewLine)

$downloaded = @()
foreach($href in $candidates) {
    $cleanName = ($href -replace '^\./','') -replace '[^A-Za-z0-9._-]','_'
    $dst = Join-Path (Join-Path $out "pages") $cleanName
    if ($href -match '^https?://') {
        $url = $href
    } else {
        $relative = $href -replace '^\./',''
        $relative = $relative.TrimStart('/')
        $url = $docBase.TrimEnd('/') + "/" + $relative
    }
    $meta = Curl $url $dst
    $pageSize = 0
    if (Test-Path -LiteralPath $dst) {
        $pageSize = (Get-Item -LiteralPath $dst).Length
    }
    $downloaded += [pscustomobject]@{
        href = $href
        file = $cleanName
        http_code = $meta.http_code
        curl_exit = $meta.curl_exit
        content_type = $meta.content_type
        size = $pageSize
    }
}

Write-Text (Join-Path $out "03_downloaded_pages.json") (($downloaded | ConvertTo-Json -Depth 5) + [Environment]::NewLine)

$needles = @(
    "reserve-order-id",
    "synchronize",
    "employee_id",
    "pin",
    "channel_id",
    "currency_id",
    "offer_id",
    "quantity",
    "price",
    "idempot",
    "retry",
    "status",
    "products"
)

$matchesOut = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath (Join-Path $out "pages") -File | ForEach-Object {
    $text = Get-Content -Raw -LiteralPath $_.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
    if($null -eq $text){ return }
    foreach($needle in $needles) {
        if($text -match [Regex]::Escape($needle)) {
            $matchesOut.Add(($_.Name + ": " + $needle))
        }
    }
}
Write-Text (Join-Path $out "04_keyword_matches.txt") (($matchesOut -join [Environment]::NewLine) + [Environment]::NewLine)

$summary = [ordered]@{
    audit = "i-Retail S3 order contract documentation audit"
    timestamp = $stamp
    git_branch = $branch
    git_sha = $sha
    index_http = $indexMeta.http_code
    candidate_pages = $candidates.Count
    downloaded_pages = @($downloaded | Where-Object { $_.http_code -eq "200" }).Count
    keywords_found = $matchesOut.Count
    network_actions = "documentation GET only"
    order_send_allowed = $false
}
Write-Text (Join-Path $out "SUMMARY.json") (($summary | ConvertTo-Json -Depth 5) + [Environment]::NewLine)
Write-Text (Join-Path $out "SUMMARY.txt") (@(
    "i-Retail S3 order contract documentation audit",
    "Timestamp=" + $stamp,
    "GitBranch=" + $branch,
    "GitSHA=" + $sha,
    "IndexHTTP=" + $indexMeta.http_code,
    "CandidatePages=" + $candidates.Count,
    "DownloadedPages=" + @($downloaded | Where-Object { $_.http_code -eq "200" }).Count,
    "KeywordMatches=" + $matchesOut.Count,
    "OrderSendAllowed=NO"
) -join [Environment]::NewLine)

if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

Write-Host "[SUCCESS] S3 order API documentation audit completed."
Write-Host ("[REPORT] " + $zip)
Write-Host ("[PAGES] candidates=" + $candidates.Count + " downloaded=" + @($downloaded | Where-Object { $_.http_code -eq "200" }).Count)
Write-Host ("[MATCHES] " + $matchesOut.Count)
exit 0
