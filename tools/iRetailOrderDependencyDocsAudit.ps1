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
$root = Join-Path $RepoRoot "test_reports\s3_order_dependencies"
$out = Join-Path $root ("S3_ORDER_DEPS_" + $stamp)
$zip = $out + ".zip"
$pagesDir = Join-Path $out "pages"

New-Item -ItemType Directory -Path $pagesDir -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Text([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}

function Invoke-CurlToFile([string]$Url,[string]$Output) {
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

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1)
Write-Text (Join-Path $out "00_git_state.txt") ("Branch=" + $branch + [Environment]::NewLine + "SHA=" + $sha + [Environment]::NewLine)

$pages = @(
    "app-controllers-iretail-devicecontroller.html",
    "app-controllers-iretail-shiftcontroller.html",
    "app-controllers-iretail-employeecontroller.html",
    "app-controllers-iretail-operationcontroller.html",
    "app-controllers-iretail-paymentincontroller.html",
    "app-controllers-iretail-channelcontroller.html",
    "app-controllers-iretail-offercontroller.html",
    "app-controllers-iretail-catalogcontroller.html",
    "app-controllers-iretail-taxcontroller.html",
    "app-controllers-referencecontroller.html",
    "app-controllers-serviceincontroller.html"
)

$downloaded = @()
foreach($name in $pages) {
    $url = $docBase + "/" + $name
    $dst = Join-Path $pagesDir $name
    $meta = Invoke-CurlToFile $url $dst
    $size = 0
    if(Test-Path -LiteralPath $dst) { $size = (Get-Item -LiteralPath $dst).Length }
    $downloaded += [pscustomobject]@{
        page=$name
        http_code=$meta.http_code
        curl_exit=$meta.curl_exit
        content_type=$meta.content_type
        size=$size
    }
}
Write-Text (Join-Path $out "01_downloaded_pages.json") (($downloaded | ConvertTo-Json -Depth 5) + [Environment]::NewLine)

$needles = @(
    "employee_id",
    "shift_id",
    "check_counter",
    "order_status_id",
    "payment_status_id",
    "service_in_slug",
    "order_counter",
    "operation_counter",
    "refund_counter",
    "device_id",
    "series_id",
    "order_number",
    "short_number",
    "number_to_day",
    "type_id",
    "unit_id",
    "tax_rate",
    "tax_included_in_price",
    "tax_number_in_printer",
    "currency_id",
    "uuid",
    "commit_time",
    "status_history",
    "payment_status_history"
)

$matches = New-Object System.Collections.Generic.List[object]
$contexts = New-Object System.Collections.Generic.List[string]

Get-ChildItem -LiteralPath $pagesDir -File | ForEach-Object {
    $html = Get-Content -Raw -LiteralPath $_.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
    if($null -eq $html){ return }
    $text = Html-ToText $html
    foreach($needle in $needles) {
        $regex = New-Object Text.RegularExpressions.Regex(("\b" + [Regex]::Escape($needle) + "\b"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $m = $regex.Match($text)
        if($m.Success) {
            $matches.Add([pscustomobject]@{page=$_.Name;term=$needle})
            $start = [Math]::Max(0,$m.Index - 450)
            $len = [Math]::Min(1400,$text.Length - $start)
            $contexts.Add(($_.Name + " | " + $needle + " | " + $text.Substring($start,$len)))
        }
    }
}

Write-Text (Join-Path $out "02_keyword_matches.json") (($matches | ConvertTo-Json -Depth 4) + [Environment]::NewLine)
Write-Text (Join-Path $out "03_keyword_contexts.txt") (($contexts -join ([Environment]::NewLine + [Environment]::NewLine)) + [Environment]::NewLine)

$failedPages = @($downloaded | Where-Object { $_.curl_exit -ne 0 -or $_.http_code -ne "200" })
$summary = [ordered]@{
    audit = "i-Retail S3 order dependency documentation audit"
    timestamp = $stamp
    git_branch = $branch
    git_sha = $sha
    requested_pages = $pages.Count
    downloaded_pages = @($downloaded | Where-Object { $_.http_code -eq "200" }).Count
    failed_pages = $failedPages.Count
    keyword_matches = $matches.Count
    network_actions = "documentation GET only"
    order_send_allowed = $false
}
Write-Text (Join-Path $out "SUMMARY.json") (($summary | ConvertTo-Json -Depth 5) + [Environment]::NewLine)
Write-Text (Join-Path $out "SUMMARY.txt") ((@(
    "i-Retail S3 order dependency documentation audit",
    "Timestamp=" + $stamp,
    "GitBranch=" + $branch,
    "GitSHA=" + $sha,
    "RequestedPages=" + $pages.Count,
    "DownloadedPages=" + @($downloaded | Where-Object { $_.http_code -eq "200" }).Count,
    "FailedPages=" + $failedPages.Count,
    "KeywordMatches=" + $matches.Count,
    "OrderSendAllowed=NO"
) -join [Environment]::NewLine) + [Environment]::NewLine)

if($failedPages.Count -gt 0) {
    Write-Text (Join-Path $out "04_failed_pages.json") (($failedPages | ConvertTo-Json -Depth 5) + [Environment]::NewLine)
}

if(Test-Path -LiteralPath $zip){ Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

Write-Host "[SUCCESS] S3 order dependency documentation audit completed."
Write-Host ("[REPORT] " + $zip)
Write-Host ("[PAGES] " + @($downloaded | Where-Object { $_.http_code -eq "200" }).Count + "/" + $pages.Count)
Write-Host ("[MATCHES] " + $matches.Count)
exit 0
