param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$TargetBranch = 'v0.5.128-device-binding',
    [string]$TargetCommit = '',
    [switch]$LibraryOnly
)
# Windows PowerShell 5.1. This file is loaded from a pinned fetched Git object.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$script:RunnerVersion = '1.0.0'
$script:Repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]'\/')
$script:Local = $null
$script:Serial = ''
$script:Adb = ''
$script:Package = 'com.coffeeonelove.iretail'
$script:Git = 'git.exe'
$script:Events = New-Object 'System.Collections.Generic.List[object]'
$script:Seen = New-Object 'System.Collections.Generic.HashSet[string]'
$script:Pids = New-Object 'System.Collections.Generic.HashSet[string]'
$script:LastBinding = $null
$script:LastProcessState = ''
$script:LastLinkState = ''
$script:RawCounter = 0

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Quote-Argument([string]$Value) {
    # Microsoft C runtime quoting, including quotes and trailing backslashes.
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
function Invoke-Program {
    param([string]$File, [string[]]$Arguments=@(), [int]$Seconds=30,
          [hashtable]$Environment=@{}, [switch]$KeepLocal, [switch]$Heartbeat)
    $si = New-Object Diagnostics.ProcessStartInfo
    $si.FileName=$File
    $si.Arguments=(@($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' ')
    if([IO.Path]::GetFileName($File) -ieq 'cmd.exe') {
        if($Arguments.Count -ne 4 -or $Arguments[0] -ne '/d' -or $Arguments[1] -ne '/v:off' -or $Arguments[2] -ne '/c') { throw 'INVALID_CMD_ARGUMENTS' }
        # cmd.exe uses its own quote grammar, not C runtime backslash escaping.
        $si.Arguments='/d /v:off /s /c "'+$Arguments[3]+'"'
    }
    $si.WorkingDirectory=$script:Repo
    $si.UseShellExecute=$false
    $si.CreateNoWindow=$true
    $si.RedirectStandardOutput=$true
    $si.RedirectStandardError=$true
    foreach($key in $Environment.Keys) { $si.EnvironmentVariables[$key]=[string]$Environment[$key] }
    $p=New-Object Diagnostics.Process
    $p.StartInfo=$si
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $timedOut=$false
    try {
        if(-not $p.Start()) { throw 'PROCESS_START_FAILED' }
        $outTask=$p.StandardOutput.ReadToEndAsync()
        $errTask=$p.StandardError.ReadToEndAsync()
        while(-not $p.WaitForExit(1000)) {
            if($watch.Elapsed.TotalSeconds -ge $Seconds) {
                $timedOut=$true
                # Kill only this command's process tree, never the global adb server.
                & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F 2>&1 | Out-Null
                if(-not $p.WaitForExit(5000)) { $p.Kill() }
                break
            }
            if($Heartbeat -and ([int]$watch.Elapsed.TotalSeconds % 15 -eq 0)) {
                Write-Host ('  Команда ещё работает: {0} сек.' -f [int]$watch.Elapsed.TotalSeconds)
            }
        }
        # Bounded drain: a persistent child must not retain the pipe indefinitely.
        if(-not $outTask.Wait(5000) -or -not $errTask.Wait(5000)) { throw 'PROCESS_PIPE_TIMEOUT' }
        $text=[string]$outTask.Result
        $errorText=[string]$errTask.Result
        $exit=if($timedOut){124}else{$p.ExitCode}
        if($KeepLocal -and $script:Local) {
            $script:RawCounter++
            Write-Utf8 (Join-Path $script:Local ('command_{0:D3}.log' -f $script:RawCounter)) ($text+"`r`n"+$errorText)
        }
        [pscustomobject]@{ExitCode=$exit; Out=$text; Err=$errorText; TimedOut=$timedOut}
    } finally { $p.Dispose(); $watch.Stop() }
}
function Git-Run {
    param([string[]]$Arguments, [hashtable]$Environment=@{}, [switch]$AllowFailure, [int]$Seconds=120)
    $r=Invoke-Program $script:Git (@('-C',$script:Repo)+$Arguments) -Seconds $Seconds -Environment $Environment -KeepLocal
    if($r.ExitCode -ne 0 -and -not $AllowFailure) { throw 'GIT_COMMAND_FAILED' }
    $r
}
function Assert-Origin {
    foreach($mode in @('fetch','push')) {
        $args=@('remote','get-url','--all')
        if($mode -eq 'push') { $args+= '--push' }
        $args+='origin'
        $r=Git-Run $args
        $urls=@($r.Out.Trim() -split '\r?\n')
        if($urls.Count -ne 1 -or $urls[0] -cnotmatch '^(https://github\.com/AragCF/i-Retail-Coffee-One-Love(?:\.git)?|git@github\.com:AragCF/i-Retail-Coffee-One-Love(?:\.git)?|ssh://git@github\.com/AragCF/i-Retail-Coffee-One-Love(?:\.git)?)$') {
            throw 'WRONG_GIT_ORIGIN'
        }
    }
}
function Assert-CleanSource {
    if((Git-Run @('diff','--quiet') -AllowFailure).ExitCode -ne 0 -or
       (Git-Run @('diff','--cached','--quiet') -AllowFailure).ExitCode -ne 0) { throw 'LOCAL_CHANGES_PRESERVED' }
    $others=(Git-Run @('ls-files','--others','--exclude-standard','--','app','kozenBridge','buildSrc','gradle')).Out.Trim()
    if($others) { throw 'UNTRACKED_SOURCE_FILES_PRESERVED' }
    foreach($path in @('MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','rebase-merge','rebase-apply')) {
        $p=(Git-Run @('rev-parse','--git-path',$path)).Out.Trim()
        if(-not [IO.Path]::IsPathRooted($p)) { $p=Join-Path $script:Repo $p }
        if(Test-Path -LiteralPath $p) { throw 'UNFINISHED_GIT_OPERATION' }
    }
}
function Update-Source([string]$Branch,[string]$Commit) {
    if($Branch -cne 'v0.5.128-device-binding' -or $Commit -cnotmatch '^[a-f0-9]{40}$') { throw 'UNAPPROVED_SOURCE' }
    Assert-CleanSource
    $ref='refs/heads/'+$Branch
    $found=Git-Run @('show-ref','--verify','--quiet',$ref) -AllowFailure
    if($found.ExitCode -eq 0) {
        if((Git-Run @('merge-base','--is-ancestor',$ref,$Commit) -AllowFailure).ExitCode -ne 0) {
            throw 'LOCAL_BRANCH_AHEAD_OR_DIVERGED'
        }
        $null=Git-Run @('switch',$Branch)
        $null=Git-Run @('-c','merge.autoStash=false','merge','--ff-only',$Commit)
    } elseif($found.ExitCode -eq 1) {
        $null=Git-Run @('switch','--create',$Branch,'--track',('origin/'+$Branch))
        $null=Git-Run @('-c','merge.autoStash=false','merge','--ff-only',$Commit)
    } else { throw 'GIT_BRANCH_READ_FAILED' }
    if((Git-Run @('rev-parse','HEAD')).Out.Trim() -cne $Commit) { throw 'SOURCE_CHANGED_DURING_UPDATE' }
    Assert-CleanSource
}
function Add-Event([hashtable]$Data) {
    if($script:Events.Count -ge 12000) { return }
    $entry=[ordered]@{observed_utc=[DateTime]::UtcNow.ToString('o')}
    foreach($k in $Data.Keys) { $entry[$k]=$Data[$k] }
    $script:Events.Add([pscustomobject]$entry)
}
function Parse-SafeLog([string]$Text,[switch]$SeedOnly) {
    foreach($line in ($Text -split '\r?\n')) {
        if(-not $line) { continue }
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=[Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($line))) } finally { $sha.Dispose() }
        if(-not $script:Seen.Add($hash) -or $SeedOnly) { continue }
        # threadtime output; raw message never enters the report.
        if($line -notmatch '^\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+\s+(\d+)\s+\d+\s+[VDIWEF]\s+([A-Za-z0-9_]+)\s*:\s?(.*)$') { continue }
        $pidText=$Matches[1]; $tag=$Matches[2]; $msg=$Matches[3]
        if($tag -eq 'AndroidRuntime' -and $msg -match '^Process: com\.coffeeonelove\.iretail, PID: (\d+)$' -and $Matches[1] -eq $pidText) {
            $null=$script:Pids.Add($pidText)
        }
        if(-not $script:Pids.Contains($pidText)) { continue }
        if($tag -eq 'IretailBinding' -and $msg -cmatch '^STATE stage=(UNBOUND|REJECTED|REGISTERING|RESPONSE_RECEIVED|BOUND|CONFIGURED|READY|STORAGE_LOCKED) busy=(true|false) ready=(true|false) legacyUnresolved=(true|false)$') {
            $b=@{kind='binding';stage=$Matches[1];busy=($Matches[2] -eq 'true');ready=($Matches[3] -eq 'true');legacy_unresolved=($Matches[4] -eq 'true')}
            $script:LastBinding=[pscustomobject]$b
            Add-Event $b
            Write-Host ('  Привязка: {0}; занято: {1}; готово: {2}' -f $b.stage,$b.busy,$b.ready)
        } elseif($tag -eq 'IretailCatalog' -and $msg -match '^REFRESH success=(true|false).* products=(\d{1,9}) offers=(\d{1,9}) categories=(\d{1,9}) channel=(\d{1,9})(?:\s|$)') {
            Add-Event @{kind='catalog';success=($Matches[1] -eq 'true');products=[int]$Matches[2];offers=[int]$Matches[3];categories=[int]$Matches[4];channel_id=[int]$Matches[5]}
        } elseif($tag -eq 'IretailChannelConfig' -and $msg -match '^REFRESH success=(true|false).* channel=(\d{1,9}) services=(\d{1,9})(?:\s|$)') {
            Add-Event @{kind='channel';success=($Matches[1] -eq 'true');channel_id=[int]$Matches[2];services=[int]$Matches[3]}
        } elseif($tag -eq 'AndroidRuntime') {
            if($msg -match '^FATAL EXCEPTION:') { Add-Event @{kind='crash';event='FATAL_EXCEPTION'} }
            elseif($msg -match '^(?:Caused by: )?([A-Za-z_$][A-Za-z0-9_$.]*(?:Exception|Error))(?::|$)') { Add-Event @{kind='crash_class';class=$Matches[1]} }
            elseif($msg -match '^\s*at (com\.coffeeonelove\.iretail\.[A-Za-z0-9_$.]+)\(([A-Za-z0-9_]+\.(?:java|kt)):(\d{1,6})\)\s*$') {
                Add-Event @{kind='stack_frame';method=$Matches[1];file=$Matches[2];line=[int]$Matches[3]}
            }
        }
    }
}
function Adb-Run([string[]]$Arguments,[int]$Seconds=15) {
    Invoke-Program $script:Adb (@('-s',$script:Serial)+$Arguments) -Seconds $Seconds
}
function Get-Targets {
    $r=Invoke-Program $script:Adb @('devices','-l') -Seconds 15
    if($r.ExitCode -ne 0) { return @() }
    $rows=@()
    foreach($line in ($r.Out -split '\r?\n')) {
        if($line -match '^([A-Za-z0-9._:\-]+)\s+device\s+' -and
           $line -match '(?:^|\s)product:octopus_jetinno(?:\s|$)' -and
           $line -match '(?:^|\s)model:UniWin_M190(?:\s|$)' -and
           $line -match '(?:^|\s)device:octopus-jetinno(?:\s|$)') {
            $rows+=($line -split '\s+')[0]
        }
    }
    @($rows)
}
function Select-Target {
    while($true) {
        $rows=@(Get-Targets)
        if($rows.Count -gt 0) {
            Write-Host 'Подключённые интерфейсы JL22:'
            for($i=0;$i -lt $rows.Count;$i++) { Write-Host ('  [{0}] {1}' -f ($i+1),$rows[$i]) }
            $choice=Read-Host 'Номер устройства (Enter — первое), R — повторить поиск, Q — завершить'
            if($choice -match '^[Qq]$') { throw 'USER_CANCELLED' }
            if($choice -eq '') { return $rows[0] }
            $n=0
            if([int]::TryParse($choice,[ref]$n) -and $n -ge 1 -and $n -le $rows.Count) { return $rows[$n-1] }
        } else {
            Write-Host 'JL22 пока не найдена. Подключи USB/разреши отладку или восстанови Ethernet.'
            $choice=Read-Host 'Enter — искать снова; IPv4:порт — подключить известный адрес; Q — завершить'
            if($choice -match '^[Qq]$') { throw 'USER_CANCELLED' }
            if($choice -match '^\d{1,3}(?:\.\d{1,3}){3}:\d{1,5}$') {
                $null=Invoke-Program $script:Adb @('connect',$choice) -Seconds 15
            }
        }
    }
}
function Assert-Target {
    if(@(Get-Targets) -notcontains $script:Serial) { throw 'SELECTED_JL22_NOT_READY' }
}
$script:LogArgs=@('logcat','-d','-t','1200','-v','threadtime','IretailBinding:I','IretailCatalog:I','IretailChannelConfig:I','AndroidRuntime:E','*:S')
function Observe-Once([switch]$SeedOnly) {
    $ps=Adb-Run @('shell','ps')
    $link=if($ps.ExitCode -eq 0){'ONLINE'}else{'UNAVAILABLE'}
    if($script:LastLinkState -ne $link -and -not $SeedOnly) {
        $script:LastLinkState=$link; Add-Event @{kind='adb_link';state=$link}; Write-Host ('  ADB: '+$link)
    }
    if($ps.ExitCode -ne 0) { return }
    $alive=$false
    foreach($line in ($ps.Out -split '\r?\n')) {
        $cols=$line.Trim() -split '\s+'
        if($cols.Count -ge 3 -and $cols[-1] -ceq $script:Package -and $cols[1] -match '^\d+$') {
            $alive=$true; $null=$script:Pids.Add($cols[1])
        }
    }
    $state=if($alive){'RUNNING'}else{'NOT_RUNNING'}
    if($script:LastProcessState -ne $state -and -not $SeedOnly) {
        $script:LastProcessState=$state; Add-Event @{kind='process';state=$state}; Write-Host ('  Приложение: '+$state)
    }
    $r=Adb-Run $script:LogArgs
    if($r.ExitCode -eq 0) { Parse-SafeLog $r.Out -SeedOnly:$SeedOnly }
}
function Wait-Observation {
    Write-Host ''
    Write-Host 'Работай с приложением на JL22. Пароли и новый PIN вводятся только на её экране.'
    Write-Host 'Прежний PIN сначала перевыпусти в ЛК. Не повторяй активацию при неизвестном результате.'
    Write-Host 'Нажми ENTER здесь, когда нужно закончить наблюдение и отправить отчёт.'
    Write-Host 'Предел наблюдения — 30 минут. Приложение не перезапускается при сбое.'
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $next=0
    try {
        while($timer.Elapsed.TotalSeconds -lt 1800) {
            if([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq [ConsoleKey]::Enter) { break }
            if($timer.Elapsed.TotalSeconds -ge $next) { Observe-Once; $next=$timer.Elapsed.TotalSeconds+3 }
            Start-Sleep -Milliseconds 150
        }
        Observe-Once
    } finally { $timer.Stop() }
    [int]$timer.Elapsed.TotalSeconds
}
function Get-BuildSummary([string]$Text) {
    # Strict extraction, not black-list redaction: compiler messages may contain source literals.
    $tasks=New-Object 'System.Collections.Generic.List[string]'
    $locations=New-Object 'System.Collections.Generic.List[object]'
    foreach($line in ($Text -split '\r?\n')) {
        if($line -cmatch '^> Task (:[A-Za-z0-9_:-]+)(?: (UP-TO-DATE|NO-SOURCE|SKIPPED|FAILED|FROM-CACHE))?\s*$') {
            if($tasks.Count -lt 500) { $tasks.Add($line.Trim()) }
        }
        if($line -match '(?:^e: |^w: ).*[\\/]([A-Za-z0-9_]+\.(?:kt|java)):(\d{1,6}):(\d{1,6})') {
            if($locations.Count -lt 200) { $locations.Add([pscustomobject]@{file=$Matches[1];line=[int]$Matches[2];column=[int]$Matches[3]}) }
        }
    }
    [pscustomobject]@{tasks=@($tasks.ToArray());compiler_locations=@($locations.ToArray());raw_output_included=$false}
}
function Make-PublicBundle([string]$RunDir,[object]$Report,[object]$Build) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $public=Join-Path $RunDir 'public'
    $null=New-Item -ItemType Directory -Path $public -Force
    Write-Utf8 (Join-Path $public 'report.json') ($Report | ConvertTo-Json -Depth 8)
    Write-Utf8 (Join-Path $public 'events.json') (ConvertTo-Json -InputObject @($script:Events.ToArray()) -Depth 6)
    Write-Utf8 (Join-Path $public 'build-summary.json') ($Build | ConvertTo-Json -Depth 5)
    Write-Utf8 (Join-Path $public 'README.md') "# Coffee One Love: one-click report`nOnly constructed states, counters and source/build identifiers. No screenshots, PIN, credentials, account files, raw logcat or raw API replies. Missing events do not prove success. Full command logs stay local. This archive does not contain its own Git delivery receipt.`n"
    $names=@('report.json','events.json','build-summary.json','README.md')
    $hashes=@($names | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $public $_) -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$_ })
    Write-Utf8 (Join-Path $public 'SHA256SUMS.txt') ($hashes -join "`n")
    $zip=Join-Path $RunDir ('IRETAIL_'+[IO.Path]::GetFileName($RunDir)+'.zip')
    $archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
    try {
        # Exact file list. Never recursively archive the working directory.
        foreach($name in ($names+@('SHA256SUMS.txt'))) {
            $null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $public $name),$name,[IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $archive.Dispose() }
    $zip
}
function New-ReportCommit([string]$Zip,[string]$Source,[string]$RunId,[string]$RunDir) {
    if($Source -cnotmatch '^[a-f0-9]{40}$' -or $RunId -cnotmatch '^\d{8}_\d{6}_[a-f0-9]{8}$') { throw 'INVALID_REPORT_ID' }
    $path='test_reports/one-click/IRETAIL_'+$RunId+'.zip'
    $branch='diag-oneclick-'+$RunId
    $index=Join-Path $RunDir ('index-'+[guid]::NewGuid().ToString('N'))
    $envMap=@{GIT_INDEX_FILE=$index}
    try {
        $null=Git-Run @('read-tree',$Source) -Environment $envMap
        $blob=(Git-Run @('hash-object','-w','--no-filters','--',$Zip)).Out.Trim()
        $null=Git-Run @('update-index','--add','--cacheinfo',('100644,'+$blob+','+$path)) -Environment $envMap
        $tree=(Git-Run @('write-tree') -Environment $envMap).Out.Trim()
        $diff=(Git-Run @('diff-tree','--no-commit-id','--name-only','-r',$Source,$tree)).Out.Trim()
        if($diff -cne $path) { throw 'REPORT_CONTAINS_UNEXPECTED_FILES' }
        $commit=(Git-Run @('commit-tree',$tree,'-p',$Source,'-m',('test: one-click '+$RunId+' [skip ci]'))).Out.Trim()
        if($commit -cnotmatch '^[a-f0-9]{40}$') { throw 'REPORT_COMMIT_FAILED' }
        $null=Git-Run @('update-ref',('refs/heads/'+$branch),$commit,('0'*40))
        [pscustomobject]@{schema='iretail.one-click.delivery.v1';branch=$branch;commit=$commit;path=$path;archive=[IO.Path]::GetFileName($Zip);blob=$blob;delivered=$false}
    } finally {
        if(Test-Path -LiteralPath $index) { Remove-Item -LiteralPath $index -Force }
    }
}
function Send-Report([object]$Receipt,[string]$RunDir) {
    Assert-Origin
    if($Receipt.schema -cne 'iretail.one-click.delivery.v1' -or
       $Receipt.branch -cnotmatch '^diag-oneclick-\d{8}_\d{6}_[a-f0-9]{8}$' -or
       $Receipt.commit -cnotmatch '^[a-f0-9]{40}$' -or
       $Receipt.path -cnotmatch '^test_reports/one-click/IRETAIL_\d{8}_\d{6}_[a-f0-9]{8}\.zip$') { throw 'INVALID_DELIVERY_RECEIPT' }
    $ref='refs/heads/'+$Receipt.branch
    if((Git-Run @('rev-parse',$ref)).Out.Trim() -cne $Receipt.commit) { throw 'REPORT_BRANCH_CHANGED' }
    $diff=(Git-Run @('diff-tree','--no-commit-id','--name-only','-r',$Receipt.commit)).Out.Trim()
    if($diff -cne $Receipt.path) { throw 'REPORT_CONTAINS_UNEXPECTED_FILES' }
    $r=Git-Run @('push','origin',($ref+':'+$ref)) -AllowFailure
    if($r.ExitCode -ne 0) { return $false }
    $remote=Git-Run @('ls-remote','--refs','origin',$ref) -AllowFailure
    if($remote.ExitCode -ne 0 -or $remote.Out -notmatch ('^'+[regex]::Escape($Receipt.commit)+'\s'+[regex]::Escape($ref)+'\s*$')) { return $false }
    $Receipt.delivered=$true
    Write-Utf8 (Join-Path $RunDir 'delivery.json') ($Receipt | ConvertTo-Json -Depth 4)
    $true
}
function Retry-Pending([string]$Root) {
    if(-not(Test-Path -LiteralPath $Root)) { return }
    # One bounded pass. The retry never installs or reactivates an application.
    $attempts=0
    foreach($d in @(Get-ChildItem -LiteralPath $Root -Directory | Where-Object { $_.Name -cmatch '^\d{8}_\d{6}_[a-f0-9]{8}$' })) {
        $receiptPath=Join-Path $d.FullName 'delivery.json'
        if(-not(Test-Path -LiteralPath $receiptPath)) { continue }
        try {
            $receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if($receipt.delivered -eq $false) {
                if($attempts -ge 20) { break }; $attempts++
                Write-Host ('Повторная отправка сохранённого отчёта: '+$d.Name)
                if(-not(Send-Report $receipt $d.FullName)) { Write-Host '  Отчёт остаётся локально; сеть или доступ Git пока недоступны.'; break }
            }
        } catch { Write-Host '  Старый отчёт не отправлен. Его файлы сохранены без изменений.' }
    }
}
function Find-Adb {
    $cmd=Get-Command adb.exe -ErrorAction SilentlyContinue
    if($cmd) { return $cmd.Source }
    foreach($root in @($env:ANDROID_HOME,$env:ANDROID_SDK_ROOT,(Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
        if($root) { $p=Join-Path $root 'platform-tools\adb.exe'; if(Test-Path -LiteralPath $p) { return $p } }
    }
    throw 'ADB_NOT_FOUND'
}
function Show-Reason([string]$Code) {
    $messages=@{
        LOCAL_CHANGES_PRESERVED='Есть незакоммиченные изменения. Они сохранены. Ничего не сбрасывай; пришли итоговый код.'
        UNTRACKED_SOURCE_FILES_PRESERVED='В исходниках есть неучтённые Git файлы. Сборка остановлена, файлы сохранены.'
        LOCAL_BRANCH_AHEAD_OR_DIVERGED='Локальная ветка содержит собственные коммиты или разошлась с серверной. Принудительного сброса не будет.'
        SIGNING_KEY_MISMATCH='Подпись APK отличается. Не удаляй приложение: необходимо вернуть прежний ключ сборки.'
        INSTALL_FAILED='Установка не подтверждена. Автоматического удаления или повтора установки не будет.'
        BUILD_FAILED='Сборка завершилась ошибкой. Полный журнал команды остался в local; в ZIP — безопасная сводка.'
        INSUFFICIENT_DISK_SPACE='Для сборки требуется не менее 2 ГБ свободного места. Автоматическая очистка не запускалась.'
        WRONG_GIT_ORIGIN='Адрес origin не соответствует разрешённому репозиторию Coffee One Love.'
        WRONG_PROJECT_VERSION='Версия приложения не соответствует проверочному выпуску привязки.'
        DEVICE_OPERATION_BUSY='В журнале последнего процесса видна незавершённая операция привязки. Установка не начата.'
    }
    if($messages.ContainsKey($Code)) { Write-Host $messages[$Code] }
}
function Invoke-OneClick {
    if($TargetCommit -cnotmatch '^[a-f0-9]{40}$') { throw 'INVALID_TARGET_COMMIT' }
    foreach($v in @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE')) {
        if([Environment]::GetEnvironmentVariable($v)) { throw 'CUSTOM_GIT_ENVIRONMENT_NOT_SUPPORTED' }
    }
    $script:Git=(Get-Command git.exe -ErrorAction Stop).Source
    Set-Location -LiteralPath $script:Repo
    $gitDir=(Git-Run @('rev-parse','--absolute-git-dir')).Out.Trim()
    $lock=$null
    try { $lock=[IO.File]::Open((Join-Path $gitDir 'one-click.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { throw 'ANOTHER_RUNNER_IS_ACTIVE' }
    $runId=[DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $root=Join-Path $script:Repo 'one_click_logs'
    $runDir=Join-Path $root $runId
    $script:Local=Join-Path $runDir 'local'
    $null=New-Item -ItemType Directory -Path $script:Local -Force
    $report=[ordered]@{schema='iretail.one-click.v1';runner_version=$script:RunnerVersion;run_id=$runId;started_utc=[DateTime]::UtcNow.ToString('o');source_commit=$TargetCommit;source_branch=$TargetBranch;result='NOT_STARTED';completed_steps=0;total_steps=7;installed=$false;android_api=$null;apk_sha256=$null;app_version='0.5.128-device-binding';observed_seconds=0;last_binding=$null;activation_sent_by_script=$false;financial_commands_sent_by_script=$false;app_data_cleared=$false;raw_runtime_logs_saved=$false;raw_command_logs_uploaded=$false}
    $build=Get-BuildSummary ''
    $trusted=$false
    $exitCode=1
    try {
        Assert-Origin; $trusted=$true
        Retry-Pending $root
        Write-Host '[1/7] Безопасное обновление рабочей копии'
        Update-Source $TargetBranch $TargetCommit; $report.completed_steps=1
        Write-Host '[2/7] Проверка среды и исходников'
        $script:Adb=Find-Adb
        $gradle=Get-Content -LiteralPath (Join-Path $script:Repo 'app\build.gradle') -Raw
        if($gradle -notmatch "versionName\s+'0\.5\.128-device-binding'") { throw 'WRONG_PROJECT_VERSION' }
        $cfg=Get-Content -LiteralPath (Join-Path $script:Repo 'app\src\main\assets\content\iretail-api.json') -Raw | ConvertFrom-Json
        if($cfg.binding_required -ne $true) { throw 'BINDING_GATE_NOT_ENABLED' }
        $drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($script:Repo))
        if($drive.AvailableFreeSpace -lt 2GB) { throw 'INSUFFICIENT_DISK_SPACE' }
        $report.completed_steps=2
        Write-Host '[3/7] Сборка с прежним локальным ключом подписи; без команды clean'
        $b=Invoke-Program $env:ComSpec @('/d','/v:off','/c','BUILD_WINDOWS_CLI.bat') -Seconds 1800 -KeepLocal -Heartbeat
        $build=Get-BuildSummary ($b.Out+"`n"+$b.Err)
        $report['build_exit_code']=$b.ExitCode
        if($b.ExitCode -ne 0) { throw 'BUILD_FAILED' }
        $apk=Join-Path $script:Repo 'app\build\outputs\apk\debug\app-debug.apk'
        if(-not(Test-Path -LiteralPath $apk)) { throw 'APK_NOT_FOUND' }
        $report.apk_sha256=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        $report.completed_steps=3
        Write-Host '[4/7] Выбор JL22 и установка с сохранением данных'
        $script:Serial=Select-Target
        Assert-Target
        $api=Adb-Run @('shell','getprop','ro.build.version.sdk')
        if($api.ExitCode -ne 0 -or $api.Out.Trim() -notmatch '^\d{1,3}$') { throw 'ANDROID_VERSION_UNREADABLE' }
        $report.android_api=[int]$api.Out.Trim()
        if($report.android_api -lt 23) { throw 'ANDROID_VERSION_NOT_SUPPORTED' }
        # Inspect the currently running process before installation; no state is changed.
        Observe-Once
        if($script:LastBinding -and ($script:LastBinding.busy -or $script:LastBinding.stage -in @('REGISTERING','RESPONSE_RECEIVED'))) { throw 'DEVICE_OPERATION_BUSY' }
        Assert-CleanSource
        if((Git-Run @('rev-parse','HEAD')).Out.Trim() -cne $TargetCommit) { throw 'SOURCE_CHANGED_DURING_BUILD' }
        $install=Adb-Run @('install','-r',$apk) -Seconds 180
        if($install.ExitCode -ne 0 -or $install.Out -notmatch '(?m)^Success\s*$') {
            if(($install.Out+$install.Err) -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') { throw 'SIGNING_KEY_MISMATCH' }
            throw 'INSTALL_FAILED'
        }
        $report.installed=$true; $report.completed_steps=4
        # Exclude all pre-launch history, including a reused PID.
        $script:LastBinding=$null; $script:Events.Clear(); $script:Pids.Clear(); $script:LastProcessState=''; $script:LastLinkState=''
        Observe-Once -SeedOnly
        $launch=Adb-Run @('shell','am','start','-W','-n','com.coffeeonelove.iretail/.ui.MainActivity','--es','machine_mode','standalone','--ez','persist_machine_mode','true','--ez','real_pos_enabled','false') -Seconds 45
        if($launch.ExitCode -ne 0 -or ($launch.Out+$launch.Err) -match '(?im)^Error:|Exception') { throw 'APP_LAUNCH_FAILED' }
        Write-Host '[5/7] Наблюдение за приложением'
        $report.observed_seconds=Wait-Observation
        $report.completed_steps=5
        $report.last_binding=$script:LastBinding
        $report.result='OBSERVATION_FINISHED_NO_BINDING_STATE'
        if($script:LastBinding) {
            $report.result=if($script:LastBinding.ready){'BINDING_READY_OBSERVED'}else{'BINDING_NOT_READY'}
        }
        if(@($script:Events | Where-Object { $_.kind -eq 'crash' }).Count -gt 0) { $report.result='APP_CRASH_OBSERVED' }
        $exitCode=0
    } catch {
        $code=[string]$_.Exception.Message
        if($code -cnotmatch '^[A-Z_]{3,80}$') { $code='LOCAL_TOOL_FAILED' }
        $report.result=$code
        Write-Host ('[ОСТАНОВКА] '+$code)
        Show-Reason $code
    }
    try {
        Write-Host '[6/7] Упаковка только безопасных результатов'
        $report['finished_utc']=[DateTime]::UtcNow.ToString('o')
        if($report.completed_steps -eq 5) { $report.completed_steps=6 }
        $zip=Make-PublicBundle $runDir $report $build
        $zipHash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Utf8 ($zip+'.sha256.txt') ($zipHash+'  '+[IO.Path]::GetFileName($zip))
        Write-Host '[7/7] Отправка отдельной диагностической ветки'
        $sent=$false
        if($trusted) {
            $receipt=New-ReportCommit $zip $TargetCommit $runId $runDir
            Write-Utf8 (Join-Path $runDir 'delivery.json') ($receipt | ConvertTo-Json -Depth 4)
            $sent=Send-Report $receipt $runDir
        }
        $lines=@('RESULT='+$report.result,'RUN_ID='+$runId,'ZIP='+$zip,'SHA256='+$zipHash)
        if($sent) {
            $lines+=@('GIT_REPORT_SENT','BRANCH='+$receipt.branch,'COMMIT='+$receipt.commit,'ARTIFACT='+$receipt.path)
            Write-Host '[GIT_REPORT_SENT] Отчёт отправлен; хеш коммита проверен на GitHub.'
            Write-Host ('Ветка: '+$receipt.branch)
            if($report.completed_steps -eq 6) { Write-Host 'Выполнено 7 / осталось 0 / всего 7 шагов — 100% этого прогона.' }
        } else {
            $lines+='GIT_REPORT_PENDING'
            if($exitCode -eq 0) { $exitCode=2 }
            Write-Host '[GIT_REPORT_PENDING] Отчёт остался локально. Следующий запуск повторит отправку.'
        }
        Write-Utf8 (Join-Path $root 'LAST_RESULT.txt') ($lines -join "`r`n")
        Write-Host ('Результат приложения: '+$report.result)
        Write-Host ('Архив: '+$zip)
        Write-Host ('Последний итог: '+(Join-Path $root 'LAST_RESULT.txt'))
    } catch {
        Write-Host '[REPORT_DELIVERY_FAILED] Файлы остались в one_click_logs. Рабочие коммиты не отправлялись.'
        Write-Utf8 (Join-Path $root 'LAST_RESULT.txt') ('RESULT='+$report.result+"`r`nREPORT_DELIVERY_FAILED`r`nRUN_ID="+$runId+"`r`nLOCAL="+$runDir)
        $exitCode=2
    } finally { if($lock) { $lock.Dispose() } }
    return $exitCode
}
if(-not $LibraryOnly) {
    try { exit (Invoke-OneClick) }
    catch { Write-Host ('[START_FAILED] '+[string]$_.Exception.Message); exit 1 }
}
