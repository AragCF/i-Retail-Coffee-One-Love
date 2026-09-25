param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$ArtifactPath,
    [string]$CommitPrefix = "test: auto-publish artifact"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$repo = (Resolve-Path $RepoRoot).Path
$artifact = (Resolve-Path $ArtifactPath).Path

if (-not ($artifact.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))) {
    throw "Artifact is outside repository: $artifact"
}

$branch = (& git -C $repo branch --show-current | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) { throw "Detached HEAD is not allowed for artifact publication" }

& git -C $repo diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    throw "Git index already contains staged changes. Refusing to mix them with an artifact commit."
}

$relative = $artifact.Substring($repo.Length).TrimStart([char[]]"\/")
$shaPath = $artifact + ".sha256.txt"
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($shaPath,("SHA256=" + $hash + [Environment]::NewLine),(New-Object System.Text.UTF8Encoding($false)))
$shaRelative = $shaPath.Substring($repo.Length).TrimStart([char[]]"\/")

& git -C $repo add -- $relative $shaRelative
if ($LASTEXITCODE -ne 0) { throw "git add failed" }

$staged = @(& git -C $repo diff --cached --name-only)
$allowed = @($relative.Replace("\","/"),$shaRelative.Replace("\","/"))
$unexpected = @($staged | Where-Object { $allowed -notcontains ([string]$_).Replace("\","/") })
if ($unexpected.Count -gt 0) {
    & git -C $repo reset -- $relative $shaRelative | Out-Null
    throw ("Unexpected staged paths: " + ($unexpected -join ", "))
}

& git -C $repo diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "[GIT] Artifact is already committed with identical content."
} else {
    $name = [IO.Path]::GetFileName($artifact)
    $message = ($CommitPrefix.Trim() + " " + $name).Trim()
    & git -C $repo commit -m $message
    if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
}

& git -C $repo push origin ("HEAD:" + $branch)
if ($LASTEXITCODE -ne 0) {
    throw "git push failed. Artifact commit remains local on branch $branch."
}

$commit = (& git -C $repo rev-parse HEAD | Select-Object -First 1).Trim()
Write-Host "[GIT] AUTO_PUBLISH_OK"
Write-Host ("[GIT] Branch: " + $branch)
Write-Host ("[GIT] Commit: " + $commit)
Write-Host ("[GIT] Artifact: " + $relative)
Write-Host ("[GIT] SHA256: " + $hash)
exit 0
