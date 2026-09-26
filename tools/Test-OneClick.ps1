param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$testRoot=Join-Path $env:TEMP ('Coffee !0719 Кириллица '+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $testRoot
$runner=Join-Path $SourceRoot 'tools\Run-OneClick.ps1'
$launcher=Join-Path $SourceRoot 'tools\START_IRETAIL.bat'
. $runner -RepoRoot $testRoot -LibraryOnly
$script:Checks=0
function Check([bool]$Condition,[string]$Name) {
    if(-not $Condition) { throw ('TEST_FAILED: '+$Name) }
    $script:Checks++; Write-Host ('[OK] '+$Name)
}
function Expect([scriptblock]$Action,[string]$Code) {
    $actual='NO_EXCEPTION'
    try { & $Action | Out-Null } catch { $actual=$_.Exception.Message }
    Check ($actual -ceq $Code) $Code
}
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'PowerShell parser'
$bat=[IO.File]::ReadAllText($launcher,[Text.Encoding]::GetEncoding(866))
$parts=[regex]::Split($bat,'(?m)^:__COL_BOOTSTRAP_PS__\r?$')
Check ($parts.Count -eq 2) 'Bootstrap boundary'
$null=[Management.Automation.Language.Parser]::ParseInput($parts[1],[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'Bootstrap PowerShell parser'
Check ($bat -notmatch '(?im)^\s*chcp\s') 'No code-page switch'
Check ($bat.Contains('DisableDelayedExpansion')) 'Exclamation marks preserved'
Check ($bat.Contains('pause')) 'Double-click pause'

# Actual Windows processes, including inherited handles and unusual paths.
$probe=Join-Path $testRoot 'probe.cmd'
[IO.File]::WriteAllText($probe,"@echo off`r`necho PROBE_OK`r`necho STDERR_OK 1>&2`r`nexit /b 37`r`n",[Text.Encoding]::ASCII)
$r=Invoke-Program $env:ComSpec @('/d','/v:off','/c','probe.cmd')
Check ($r.ExitCode -eq 37 -and $r.Out.Contains('PROBE_OK') -and $r.Err.Contains('STDERR_OK')) 'Native CMD exit/stdout/stderr'
$echo=Join-Path $testRoot 'echo.ps1'
Write-Utf8 $echo 'param([string]$Text) [Console]::Write($Text)'
$value='C:\space path\!mark\with"quote\'
$r=Invoke-Program 'powershell.exe' @('-NoProfile','-File',$echo,'-Text',$value)
Check ($r.ExitCode -eq 0 -and $r.Out -ceq $value) 'Windows argument quoting roundtrip'
$r=Invoke-Program 'powershell.exe' @('-NoProfile','-Command','Start-Sleep -Seconds 20') -Seconds 1
Check ($r.ExitCode -eq 124 -and $r.TimedOut) 'Bounded command timeout'
$stub=Join-Path $testRoot 'пуск ! проверка.bat'
[IO.File]::WriteAllText($stub,($parts[0]+":__COL_BOOTSTRAP_PS__`r`nexit 37`r`n"),[Text.Encoding]::GetEncoding(866))
# Build the entire /c command as one argument; this catches CMD quote stripping.
$r=Invoke-Program $env:ComSpec @('/d','/v:off','/c',('call '+(Quote-Argument $stub))) -Environment @{COL_NO_PAUSE='1'}
Check ($r.ExitCode -eq 37) 'Actual BAT wrapper returns child exit code with spaces/Cyrillic/!'

# Hostile runtime text stays outside the constructed telemetry.
$null=$script:Pids.Add('123')
$raw=@'
09-26 17:01:02.001   999   999 I IretailBinding: STATE stage=READY busy=false ready=true legacyUnresolved=false
09-26 17:01:02.002   123   123 I IretailBinding: STATE stage=READY busy=false ready=true legacyUnresolved=false password=NEVER_PUBLISH_THIS
09-26 17:01:02.003   123   123 I IretailBinding: STATE stage=BOUND busy=false ready=false legacyUnresolved=false
09-26 17:01:02.004   123   123 I IretailCatalog: REFRESH success=true raw=NEVER_PUBLISH_THIS products=2 offers=3 categories=1 channel=6002 extra=NEVER_PUBLISH_THIS
09-26 17:01:02.005   123   123 I IretailChannelConfig: REFRESH success=false raw=NEVER_PUBLISH_THIS channel=6002 services=0 detail=NEVER_PUBLISH_THIS
09-26 17:01:02.006   123   123 E AndroidRuntime: FATAL EXCEPTION: NEVER_PUBLISH_THIS
09-26 17:01:02.007   123   123 E AndroidRuntime: java.lang.IllegalStateException: password=NEVER_PUBLISH_THIS
09-26 17:01:02.008   123   123 E AndroidRuntime:   at com.coffeeonelove.iretail.ui.MainActivity.onCreate(MainActivity.kt:45)
09-26 17:01:02.009   123   123 I IretailBinding: {"code":"NEVER_PUBLISH_THIS","access_token":"NEVER_PUBLISH_THIS"}
'@
Parse-SafeLog $raw
$json=ConvertTo-Json -InputObject @($script:Events.ToArray()) -Depth 6
Check (-not $json.Contains('NEVER_PUBLISH_THIS')) 'No raw credentials/API/error messages'
Check ($script:LastBinding.stage -eq 'BOUND') 'Strict binding schema/PID filter'
Check ($script:Events.Count -eq 6) 'Only six expected normalized events'
Check (@($script:Events | Where-Object {$_.kind -eq 'crash_class'}).Count -eq 1) 'Crash class without message'
$before=$script:Events.Count; Parse-SafeLog $raw
Check ($script:Events.Count -eq $before) 'Duplicate snapshots removed'
Parse-SafeLog '09-26 17:01:02.099   123   123 I IretailBinding: STATE stage=READY busy=false ready=true legacyUnresolved=false' -SeedOnly
Parse-SafeLog '09-26 17:01:02.099   123   123 I IretailBinding: STATE stage=READY busy=false ready=true legacyUnresolved=false'
Check ($script:LastBinding.stage -eq 'BOUND') 'Pre-launch history excluded'
$build=Get-BuildSummary "> Task :app:compileDebugKotlin FAILED`ne: file:///a/Secret.kt:15:9 error NEVER_PUBLISH_THIS`nPIN=NEVER_PUBLISH_THIS"
Check (($build | ConvertTo-Json -Depth 5) -notmatch 'NEVER_PUBLISH_THIS') 'Build output minimized'
Check ($build.compiler_locations.Count -eq 1 -and $build.tasks.Count -eq 1) 'Compiler location/task preserved'

$instantCrash=@'
09-26 17:01:03.001   456   456 E AndroidRuntime: FATAL EXCEPTION: NEVER_PUBLISH_THIS
09-26 17:01:03.002   456   456 E AndroidRuntime: Process: com.coffeeonelove.iretail, PID: 456
09-26 17:01:03.003   456   456 E AndroidRuntime: java.lang.RuntimeException: NEVER_PUBLISH_THIS
'@
$before=$script:Events.Count
Parse-SafeLog $instantCrash
Check ($script:Events.Count -eq $before+2) 'Immediate crash captured even before ps sees its PID'
Check ((ConvertTo-Json -InputObject @($script:Events.ToArray()) -Depth 5) -notmatch 'NEVER_PUBLISH_THIS') 'Immediate crash excludes message secrets'

# Native Git integration, all remotes are disposable local bare repositories.
$seed=Join-Path $testRoot 'seed'; $mirror=Join-Path $testRoot 'mirror.git'; $work=Join-Path $testRoot 'work ! копия'
$branch='v0.5.128-device-binding'
Check ((Invoke-Program 'git.exe' @('init','--bare',$mirror)).ExitCode -eq 0) 'Create disposable bare remote'
Check ((Invoke-Program 'git.exe' @('init','--initial-branch',$branch,$seed)).ExitCode -eq 0) 'Create seed repository'
$script:Repo=$seed
$null=Git-Run @('config','user.name','One Click Test');$null=Git-Run @('config','user.email','oneclick-test@example.invalid')
Write-Utf8 (Join-Path $seed 'source.txt') 'base'
$null=New-Item -ItemType Directory -Path (Join-Path $seed 'app\src\main\assets\content') -Force
Write-Utf8 (Join-Path $seed 'app\build.gradle') "versionName '0.5.128-device-binding'"
Write-Utf8 (Join-Path $seed 'app\src\main\assets\content\iretail-api.json') '{"binding_required":true}'
Write-Utf8 (Join-Path $seed '.gitignore') "one_click_logs/`napp/build/`n"
$null=Git-Run @('add','.');$null=Git-Run @('commit','-m','synthetic base');$base=(Git-Run @('rev-parse','HEAD')).Out.Trim()
$null=Git-Run @('remote','add','origin',$mirror);$null=Git-Run @('push','-u','origin',$branch)
Check ((Invoke-Program 'git.exe' @('clone','--branch',$branch,$mirror,$work)).ExitCode -eq 0) 'Clone fixture'
Write-Utf8 (Join-Path $seed 'source.txt') 'new remote content'
$null=Git-Run @('add','source.txt');$null=Git-Run @('commit','-m','next source');$source=(Git-Run @('rev-parse','HEAD')).Out.Trim()
$null=Git-Run @('push','origin',$branch)
$script:Repo=$work
$null=Git-Run @('config','user.name','One Click Test');$null=Git-Run @('config','user.email','oneclick-test@example.invalid')
$null=Git-Run @('fetch','origin')
Update-Source $branch $source
Check ((Git-Run @('rev-parse','HEAD')).Out.Trim() -eq $source) 'Fast-forward source update'
Update-Source $branch $source
Check ((Git-Run @('rev-parse','HEAD')).Out.Trim() -eq $source) 'Repeated update is idempotent'
Expect {Assert-Origin} 'WRONG_GIT_ORIGIN'
$null=Git-Run @('remote','set-url','origin','https://github.com/AragCF/i-Retail-Coffee-One-Love.git')
Assert-Origin;Check $true 'Expected GitHub origin accepted'
$null=Git-Run @('remote','set-url','origin',$mirror)
Write-Utf8 (Join-Path $work 'app\unexpected.kt') 'do not compile this'
Expect {Assert-CleanSource} 'UNTRACKED_SOURCE_FILES_PRESERVED'
Remove-Item -LiteralPath (Join-Path $work 'app\unexpected.kt')
$null=Git-Run @('switch','--create','fixture-local-branch')
Write-Utf8 (Join-Path $work 'local-only.txt') 'LOCAL_ONLY_COMMIT'
$null=Git-Run @('add','local-only.txt'); $null=Git-Run @('commit','-m','local user change')
$localCommit=(Git-Run @('rev-parse','HEAD')).Out.Trim()
$null=Git-Run @('update-ref',('refs/heads/'+$branch),$localCommit,$source)
Expect {Update-Source $branch $source} 'LOCAL_BRANCH_AHEAD_OR_DIVERGED'
Check ((Git-Run @('rev-parse','HEAD')).Out.Trim() -eq $localCommit) 'Ahead branch is not reset'
# Restore only the synthetic fixture ref, not production data.
$null=Git-Run @('update-ref',('refs/heads/'+$branch),$source,$localCommit)
$null=Git-Run @('switch',$branch)
Write-Utf8 (Join-Path $work 'source.txt') 'LOCAL_SECRET_DO_NOT_PUBLISH'
Write-Utf8 (Join-Path $work 'staged.txt') 'STAGED_SECRET_DO_NOT_PUBLISH'
$null=Git-Run @('add','staged.txt')
Expect {Update-Source $branch $source} 'LOCAL_CHANGES_PRESERVED'
Check ((Get-Content -LiteralPath (Join-Path $work 'source.txt') -Raw) -eq 'LOCAL_SECRET_DO_NOT_PUBLISH') 'Uncommitted source retained'
$indexBefore=(Get-FileHash -LiteralPath (Join-Path $work '.git\index')).Hash
$headBefore=(Git-Run @('rev-parse','HEAD')).Out.Trim()
$runId='20260926_120000_1234abcd';$runDir=Join-Path $work ('one_click_logs\'+$runId)
$null=New-Item -ItemType Directory -Path (Join-Path $runDir 'local') -Force
Write-Utf8 (Join-Path $runDir 'local\private.log') 'NEVER_PUBLISH_THIS'
$zip=Make-PublicBundle $runDir ([ordered]@{schema='fixture';result='OK'}) $build
$z=[IO.Compression.ZipFile]::OpenRead($zip)
try {
    Check ($z.Entries.Count -eq 5) 'Archive contains exactly five allowed files'
    Check (@($z.Entries | Where-Object {$_.FullName -match 'local|private'}).Count -eq 0) 'Private directory not archived'
    foreach($entry in $z.Entries) {
        $reader=New-Object IO.StreamReader($entry.Open());try{$t=$reader.ReadToEnd()}finally{$reader.Dispose()}
        Check ($t -notmatch 'NEVER_PUBLISH_THIS|LOCAL_SECRET_DO_NOT_PUBLISH|STAGED_SECRET_DO_NOT_PUBLISH') ('Safe ZIP entry '+$entry.FullName)
    }
} finally {$z.Dispose()}
$receipt=New-ReportCommit $zip $source $runId $runDir
Check ((Get-FileHash -LiteralPath (Join-Path $work '.git\index')).Hash -eq $indexBefore) 'Report leaves user Git index unchanged'
Check ((Git-Run @('rev-parse','HEAD')).Out.Trim() -eq $headBefore) 'Report leaves user branch/HEAD unchanged'
Check ((Git-Run @('diff-tree','--no-commit-id','--name-only','-r',$receipt.commit)).Out.Trim() -eq $receipt.path) 'Report commit has only one ZIP'
$saveOrigin=${function:Assert-Origin}
function Assert-Origin {} # Test-only: allow disposable bare remote, never applied to production file.
Write-Utf8 (Join-Path $runDir 'delivery.json') ($receipt | ConvertTo-Json -Depth 4)
Check (Send-Report $receipt $runDir) 'Push and verify diagnostic commit to local remote'
Check (Send-Report $receipt $runDir) 'Repeat delivery is idempotent'
Check ((Git-Run @('rev-parse','HEAD')).Out.Trim() -eq $source) 'Publication does not switch source branch'
Check ((Get-FileHash -LiteralPath (Join-Path $work '.git\index')).Hash -eq $indexBefore) 'Publication preserves staged secrets'

# Run the complete coordinator with synthetic device/build boundaries, real Git/ZIP delivery.
$null=Git-Run @('restore','--staged','--','staged.txt');Remove-Item -LiteralPath (Join-Path $work 'staged.txt')
$null=Git-Run @('restore','--','source.txt')
$saveProgram=${function:Invoke-Program}
function Invoke-Program {
    param([string]$File,[string[]]$Arguments=@(),[int]$Seconds=30,[hashtable]$Environment=@{},[switch]$KeepLocal,[switch]$Heartbeat)
    if($File -eq $env:ComSpec) {
        $p=Join-Path $script:Repo 'app\build\outputs\apk\debug';$null=New-Item -ItemType Directory -Path $p -Force
        Write-Utf8 (Join-Path $p 'app-debug.apk') 'SYNTHETIC_NOT_AN_APK'
        return [pscustomobject]@{ExitCode=0;Out='> Task :app:assembleDebug';Err='';TimedOut=$false}
    }
    & $saveProgram @PSBoundParameters
}
function Find-Adb { 'test-only-adb-not-a-real-device' }
function Select-Target { 'fixture-device' }
function Assert-Target {}
function Observe-Once {param([switch]$SeedOnly)}
function Adb-Run {
    param([string[]]$Arguments,[int]$Seconds=15)
    $out=if($Arguments -contains 'ro.build.version.sdk'){'23'}elseif($Arguments[0] -eq 'install'){'Success'}else{'Status: ok'}
    [pscustomobject]@{ExitCode=0;Out=$out;Err='';TimedOut=$false}
}
function Wait-Observation {
    $script:LastProcessState='RUNNING'; $script:LastLinkState='ONLINE'
    $script:LastBinding=[pscustomobject]@{kind='binding';stage='READY';busy=$false;ready=$true;legacy_unresolved=$false}
    return 1
}
$script:Events.Clear();$script:LastBinding=$null
$TargetCommit=$source;$TargetBranch=$branch
$result=Invoke-OneClick
Check ($result -eq 0) 'Complete coordinator with fake build/device and real Git delivery'
$last=Get-Content -LiteralPath (Join-Path $work 'one_click_logs\LAST_RESULT.txt') -Raw
Check ($last.Contains('GIT_REPORT_SENT') -and $last.Contains('BINDING_READY_OBSERVED')) 'Human-readable final receipt'
Check ((Git-Run @('rev-parse','HEAD')).Out.Trim() -eq $source) 'End-to-end source HEAD stable'
Set-Item function:Invoke-Program $saveProgram
Set-Item function:Assert-Origin $saveOrigin
Write-Host ('ONE_CLICK_TESTS_OK checks='+$script:Checks)
# CI output only: no production credentials, no physical device, no external push.
