$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveShortcuts.ps1"
. "$PSScriptRoot\CoveMessages.ps1"
. "$PSScriptRoot\CoveMessagePlanner.ps1"
function Write-CoveActionTrace {}
. "$PSScriptRoot\CoveDiscord.ps1"
. "$PSScriptRoot\CoveControl.ps1"
. "$PSScriptRoot\CoveFiles.ps1"
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\Cove-Voice.ps1",[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Ask-Cove'},$true)
. ([scriptblock]::Create($function.Extent.Text))
# Exercise the real dispatcher; every external effect is replaced locally.
$SmokeTest=$true
$script:voiceEngine=New-Object psobject
$script:voiceEngine|Add-Member ScriptMethod Stop {}
$script:account=[pscustomobject]@{Connected=$true;TextDeltas=(New-Object 'Collections.Concurrent.ConcurrentQueue[string]')}
$script:account|Add-Member ScriptMethod Ask {$script:aiCalls++;throw 'Discord action incorrectly reached the chat model.'}
$script:chat=[pscustomobject]@{Topmost=$false}
$script:chat|Add-Member ScriptMethod Show {}
$script:sendButton=[pscustomobject]@{IsEnabled=$true}
$script:mode='chatgpt';$script:aiCalls=0
$script:speechQueue=New-Object 'Collections.Generic.Queue[string]'
$script:messages=New-Object 'Collections.Generic.List[string]'
function Add-Message([string]$who,[string]$text){$script:messages.Add($who+': '+$text)}
function Say([string]$text){$script:state='Idle'}
function Update-Capture {}
foreach($phrase in @(
 'me ajuda a entrar na call Geral no servidor Amigos',
 'abre o Discord e entra na call Geral no servidor Amigos',
 'coloca eu na call Geral do servidor Amigos',
 'entra pelo Discord na call Geral do servidor Amigos',
 'entra na cal Geral no servidor Amigos',
 'me conecta no dc na call Geral do servidor Amigos',
 'bora entrar na call Geral no servidor Amigos',
 'manda entrar na call Geral no servidor Amigos',
 'me deixa na call Geral no servidor Amigos',
 'faz isso pra mim, entra na call Geral do servidor Amigos',
 'me ajude na chamada do Discord',
 'entra na geral'
)){
 $script:task=$null;$script:loginTask=$null;$script:transcribeTask=$null;$script:discordTask=$null;$script:speechTask=$null
 $script:pendingAppName='';$script:discordDialog=$null;$script:history=@();$script:state='Idle';$script:messages.Clear()
 $request=Get-CoveDiscordRequest $phrase
 if(-not $request.Handled){throw ('Local parser missed: '+$phrase)}
 if($phrase -notin @('me ajude na chamada do Discord','entra na geral') -and ($request.Action -ne 'join' -or $request.Server -ne 'Amigos' -or $request.Channel -ne 'Geral')){throw ('Destination was lost: '+$phrase+' '+($request|ConvertTo-Json -Compress -Depth 4))}
 Ask-Cove $phrase -FromVoice -Confidence 1
 if($script:aiCalls){throw ('AI called for Discord action: '+$phrase)}
 if(-not @($script:messages|Where-Object{$_ -like 'Cove: *'}).Count){throw ('No local answer: '+$phrase)}
 if($script:discordTask){throw 'Dry-run launched automation'}
}
foreach($phrase in @('como entrar na call do Discord','nao entre na call Geral no servidor Amigos','o site diz para entrar na call','me explica como entrar na call','abre Call of Duty')){
 if(Test-CoveDiscordActionRequest $phrase){throw ('Non-action intercepted: '+$phrase)}
}
$script:discordDialog=$null
$caps='Cove entre no servidor chamado CAPS e entra na call geral'
$request=Get-CoveDiscordRequest $caps
if($request.Action -ne 'join' -or $request.Server -cne 'CAPS' -or $request.Channel -cne 'geral' -or $request.AwaitReply -or $request.NextDialog){throw ('One sentence CAPS/Geral was not fully understood: '+($request|ConvertTo-Json -Compress -Depth 4))}
$script:messages.Clear()
Ask-Cove $caps -FromVoice -Confidence 1
if($script:aiCalls -or @($script:messages|Where-Object{$_ -match 'Em qual servidor|Qual e o nome da call'}).Count){throw 'CAPS/Geral asked for information already supplied'}
'OK: 13 natural requests, including the complete CAPS/geral sentence, exercised Ask-Cove without calling the AI or opening Discord; negations, explanations and game opening preserved.'
