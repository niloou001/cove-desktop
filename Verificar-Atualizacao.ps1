$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveRuntime.ps1"
. "$PSScriptRoot\CoveInstance.ps1"
Add-Type -Path "$PSScriptRoot\CoveRuntimeWindows.cs"
foreach($file in @('CoveRuntime.ps1','CoveLauncher.ps1','Cove-Voice.ps1','CoveInstance.ps1')){
 $tokens=$null;$issues=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$issues)
 if($issues.Count){throw ($issues|Out-String)}
 if($file -eq 'CoveLauncher.ps1'){$node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-CoveProcessCommand'},$true);. ([scriptblock]::Create($node.Extent.Text))}
}
$valid='powershell.exe -NoProfile -STA -File "'+$PSScriptRoot+'\Cove-Voice.ps1" -ListenOnStart'
if(-not (Test-CoveProcessCommand $valid $PSScriptRoot)){throw 'Correct instance not recognized'}
foreach($invalid in @(
 ('powershell.exe -File "'+$PSScriptRoot+'\Verificar-Cove.ps1"'),
 ($valid+' -SmokeTest'),
 ('powershell.exe -File "'+$PSScriptRoot+'\Cove-Voice.ps1.bak"'),
 ('powershell.exe -Command echo -File "'+$PSScriptRoot+'\Cove-Voice.ps1"'),
 'powershell.exe -File "C:\Other\Cove-Voice.ps1"'
)){
 if(Test-CoveProcessCommand $invalid $PSScriptRoot){throw ('Unrelated process accepted: '+$invalid)}
}
$root=Join-Path $PSScriptRoot ('runtime-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$first=$null;$second=$null
try{
 Get-ChildItem -LiteralPath $PSScriptRoot -File|Where-Object{$_.Extension -in @('.ps1','.cs','.xaml','.py')}|ForEach-Object{[IO.File]::Copy($_.FullName,(Join-Path $root $_.Name))}
 $before=Get-CoveBuildId $root
 if($before -cne (Get-CoveBuildId $PSScriptRoot)){throw 'Fingerprint depends on unrelated files'}
 [IO.File]::AppendAllText((Join-Path $root 'Cove-Orb.xaml'),"`n")
 $after=Get-CoveBuildId $root
 if($after -ceq $before){throw 'Updated source not detected'}
 [IO.File]::WriteAllText((Join-Path $root 'cove-appearance.json'),'{"Accent":"#A78BFA"}')
 if((Get-CoveBuildId $root) -cne $after){throw 'Preference change incorrectly triggers app restart'}
 $protectedSession='verified'
 try{
  Save-CoveReloadState $root 'fixture private transcript' @(@{role='user';content='fixture question'})
  $file=Join-Path $root '.cove-reload-session.dat'
  if([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($file)).Contains('fixture private transcript')){throw 'Reload snapshot stored plaintext'}
  $state=Read-CoveReloadState $root
  if($state.Transcript -cne 'fixture private transcript' -or $state.History[0].content -cne 'fixture question' -or (Test-Path -LiteralPath $file)){throw 'Protected session restore failed'}
 }catch{
  if($_.Exception.GetBaseException() -isnot [Security.Cryptography.CryptographicException]){throw}
  $protectedSession='not verified: Windows user-profile DPAPI unavailable in this session'
 }
 Write-CoveRuntime $root $after
 $runtime=Get-Content -LiteralPath (Join-Path $root 'cove-runtime.json') -Raw|ConvertFrom-Json
 if($runtime.Pid -ne $PID -or $runtime.Build -cne $after -or $runtime.Features -notcontains 'mouse-two-monitors'){throw 'Runtime identity missing'}
 $first=Open-CoveInstanceChannel $root
 $second=Open-CoveInstanceChannel $root -DiscordSettings
 if(-not $second.AlreadyRunning -or -not $first.DiscordSettings.WaitOne(0)){throw 'Existing instance does not receive settings request'}
 $second.Reload.Set()|Out-Null
 if(-not $first.Reload.WaitOne(0)){throw 'Reload request not delivered'}
 'OK: exact process ownership, source version detection, preferences kept, runtime identity and reload/settings channels. No running Cove process was closed.'
 'Session encryption: '+$protectedSession
}finally{
 if($second){Close-CoveInstanceChannel $second};if($first){Close-CoveInstanceChannel $first}
 $resolved=[IO.Path]::GetFullPath($root)
 if($resolved.StartsWith($PSScriptRoot+'\runtime-test-',[StringComparison]::OrdinalIgnoreCase)){
  Get-ChildItem -LiteralPath $resolved -File|ForEach-Object{Remove-Item -LiteralPath $_.FullName}
  [IO.Directory]::Delete($resolved,$false)
 }
}
