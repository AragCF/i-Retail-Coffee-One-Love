param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$SourceRoot=[IO.Path]::GetFullPath($SourceRoot)
$launcher=Join-Path $SourceRoot 'tools\START_IRETAIL.bat'
$baseRunner=Join-Path $SourceRoot 'tools\Run-OneClick.ps1'
$source=[IO.File]::ReadAllText($baseRunner,[Text.Encoding]::UTF8).Replace("`r`n","`n").TrimStart([char]0xFEFF)
$bat=[IO.File]::ReadAllText($launcher,[Text.Encoding]::GetEncoding(866))
$payload=[regex]::Match($bat,"FromBase64String\('([A-Za-z0-9+/=]+)'\)")
if(-not $payload.Success) { throw 'INSTALLER_PAYLOAD_MISSING' }
$patches=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload.Groups[1].Value)) | ConvertFrom-Json
foreach($patch in $patches) {
    $from=[string]$patch[0];$to=[string]$patch[1]
    if([regex]::Matches($source,[regex]::Escape($from)).Count -ne 1) { throw 'INSTALLER_ANCHOR_MISMATCH' }
    $source=$source.Replace($from,$to)
}
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count -ne 0) { throw 'INSTALLER_PAYLOAD_SYNTAX_INVALID' }
$testRoot=Join-Path $env:TEMP ('iretail-installer-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $testRoot
$patched=Join-Path $testRoot 'runner-1.0.2.ps1'
[IO.File]::WriteAllText($patched,$source,(New-Object Text.UTF8Encoding($true)))
. $patched -RepoRoot $testRoot -LibraryOnly
$script:Local=Join-Path $testRoot 'local'
$null=New-Item -ItemType Directory -Path $script:Local
$script:Count=0
function Assert-Installer([bool]$Condition,[string]$Name) {
    if(-not $Condition) { throw ('INSTALLER_TEST_FAILED: '+$Name) }
    $script:Count++;Write-Host ('[OK] '+$Name)
}
Assert-Installer ($script:RunnerVersion -eq '1.0.2') 'Published launcher produces runner 1.0.2'
$builtInCount=Test-InstallDiagnostic
Assert-Installer ($builtInCount -eq 14) 'All 14 preflight tests ran with real Windows child processes'

# No real ADB executable is called. Read and install boundaries are synthetic.
$script:InstallCalls=0
$script:QueryCalls=0
$script:PostVersion=128
$script:ThrowInstall=$false
$script:NativeInstall=[pscustomobject]@{ExitCode=0;Out="Success`r`n";Err='SYNTHETIC_PROGRESS';TimedOut=$false}
function Adb-Run {
    param([string[]]$Arguments,[int]$Seconds=15)
    if($Arguments[0] -eq 'install') {
        $script:InstallCalls++
        if($script:ThrowInstall) { throw 'SYNTHETIC_PRIVATE_EXCEPTION_NOT_FOR_UPLOAD' }
        return $script:NativeInstall
    }
    if(($Arguments -join ' ') -ceq 'shell dumpsys package com.coffeeonelove.iretail') {
        $script:QueryCalls++
        $version=if($script:QueryCalls -eq 1){127}else{$script:PostVersion}
        return [pscustomobject]@{ExitCode=0;Out=("  versionCode="+$version+" minSdk=23`r`n");Err='';TimedOut=$false}
    }
    throw 'UNEXPECTED_SYNTHETIC_ADB_COMMAND'
}
$d=Invoke-InstallDiagnostic 'synthetic-not-an-apk'
Assert-Installer ($script:InstallCalls -eq 1 -and $script:QueryCalls -eq 2) 'Exactly one install and two read-only package queries'
Assert-Installer ($d.reason -eq 'ADB_INSTALL_SUCCESS' -and $d.before.version_code -eq 127 -and $d.after.version_code -eq 128) 'Success needs expected installed version'
Assert-Installer (($d | ConvertTo-Json -Depth 6) -notmatch 'SYNTHETIC_PROGRESS') 'Diagnostic excludes raw stderr'

$script:InstallCalls=0;$script:QueryCalls=0;$script:PostVersion=127
$d=Invoke-InstallDiagnostic 'synthetic-not-an-apk'
Assert-Installer ($d.reason -eq 'INSTALLED_VERSION_NOT_CONFIRMED' -and $script:InstallCalls -eq 1) 'Unexpected version is not installation success'

$script:InstallCalls=0;$script:QueryCalls=0;$script:PostVersion=128
$script:NativeInstall=[pscustomobject]@{ExitCode=124;Out='Success';Err='';TimedOut=$true}
$d=Invoke-InstallDiagnostic 'synthetic-not-an-apk'
Assert-Installer ($d.reason -eq 'INSTALL_RESULT_UNKNOWN_TIMEOUT' -and -not $d.adb_confirmed -and $script:InstallCalls -eq 1) 'Timeout stays uncertain even with target version observed'

$script:InstallCalls=0;$script:QueryCalls=0
$script:ThrowInstall=$true
$d=Invoke-InstallDiagnostic 'synthetic-not-an-apk'
Assert-Installer ($d.reason -eq 'INSTALL_PROCESS_EXCEPTION' -and $script:InstallCalls -eq 1) 'Exception is captured without retry'
Assert-Installer (($d | ConvertTo-Json -Depth 8) -notmatch 'SYNTHETIC_PRIVATE_EXCEPTION_NOT_FOR_UPLOAD') 'Exception message is excluded from report'

$zip=Make-PublicBundle $testRoot ([ordered]@{schema='synthetic';installation=$d}) (Get-BuildSummary '')
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try {
    Assert-Installer ($archive.Entries.Count -eq 5) 'Installer archive uses the established five-file allowlist'
    foreach($entry in $archive.Entries) {
        $reader=New-Object IO.StreamReader($entry.Open())
        try { $text=$reader.ReadToEnd() } finally { $reader.Dispose() }
        Assert-Installer ($text -notmatch 'SYNTHETIC_PRIVATE_EXCEPTION_NOT_FOR_UPLOAD|SYNTHETIC_PROGRESS') ('No raw installer content in '+$entry.FullName)
    }
} finally { $archive.Dispose() }
Write-Host ('ONE_CLICK_INSTALLER_TESTS_OK preflight='+$builtInCount+' integration='+$script:Count)
# Intentionally no device, Retail request, activation, or external Git push.
