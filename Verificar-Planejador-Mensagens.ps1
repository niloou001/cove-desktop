$ErrorActionPreference='Stop'
Add-Type @'
using System.Collections.Concurrent;using System.Threading;using System.Threading.Tasks;
namespace CoveTests {
 public sealed class MessageAccount {
  public bool Connected=true;public string Body;public int Calls;
  public ConcurrentQueue<string> TextDeltas=new ConcurrentQueue<string>();
  public Task<string> Ask(string body,CancellationToken token){Body=body;Calls++;return Task.FromResult("{\"recipient\":\"Ester\",\"platform\":\"Discord\",\"body\":\"Oi!\"}");}
 }
}
namespace CoveApp {
 public static class DiscordCall {public static int Sends;public static string Recipient,Body,DiagnosticFile;public static Task<string> SendFriendMessage(string recipient,string body,bool mouse,CancellationToken token){Sends++;Recipient=recipient;Body=body;return Task.FromResult("fixture-send");}}
 public static class Messaging {public static string DraftDirectory,Recipient,Body;public static int WebSends;public static Task<string> SendWhatsAppWeb(string recipient,string body,string chrome,CancellationToken token){WebSends++;Recipient=recipient;Body=body;return Task.FromResult("fixture-web");}public static Task<string> SendWhatsApp(string recipient,string body,CancellationToken token){throw new System.Exception("Unexpected platform");}}
}
'@
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveDiscord.ps1"
. "$PSScriptRoot\CoveMessages.ps1"
. "$PSScriptRoot\CoveShortcuts.ps1"
. "$PSScriptRoot\CoveMessagePlanner.ps1"
function Write-CoveActionTrace {}
function Get-CoveChromePath {return 'C:\fixture\chrome.exe'}
function Invoke-CoveComputerRequest {throw 'Message escaped to computer handler'}
function Invoke-CoveFileRequest {throw 'Message escaped to file handler'}
function Invoke-CoveAppRequest {throw 'Message escaped to app handler'}
function Invoke-CoveOnlineRequest {throw 'Message escaped to online handler'}
function Add-Message {param($Who,$Text) $script:shown+=@($Text)}
function Say {param($Text) $script:spoken+=@($Text)}
function Update-Capture {}
$voiceEngine=[pscustomobject]@{};$voiceEngine|Add-Member ScriptMethod Stop {}
$sendButton=[pscustomobject]@{IsEnabled=$true}
$script:speechQueue=New-Object 'Collections.Generic.Queue[string]'
$script:account=New-Object CoveTests.MessageAccount;$script:mode='chatgpt';$script:task=$null;$script:loginTask=$null;$script:discordTask=$null;$script:transcribeTask=$null;$script:history=@();$script:shown=@();$script:spoken=@()
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\Cove-Voice.ps1",[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Ask-Cove'},$true)
. ([scriptblock]::Create($node.Extent.Text))
foreach($phrase in @('me envie uma mensagem para Ester pelo Discord dizendo Oi!','mande no Discord um recado para Ester: Oi!')){
 if(-not (Test-CoveUnparsedMessageIntent $phrase)){throw "Missed send intent: $phrase"}
 Ask-Cove $phrase
 if(-not $script:messagePlanPending -or $script:streamActive -or -not $script:task){throw 'Message used chat mode or spoke planner JSON'}
 $body=$script:account.Body|ConvertFrom-Json
 if($body.instructions -cne (Get-CoveMessagePlannerInstructions) -or $body.input.Count -ne 1 -or $body.input[0].content -cne (Get-CoveMessagePlannerInput $phrase)){throw 'Planner must receive only current request and pending message context'}
 $r=Invoke-CoveMessagePlanResponse ($script:task.GetAwaiter().GetResult()) -OriginalRequest $phrase
 if($r.Task.GetAwaiter().GetResult() -cne 'fixture-send' -or [CoveApp.DiscordCall]::Recipient -cne 'Ester' -or [CoveApp.DiscordCall]::Body -cne 'Oi!'){throw 'Structured plan did not reach local sender'}
 $script:task=$null;$script:discordCancel.Dispose();$script:discordCancel=$null;$script:cancel.Dispose();$script:cancel=$null
}
if([CoveApp.DiscordCall]::Sends -ne 2 -or $script:spoken.Count){throw 'Duplicate sends or planner spoken'}
Set-CoveMessageState ([pscustomobject]@{Recipient='Ester';Platform='Discord'}) 'sent' 'fixture verified send'
$before=$script:account.Calls
Ask-Cove 'mandou a mensagem?'
if($script:account.Calls -ne $before -or $script:spoken[-1] -cne 'Sim, a mensagem foi enviada para Ester no Discord.'){throw 'Verified send status fell through to AI'}
Set-CoveMessageState ([pscustomobject]@{Recipient='Ester';Platform='Discord'}) 'failed' 'fixture blocked'
$r=Get-CoveMessageStatusRequest 'enviou?'
if($r.Message -notlike '*fixture blocked*' -or $r.Message -like 'Sim*'){throw 'Failure reported as success'}
foreach($text in @('nao mande uma mensagem no Discord','como mandar uma mensagem no Discord','ele disse envie mensagem','faz login no Discord','entre na call no servidor CAPS','nao entre no WhatsApp Web e mande mensagem para Ester','como entrar no WhatsApp Web e mandar mensagem para Ester')){if(Test-CoveUnparsedMessageIntent $text){throw "Not a message instruction: $text"}}
if(-not (Test-CoveUnparsedMessageIntent 'voce manda uma mensagem para Ester no Discord dizendo Oi!')){throw 'Spoken voce-prefix escaped action router'}
foreach($bad in @('Nao tenho confirmacao do aplicativo.','{"recipient":"Ester","platform":"Email","body":"oi"}','{"recipient":"Ester","platform":"Discord","body":"oi","command":"anything"}','[{"recipient":"Ester","platform":"Discord","body":"oi"}]')){
 $blocked=$false;try{ConvertFrom-CoveMessagePlan $bad|Out-Null}catch{$blocked=$true};if(-not $blocked){throw 'Invalid plan executed'}
}
$script:messageContext=$null
$r=Invoke-CoveMessagePlanResponse '{"recipient":"Ester","platform":"","body":"Oi!"}'
if(-not $r.AwaitReply -or $r.NextDialog.Stage -ne 'platform' -or $r.Task -or [CoveApp.DiscordCall]::Sends -ne 2){throw 'Missing data caused a send'}
$r=ConvertFrom-CoveMessagePlan '{"recipient":"Ester","platform":"Discord","body":"Oi!"}' -OriginalRequest 'me mande uma mensagem dizendo Oi!'
if($r.Action -or $r.Recipient -or $r.Platform){throw 'Invented contact/platform accepted'}
$r=ConvertFrom-CoveMessagePlan '{"recipient":"Ester","platform":"Discord","body":"different"}' -OriginalRequest 'me envie uma mensagem para Ester no Discord dizendo "Oi, tudo bem?"'
if($r.Body -cne 'Oi, tudo bem?'){throw 'Literal quoted message changed'}
$r=ConvertFrom-CoveMessagePlan '{"recipient":"Ester","platform":"WhatsApp","body":"Oi!"}' -OriginalRequest 'me envie um recado para Ester no WhatsApp Web dizendo Oi!'
if($r.Platform -cne 'WhatsApp Web'){throw 'Explicit web request rerouted to desktop'}
$script:messageDialog=$null;$script:task=$null;$before=[CoveApp.DiscordCall]::Sends
Ask-Cove 'mande mensagem para Ester no Discord dizendo Oi!' -FromVoice -Confidence 0.4
if(-not $script:pendingMessageText -or [CoveApp.DiscordCall]::Sends -ne $before){throw 'Unclear speech sent without confirmation'}
Ask-Cove 'sim' -FromVoice -Confidence 0.55
if([CoveApp.DiscordCall]::Sends -ne $before+1 -or [CoveApp.DiscordCall]::Body -cne 'Oi!' -or $script:pendingMessageText){throw 'Simple confirmation did not reuse the captured full message'}
if($script:history[-1].content -notlike '*Ester*'){throw 'Local request missing from conversational history'}
if($script:discordCancel){$script:discordCancel.Dispose();$script:discordCancel=$null};$script:discordTask=$null
foreach($phrase in @('mande mensagem para Ester no WhatsApp Web dizendo Oi!','entra no WhatsApp Web e manda mensagem para Ester dizendo Oi!','vai no whatssap web e manda para Ester falando Oi!')){
 $calls=$script:account.Calls;$sends=[CoveApp.Messaging]::WebSends
 Ask-Cove $phrase
 if(-not $script:discordTask -or $script:messagePlanPending -or $script:account.Calls -ne $calls -or [CoveApp.Messaging]::WebSends -ne $sends+1 -or [CoveApp.Messaging]::Recipient -cne 'Ester' -or [CoveApp.Messaging]::Body -cne 'Oi!'){throw 'Web message escaped local browser controller'}
 $script:discordCancel.Dispose();$script:discordCancel=$null;$script:discordTask=$null
}
foreach($claim in @('Pronto, enviei a mensagem para Ester.','Sim, mandei no WhatsApp Web.','A mensagem foi enviada.')){if(-not (Test-CoveUnverifiedSendClaim $claim)){throw 'Unverified chat send claim accepted'}}
$calls=$script:account.Calls;$sends=[CoveApp.Messaging]::WebSends
Ask-Cove 'voce entendeu errado, e para mandar mensagem para um contato chamado Ester'
if($script:discordTask -or $script:account.Calls -ne $calls -or [CoveApp.Messaging]::WebSends -ne $sends -or $script:messageDialog.Stage -ne 'confirm' -or $script:messageDialog.Platform -cne 'WhatsApp Web' -or $script:messageDialog.Recipient -cne 'Ester' -or $script:messageDialog.Body -cne 'Oi!'){throw 'Correction escaped local route or changed contact/body/platform'}
Ask-Cove 'pode enviar'
if(-not $script:discordTask -or [CoveApp.Messaging]::WebSends -ne $sends+1 -or [CoveApp.Messaging]::Body -cne 'Oi!'){throw 'Confirmation failed to reuse corrected web request'}
$script:discordCancel.Dispose();$script:discordCancel=$null;$script:discordTask=$null
foreach($safe in @('Vou enviar a mensagem.','Nao enviei a mensagem.','Como enviar uma mensagem?')){if(Test-CoveUnverifiedSendClaim $safe){throw 'Non-success chat text blocked'}}
Set-CoveMessageState ([pscustomobject]@{Recipient='Ester';Platform='WhatsApp Web'}) 'sent' 'verified fixture'
foreach($phrase in @('qual o resultado do envio local?','nao recebi um resultado do envio local','e ai, mandou a mensagem?','ja enviou no WhatsApp Web?','deu certo?')){
 $calls=$script:account.Calls;Ask-Cove $phrase
 if($script:account.Calls -ne $calls -or $script:spoken[-1] -notlike '*enviada para Ester no WhatsApp Web*'){throw "Status escaped local result: $phrase"}
}
if(-not (Test-CoveUnverifiedSendClaim 'Nao recebi um resultado do envio local.')){throw 'AI deferral not intercepted'}
if(-not (Test-CoveUnverifiedSendClaim 'Nao tenho resultado local desse envio.')){throw 'Local-result deferral not intercepted'}
if((Get-CoveUnverifiedSendNotice) -notlike '*enviada para Ester no WhatsApp Web*'){throw 'AI deferral ignored verified state'}
$script:messageDialog=[pscustomobject]@{Stage='confirm';Recipient='Ester';Platform='WhatsApp Web';Body='Oi!';Until=[datetime]::Now.AddMinutes(5)}
$snapshot=Get-CoveMessageSession|ConvertTo-Json -Depth 10|ConvertFrom-Json
$script:lastMessageState=$null;$script:messageContext=$null;$script:messageDialog=$null
$sends=[CoveApp.Messaging]::WebSends
Restore-CoveMessageSession $snapshot
if($script:lastMessageState.Phase -cne 'sent' -or $script:messageDialog.Body -cne 'Oi!' -or $script:messageDialog.Platform -cne 'WhatsApp Web' -or [CoveApp.Messaging]::WebSends -ne $sends){throw 'Reload lost result/pending message or automatically resent'}
$snapshot.State.Phase='running';Restore-CoveMessageSession $snapshot
if($script:lastMessageState.Phase -cne 'interrupted' -or (Get-CoveMessageStatusRequest 'enviou').Message -notlike '*reiniciado*' -or [CoveApp.Messaging]::WebSends -ne $sends){throw 'Restarted running task claimed success or resent'}
$snapshot.Dialog.Until=[datetime]::Now.AddMinutes(-1).ToString('o');$script:messageDialog=$null;Restore-CoveMessageSession $snapshot
if($script:messageDialog){throw 'Expired pending message restored'}
$script:messageDialog=$null
$script:messageContext=[pscustomobject]@{Recipient='Wrong name';Platform='WhatsApp Web';Body='Recado preservado';Until=[datetime]::Now.AddMinutes(20)}
Set-CoveMessageState ([pscustomobject]@{Recipient='Wrong name';Platform='WhatsApp Web'}) 'failed' 'Nao encontrei um contato unico chamado Wrong name.'
if($script:messageDialog.Stage -ne 'recipient' -or $script:messageDialog.Body -cne 'Recado preservado'){throw 'Missing contact did not preserve a pending correction'}
$next=Get-CoveMessageRequest 'nao, o nome correto e Ana'
if($next.Action -cne 'send' -or $next.Recipient -cne 'Ana' -or $next.Body -cne 'Recado preservado' -or $next.Platform -cne 'WhatsApp Web'){throw 'Natural name correction did not resume pending send'}
$next=Get-CoveMessageRequest 'Ana'
if($next.Action -cne 'send' -or $next.Recipient -cne 'Ana'){throw 'Bare corrected name lost pending send'}
$script:messageDialog=$null
foreach($phrase in @('consegue enviar esse recado para ela?','tenta novamente por favor','corrige o nome que eu falei')){if(-not (Test-CoveUnparsedMessageIntent $phrase)){throw "Natural follow-up escaped planner: $phrase"}}
$planned=Get-CoveMessagePlannerInput 'tenta novamente por favor'|ConvertFrom-Json
if($planned.pendingMessage.body -cne 'Recado preservado' -or $planned.pendingMessage.platform -cne 'WhatsApp Web'){throw 'Planner lost pending message context'}
if(-not (Get-CoveMessageStatusRequest 'gera o resultado desse envio').Handled){throw 'Status request escaped to chat'}
'OK: local routes, pending contact correction, contextual planner, status, sequential requests and no automatic resend. All sends stubbed.'
