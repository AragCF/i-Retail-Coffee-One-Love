@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "COL_SELF=%~f0"
set "COL_ROOT=%~1"
rem The complete block is parsed before Git can update a running copy.
(
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $s=[IO.File]::ReadAllText($env:COL_SELF,[Text.Encoding]::GetEncoding(866)); $b=[regex]::Split($s,'(?m)^:__COL_BOOTSTRAP_PS__\r?$'); if($b.Count -ne 2){throw 'BAD_LAUNCHER'}; & ([scriptblock]::Create($b[1])) } catch { Write-Host ('[START_FAILED] '+$_.Exception.Message); exit 1 }"
  call set "COL_EXIT=%%errorlevel%%"
  echo.
  if not defined COL_NO_PAUSE pause
  call exit /b %%COL_EXIT%%
)
:__COL_BOOTSTRAP_PS__
# Launcher protocol 1; version 1.0.0. ASCII is a subset of OEM CP866.
$ErrorActionPreference='Stop'
$repo=$env:COL_ROOT
if([string]::IsNullOrWhiteSpace($repo)) { $repo='C:\54\Projects\!0719 - Coffee\Stage 02\Git\i-Retail-Coffee-One-Love' }
$repo=[IO.Path]::GetFullPath($repo).TrimEnd([char[]]'\/')
if(-not(Test-Path -LiteralPath $repo -PathType Container)) { throw 'PROJECT_FOLDER_NOT_FOUND' }
foreach($v in @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE')) {
    if([Environment]::GetEnvironmentVariable($v)) { throw 'CUSTOM_GIT_ENVIRONMENT_NOT_SUPPORTED' }
}
$git=Get-Command git.exe -ErrorAction SilentlyContinue
if(-not $git) {
    foreach($dir in @("$env:ProgramFiles\Git\cmd","${env:ProgramFiles(x86)}\Git\cmd")) {
        if(Test-Path -LiteralPath (Join-Path $dir 'git.exe')) { $env:PATH=$dir+';'+$env:PATH; break }
    }
    $git=Get-Command git.exe -ErrorAction Stop
}
$logDir=Join-Path $repo 'one_click_logs'
$null=New-Item -ItemType Directory -Path $logDir -Force
function Boot-Git([string[]]$Arguments) {
    $q={param($x) '"'+[regex]::Replace([regex]::Replace($x,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'}
    $si=New-Object Diagnostics.ProcessStartInfo
    $si.FileName=$git.Source
    $si.Arguments=(@(@('-C',$repo)+$Arguments | ForEach-Object { & $q $_ }) -join ' ')
    $si.WorkingDirectory=$repo
    $si.UseShellExecute=$false; $si.CreateNoWindow=$true
    $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
    $si.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
    $si.StandardErrorEncoding=New-Object Text.UTF8Encoding($false)
    $si.EnvironmentVariables['GIT_TERMINAL_PROMPT']='0'
    $p=New-Object Diagnostics.Process; $p.StartInfo=$si
    try {
        $null=$p.Start()
        $o=$p.StandardOutput.ReadToEndAsync(); $e=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(120000)) {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F 2>&1 | Out-Null
            throw 'GIT_TIMEOUT'
        }
        if(-not $o.Wait(5000) -or -not $e.Wait(5000)) { throw 'GIT_PIPE_TIMEOUT' }
        if($p.ExitCode -ne 0) {
            [IO.File]::WriteAllText((Join-Path $logDir 'bootstrap-error.log'),([string]$o.Result+"`r`n"+[string]$e.Result),(New-Object Text.UTF8Encoding($false)))
            throw 'GIT_BOOTSTRAP_FAILED_SEE_one_click_logs'
        }
        [string]$o.Result
    } finally { $p.Dispose() }
}
$top=(Boot-Git @('rev-parse','--show-toplevel')).Trim().Replace('/','\').TrimEnd('\')
if($top -ine $repo.Replace('/','\')) { throw 'NOT_PROJECT_ROOT' }
foreach($mode in @('fetch','push')) {
    $a=@('remote','get-url','--all'); if($mode -eq 'push') { $a+='--push' }; $a+='origin'
    $urls=@((Boot-Git $a).Trim() -split '\r?\n')
    if($urls.Count -ne 1 -or $urls[0] -cnotmatch '^(https://github\.com/AragCF/i-Retail-Coffee-One-Love(?:\.git)?|git@github\.com:AragCF/i-Retail-Coffee-One-Love(?:\.git)?|ssh://git@github\.com/AragCF/i-Retail-Coffee-One-Love(?:\.git)?)$') { throw 'WRONG_GIT_ORIGIN' }
}
$branch='v0.5.128-device-binding'
Write-Host '[GitHub] Fetching the approved Coffee One Love branch...'
$null=Boot-Git @('fetch','--no-tags','origin',('refs/heads/'+$branch+':refs/remotes/origin/'+$branch))
$commit=(Boot-Git @('rev-parse',('refs/remotes/origin/'+$branch))).Trim()
if($commit -cnotmatch '^[a-f0-9]{40}$') { throw 'INVALID_SOURCE_COMMIT' }
# Load only the runner from that exact Git object, not a stale local helper.
$code=Boot-Git @('show',($commit+':tools/Run-OneClick.ps1'))
$path=Join-Path $logDir ('runner-'+$commit+'.ps1')
[IO.File]::WriteAllText($path,$code,(New-Object Text.UTF8Encoding($true)))
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -RepoRoot $repo -TargetBranch $branch -TargetCommit $commit
exit $LASTEXITCODE
