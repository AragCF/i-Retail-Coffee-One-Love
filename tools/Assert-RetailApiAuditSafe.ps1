param(
    [Parameter(Mandatory=$true)][string]$ZipPath,
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $RepoRoot = (Resolve-Path $RepoRoot).Path
}

$ZipPath = (Resolve-Path $ZipPath).Path
$configPath = Join-Path $RepoRoot "app\src\main\assets\content\iretail-api.json"
$config = Get-Content -Raw -LiteralPath $configPath -Encoding UTF8 | ConvertFrom-Json
$secrets = @([string]$config.login,[string]$config.password,[string]$config.client_secret) |
    Where-Object { -not [string]::IsNullOrEmpty($_) } |
    Select-Object -Unique

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
$violations = @()
try {
    $names = @($archive.Entries | ForEach-Object { $_.FullName })
    foreach ($forbidden in @("auth_raw.json","auth.form","catalog.form","access_token.txt","iretail-api.json")) {
        if ($names -contains $forbidden) { $violations += ("forbidden entry: " + $forbidden) }
    }

    foreach ($entry in $archive.Entries) {
        $ext = [IO.Path]::GetExtension($entry.FullName)
        if ($ext -notmatch "^\.(txt|json|html|js|md)$") { continue }
        $stream = $entry.Open()
        try {
            $reader = New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true)
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $stream.Dispose() }

        foreach ($secret in $secrets) {
            if ($text.Contains($secret)) {
                $violations += ("configured secret found in " + $entry.FullName)
                break
            }
        }

        if ($entry.FullName -notlike "docs/*") {
            if ($text -match '(?i)"access_token"\s*:\s*"[^"]{8,}"') {
                $violations += ("access token value found in " + $entry.FullName)
            }
            if ($text -match '(?i)authorization\s*:\s*bearer\s+\S+') {
                $violations += ("bearer token found in " + $entry.FullName)
            }
        }
    }
}
finally {
    $archive.Dispose()
}

if ($violations.Count -gt 0) {
    Write-Host "[ERROR] Retail API audit safety scan failed."
    $violations | Select-Object -Unique | ForEach-Object { Write-Host ("  " + $_) }
    exit 40
}

Write-Host "[OK] Retail API audit safety scan passed."
exit 0
