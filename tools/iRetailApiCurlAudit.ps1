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
$root = Join-Path $RepoRoot "test_reports\retail_api_curl"
$out = Join-Path $root ("RAPI_CURL_" + $stamp)
$zip = $out + ".zip"
$tmp = Join-Path $env:TEMP ("iretail_rapi_" + $stamp + "_" + $PID)
New-Item -ItemType Directory -Path $out -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $out "docs") -Force | Out-Null
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

function Redact([string]$Text) {
    if ($null -eq $Text) { return "" }
    $r = $Text
    foreach ($s in @([string]$config.login,[string]$config.password,[string]$config.client_secret)) {
        if (-not [string]::IsNullOrEmpty($s)) { $r = $r.Replace($s,"[REDACTED]") }
    }
    return $r
}

function Curl-ToFile([string]$Url,[string]$Output,[string[]]$Extra) {
    $err = Join-Path $tmp ("curl_" + [Guid]::NewGuid().ToString("N") + ".err")
    $fmt = "http_code=%{http_code}|content_type=%{content_type}|time_total=%{time_total}|remote_ip=%{remote_ip}|url_effective=%{url_effective}"
    $args = @("--silent","--show-error","--location","--connect-timeout","15","--max-time","45","--output",$Output,"--write-out",$fmt)
    if ($null -ne $Extra) { $args += $Extra }
    $args += $Url
    $line = (& curl.exe @args 2> $err | Out-String).Trim()
    $rc = $LASTEXITCODE
    $stderr = ""
    if (Test-Path -LiteralPath $err) {
        $stderr = Redact (Get-Content -Raw -LiteralPath $err -ErrorAction SilentlyContinue)
        Remove-Item -LiteralPath $err -Force -ErrorAction SilentlyContinue
    }
    $m = [ordered]@{ curl_exit=$rc; http_code=""; content_type=""; time_total=""; remote_ip=""; url_effective=""; stderr=$stderr.Trim() }
    foreach ($part in ($line -split "\|")) {
        if ($part -match "^([^=]+)=(.*)$" -and $m.Contains($matches[1])) { $m[$matches[1]] = $matches[2] }
    }
    return [pscustomobject]$m
}

function Save-Meta([string]$Path,$Meta) {
    Write-Text $Path (($Meta | ConvertTo-Json -Depth 4) + [Environment]::NewLine)
}

$branch = (& git -C $RepoRoot branch --show-current | Select-Object -First 1)
$sha = (& git -C $RepoRoot rev-parse HEAD | Select-Object -First 1)

try {
    Write-Text (Join-Path $out "00_git_state.txt") ("Branch=" + $branch + [Environment]::NewLine + "SHA=" + $sha + [Environment]::NewLine)

    $safeConfig = [ordered]@{
        enabled=[bool]$config.enabled
        base_url=[string]$config.base_url
        client_id=[string]$config.client_id
        profile_id=[string]$config.profile_id
        channel_id=[string]$config.channel_id
        currency_id=[string]$config.currency_id
        device_code=[string]$config.device_code
        device_id=[string]$config.device_id
        login_present=(-not [string]::IsNullOrWhiteSpace([string]$config.login))
        password_present=(-not [string]::IsNullOrWhiteSpace([string]$config.password))
        client_secret_present=(-not [string]::IsNullOrWhiteSpace([string]$config.client_secret))
    }
    Write-Text (Join-Path $out "01_config_sanitized.json") (($safeConfig | ConvertTo-Json -Depth 4) + [Environment]::NewLine)

    $contract = @(
        "Documentation: " + $docBase + "/index.html",
        "AUTH POST user/authentication",
        "AUTH Content-Type application/x-www-form-urlencoded",
        "AUTH fields username,password,client_id,client_secret",
        "AUTH consumed response result.access_token",
        "CATALOG POST iretail/catalog/download-actual-zip",
        "CATALOG Content-Type application/x-www-form-urlencoded",
        "CATALOG fields client_id,client_secret,access_token,channel_id",
        "No order, loyalty, payment or fiscal request is sent."
    )
    Write-Text (Join-Path $out "02_APP_REQUEST_CONTRACT.txt") (($contract -join [Environment]::NewLine) + [Environment]::NewLine)

    $docInfo = @()
    foreach ($name in @("index.html","api_data.js","api_project.js")) {
        $url = $docBase + "/" + $name
        $dst = Join-Path (Join-Path $out "docs") $name
        $meta = Curl-ToFile $url $dst @()
        Save-Meta ($dst + ".http.json") $meta
        $docSize = 0
        if (Test-Path -LiteralPath $dst) {
            $docSize = (Get-Item -LiteralPath $dst).Length
        }
        $docInfo += [pscustomobject]@{
            name = $name
            http_code = $meta.http_code
            curl_exit = $meta.curl_exit
            size = $docSize
        }
    }

    $hits = @()
    foreach ($name in @("index.html","api_data.js","api_project.js")) {
        $p = Join-Path (Join-Path $out "docs") $name
        if (Test-Path $p) {
            $t = Get-Content -Raw -LiteralPath $p -ErrorAction SilentlyContinue
            foreach ($needle in @("user/authentication","iretail/catalog/download-actual-zip","channel_id","client_secret","access_token")) {
                if ($null -ne $t -and $t.Contains($needle)) { $hits += ($name + ": " + $needle) }
            }
        }
    }
    Write-Text (Join-Path $out "03_documentation_matches.txt") (($hits -join [Environment]::NewLine) + [Environment]::NewLine)

    $authForm = Join-Path $tmp "auth.form"
    Write-Text $authForm (Encode-Form @{username=[string]$config.login;password=[string]$config.password;client_id=[string]$config.client_id;client_secret=[string]$config.client_secret})
    $authRaw = Join-Path $tmp "auth.json"
    $authMeta = Curl-ToFile ($baseUrl + "user/authentication") $authRaw @("--request","POST","--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8","--header","Accept: application/json, application/zip, */*","--data-binary",("@" + $authForm))
    Save-Meta (Join-Path $out "10_auth_http.json") $authMeta

    $apiStatus = $false
    $token = ""
    $title = ""
    $parseError = ""
    if (Test-Path $authRaw) {
        try {
            $ao = Get-Content -Raw -LiteralPath $authRaw -Encoding UTF8 | ConvertFrom-Json
            $apiStatus = [bool]$ao.status
            if ($null -ne $ao.result) {
                if ($null -ne $ao.result.access_token) { $token = [string]$ao.result.access_token }
                if ($null -ne $ao.result.title) { $title = Redact ([string]$ao.result.title) }
            }
        } catch { $parseError = $_.Exception.GetType().Name }
    }
    $authSafe = [ordered]@{http_code=$authMeta.http_code;curl_exit=$authMeta.curl_exit;api_status=$apiStatus;token_present=(-not [string]::IsNullOrWhiteSpace($token));title=$title;parse_error=$parseError}
    Write-Text (Join-Path $out "11_auth_response_sanitized.json") (($authSafe | ConvertTo-Json -Depth 4) + [Environment]::NewLine)

    $catMeta = $null
    $catZip = $false
    $catSha = ""
    $catSize = 0
    $catPath = Join-Path $out "21_catalog.zip"
    if (-not [string]::IsNullOrWhiteSpace($token)) {
        $catForm = Join-Path $tmp "catalog.form"
        Write-Text $catForm (Encode-Form @{client_id=[string]$config.client_id;client_secret=[string]$config.client_secret;access_token=$token;channel_id=[string]$config.channel_id})
        $catRaw = Join-Path $tmp "catalog.raw"
        $catMeta = Curl-ToFile ($baseUrl + "iretail/catalog/download-actual-zip") $catRaw @("--request","POST","--header","Content-Type: application/x-www-form-urlencoded; charset=UTF-8","--header","Accept: application/json, application/zip, */*","--data-binary",("@" + $catForm))
        Save-Meta (Join-Path $out "20_catalog_http.json") $catMeta
        if (Test-Path $catRaw) {
            $catSize = (Get-Item $catRaw).Length
            if ($catSize -ge 4) {
                $b = [IO.File]::ReadAllBytes($catRaw)
                $catZip = ($b[0] -eq 0x50 -and $b[1] -eq 0x4B)
            }
        }
        if ($catZip) {
            Copy-Item -LiteralPath $catRaw -Destination $catPath -Force
            $catSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $catPath).Hash.ToLowerInvariant()
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $a = [IO.Compression.ZipFile]::OpenRead($catPath)
            try {
                $list = @($a.Entries | ForEach-Object { [pscustomobject]@{name=$_.FullName;compressed_length=$_.CompressedLength;length=$_.Length} })
                Write-Text (Join-Path $out "22_catalog_entries.json") (($list | ConvertTo-Json -Depth 4) + [Environment]::NewLine)
            } finally { $a.Dispose() }
        } else {
            $errText = ""
            try { $errText = Redact (Get-Content -Raw -LiteralPath $catRaw -Encoding UTF8) } catch { $errText = "non_text_response" }
            if ($errText.Length -gt 2000) { $errText = $errText.Substring(0,2000) }
            Write-Text (Join-Path $out "21_catalog_error_sanitized.txt") ($errText + [Environment]::NewLine)
        }
    } else {
        $catMeta = [pscustomobject][ordered]@{curl_exit=-1;http_code="";content_type="";time_total="";remote_ip="";url_effective="";stderr="skipped: no access token"}
        Save-Meta (Join-Path $out "20_catalog_http.json") $catMeta
        Write-Text (Join-Path $out "21_catalog_error_sanitized.txt") ("skipped: no access token" + [Environment]::NewLine)
    }

    Write-Text (Join-Path $out "30_curl_version.txt") ((& curl.exe --version | Out-String))
    $summary = [ordered]@{
        audit="i-Retail v0.5.42 Windows curl API audit"
        timestamp=$stamp
        git_branch=$branch
        git_sha=$sha
        docs=$docInfo
        auth_http_code=$authMeta.http_code
        auth_curl_exit=$authMeta.curl_exit
        auth_api_status=$apiStatus
        auth_token_present=(-not [string]::IsNullOrWhiteSpace($token))
        catalog_http_code=$catMeta.http_code
        catalog_curl_exit=$catMeta.curl_exit
        catalog_is_zip=$catZip
        catalog_sha256=$catSha
        catalog_size=$catSize
        secrets_written=$false
    }
    Write-Text (Join-Path $out "SUMMARY.json") (($summary | ConvertTo-Json -Depth 6) + [Environment]::NewLine)

    $summaryLines = @(
        "i-Retail v0.5.42 Windows curl API audit",
        "GitBranch=" + $branch,
        "GitSHA=" + $sha,
        "AuthHTTP=" + $authMeta.http_code,
        "AuthApiStatus=" + $apiStatus,
        "AuthTokenPresent=" + (-not [string]::IsNullOrWhiteSpace($token)),
        "CatalogHTTP=" + $catMeta.http_code,
        "CatalogIsZip=" + $catZip,
        "CatalogSHA256=" + $catSha,
        "CatalogSize=" + $catSize
    )
    Write-Text (Join-Path $out "SUMMARY.txt") (($summaryLines -join [Environment]::NewLine) + [Environment]::NewLine)

    $secretValues = @([string]$config.login,[string]$config.password,[string]$config.client_secret) | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique
    $unsafe = @()
    Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object { $_.Extension -match "^\.(txt|json|html|js)$" } | ForEach-Object {
        $content = Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue
        foreach ($secret in $secretValues) {
            if ($null -ne $content -and $content.Contains($secret)) { $unsafe += $_.FullName; break }
        }
    }
    if ($unsafe.Count -gt 0) { throw "Safety scan failed: secret-like value found in report" }

    if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force
    Write-Host "[SUCCESS] Retail API curl audit completed."
    Write-Host ("[REPORT] " + $zip)
    Write-Host ("[AUTH] HTTP=" + $authMeta.http_code + " status=" + $apiStatus + " token=" + (-not [string]::IsNullOrWhiteSpace($token)))
    Write-Host ("[CATALOG] HTTP=" + $catMeta.http_code + " zip=" + $catZip + " size=" + $catSize)
    exit 0
}
finally {
    if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
