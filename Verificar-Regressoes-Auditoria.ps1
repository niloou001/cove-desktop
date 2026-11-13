$ErrorActionPreference='Stop'
foreach($module in @('CoveApps.ps1','CoveDiscord.ps1','CoveMessages.ps1','CoveMessagePlanner.ps1','CoveShortcuts.ps1','CoveControl.ps1','CoveFiles.ps1','CoveOnline.ps1')){. (Join-Path $PSScriptRoot $module)}
$tokens=$null;$issues=$null;$source=[IO.File]::ReadAllText("$PSScriptRoot\Cove-Voice.ps1")
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$issues)
if($issues.Count){throw ($issues|Out-String)}
foreach($name in @('Ask-Cove','Restart-Listener','Start-ChatGPTConnection','Clear-CoveConversation')){
 $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 . ([scriptblock]::Create($node.Extent.Text))
}
function Add-Message {param($Who,$Text)}
function Say {param($Text) $script:spoken=$Text}
function Update-Capture {}
function Update-CoveShortcutLabels {}
function Write-CoveActionTrace {}
$voiceEngine=[pscustomobject]@{};$voiceEngine|Add-Member ScriptMethod Stop {}
$transcriber=[pscustomobject]@{};$transcriber|Add-Member ScriptMethod Stop {}
$transcript=[pscustomobject]@{Text='test'};$transcript|Add-Member ScriptMethod Clear {$this.Text=''}
$sendButton=[pscustomobject]@{IsEnabled=$true};$muteButton=[pscustomobject]@{Content=''}
$script:speechQueue=New-Object 'Collections.Generic.Queue[string]'
$SmokeTest=$true;$modelReady=$false;$script:listener=$null
$script:task=$null;$script:discordTask=$null;$script:loginTask=$null;$script:transcribeTask=$null
$folder=Join-Path $PSScriptRoot '.cove-audit';[IO.Directory]::CreateDirectory($folder)|Out-Null
$file=Join-Path $folder 'private-fixture.txt';[IO.File]::WriteAllText($file,'LOCAL_CONTENT_SENTINEL_729')
$audioFile=Join-Path $folder 'audio-fixture.json'
$script:failures=New-Object 'Collections.Generic.List[string]'
function Check([string]$Name,[scriptblock]$Test){try{& $Test;'PASS '+$Name}catch{$script:failures.Add($Name+': '+$_.Exception.Message);'FAIL '+$script:failures[-1]}}
try{
 Check 'Natural local file commands' {
  $script:assistantWakePattern='(?<!\w)Luma(?!\w)'
  $r=Invoke-CoveFileRequest ('Luma, pode ler arquivo "'+$file+'" por favor') -DryRun
  if(-not $r.Handled -or $r.Message -cne 'LOCAL_CONTENT_SENTINEL_729'){throw 'Named assistant and polite phrase lost file request'}
  $script:assistantWakePattern=$null
 }
 $script:assistantWakePattern=$null
 Check 'Local file data excluded from model history' {
  $script:history=@();Ask-Cove ('leia arquivo '+$file)
  if(($script:history|ConvertTo-Json -Compress) -like '*LOCAL_CONTENT_SENTINEL_729*'){throw 'Private file content entered model history'}
  if($script:spoken -cne 'LOCAL_CONTENT_SENTINEL_729'){throw 'Local read stopped displaying/speaking its content'}
 }
 Check 'ASR restart preserves active speech state' {
  $script:state='Speaking';Restart-Listener
  if($script:state -ne 'Speaking'){throw 'Restart changed Speaking to Idle'}
 }
 Check 'Connection waits for local automation' {
  $script:discordTask=[pscustomobject]@{Busy=$true};$script:loginCalls=0
  $script:account=[pscustomobject]@{};$script:account|Add-Member ScriptMethod SignIn {$script:loginCalls++;return [pscustomobject]@{Fake=$true}}
  Start-ChatGPTConnection 'login'
  if($script:loginCalls){throw 'Login started during local automation'}
 }
 $script:discordTask=$null;$script:loginTask=$null
 if($script:loginCancel){$script:loginCancel.Dispose();$script:loginCancel=$null}
 Check 'Weather city prompt can be cancelled' {
  $script:onlineCityUntil=[datetime]::Now.AddMinutes(1)
  $r=Invoke-CoveOnlineRequest 'cancela'
  if(-not $r.Handled -or $script:onlineCityUntil -gt [datetime]::Now){throw 'Pending weather city remained active'}
  $script:onlineCityUntil=[datetime]::Now.AddMinutes(1)
  if((Get-CoveOnlineRequest 'obrigado').Handled){throw 'Thanks interpreted as city'}
 }
 Check 'Clear conversation removes pending weather and channel link' {
  $script:onlineCityUntil=[datetime]::Now.AddMinutes(1);$script:pendingLinkTarget=[pscustomobject]@{Server='old'}
  Clear-CoveConversation|Out-Null
  if($script:onlineCityUntil -gt [datetime]::Now -or $script:pendingLinkTarget){throw 'Old pending action survived Clear'}
 }
 $begin=$source.IndexOf("`$dialog.FindName('ApplyAudio').Add_Click({")
 $finish=$source.IndexOf("`n })",$begin)
 $handler=$source.Substring($begin,$finish-$begin)
 $handler=$handler.Substring($handler.IndexOf('{')+1)
 $voiceList=[pscustomobject]@{SelectedItem=$null};$micList=[pscustomobject]@{SelectedItem=$null};$vocabularyBox=[pscustomobject]@{Text=''}
 $script:micHint=[pscustomobject]@{Text=''};$script:micId=-1;$script:voiceId='test'
 Check 'Applying audio preserves paused microphone' {
  $script:muted=$true;$script:state='Speaking';$script:speechQueue.Enqueue('old speech');& ([scriptblock]::Create($handler))
  if(-not $script:muted){throw 'Apply audio reactivated muted microphone'}
  if($script:state -ne 'Idle' -or $script:speechQueue.Count){throw 'Apply audio left stale speech state'}
 }
 Check 'Applying audio waits for local task' {
  $script:discordTask=[pscustomobject]@{Busy=$true};$script:micHint.Text=''
  & ([scriptblock]::Create($handler))
  if($script:micHint.Text -notlike 'Espere*'){throw 'Audio changed during local automation'}
 }
}finally{
 [IO.File]::Delete($file);[IO.File]::Delete($audioFile)
}
if($script:failures.Count){throw ($script:failures -join "`n")}
'OK: audit regressions, simulated tasks and local fixture only; no network, messages or microphone.'