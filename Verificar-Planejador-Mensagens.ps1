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
 public static class Messaging {public static string DraftDirectory;public static Task<string> SendWhatsApp(string recipient,string body,CancellationToken token){throw new System.Exception("Unexpected platform");}}
}
'@
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveDiscord.ps1"
. "$PSScriptRoot\CoveMessages.ps1"
. "$PSScriptRoot\CoveMessagePlanner.ps1"
function Write-CoveActionTrace {}
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
 if($body.instructions -cne (Get-CoveMessagePlannerInstructions) -or $body.input.Count -ne 1 -or $body.input[0].content -cne $phrase){throw 'Planner not isolated from chat history'}
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
foreach($text in @('nao mande uma mensagem no Discord','como mandar uma mensagem no Discord','ele disse envie mensagem','faz login no Discord','entre na call no servidor CAPS')){if(Test-CoveUnparsedMessageIntent $text){throw "Not a message instruction: $text"}}
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
'OK: actual Ask-Cove uses isolated structured intent, suppresses planner speech, dispatches local sender once, blocks chat refusal/invalid plans, preserves missing-data dialog. All sends stubbed.'
