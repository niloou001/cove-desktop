$ErrorActionPreference='Stop'
Add-Type @'
using System.Threading;using System.Threading.Tasks;
namespace CoveApp {
 public static class DiscordCall { public static string Recipient,Body,DiagnosticFile;public static int Sends;public static Task<string> SendFriendMessage(string who,string body,bool mouse,CancellationToken token){Recipient=who;Body=body;Sends++;return Task.FromResult("stub-discord");} }
 public static class Messaging { public static string Recipient,Body,DraftDirectory;public static int Sends,WebSends;public static Task<string> SendWhatsAppWeb(string who,string body,string chrome,CancellationToken token){Recipient=who;Body=body;WebSends++;return Task.FromResult("stub-web");}public static Task<string> SendWhatsApp(string who,string body,CancellationToken token){Recipient=who;Body=body;Sends++;return Task.FromResult("stub-whatsapp");} }
}
'@
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveDiscordLinks.ps1"
. "$PSScriptRoot\CoveMessages.ps1"
$script:discordCancel=New-Object Threading.CancellationTokenSource
function Get-CoveChromePath {return 'C:\fixture\chrome.exe'}
try{
 foreach($phrase in @('mande mensagem para Ester no WhatsApp Web dizendo Ate logo!','mande mensagem no WhatsApp Web para Ester: Ate logo!','envie mensagem para Ester no whatssap web falando Ate logo!')){
  $web=Invoke-CoveMessageRequest $phrase -DryRun
  if($web.Platform -cne 'WhatsApp Web' -or $web.Recipient -cne 'Ester' -or $web.Body -cne 'Ate logo!' -or $web.Task){throw "Web parsing: $phrase -> $($web|ConvertTo-Json -Compress)"}
 }
 foreach($phrase in @('Cove mande mensagem para o contato Ester no WhatsApp falando q gosta dela','manda uma mensagem no WhatsApp para Ester dizendo que gosta dela','envie mensagem pra Ester falando que gosta dela no WhatsApp')){
  $r=Invoke-CoveMessageRequest $phrase -DryRun
  if($r.Action -ne 'send' -or $r.Recipient -cne 'Ester' -or $r.Platform -cne 'WhatsApp' -or $r.Body -cne 'Eu gosto de voce.' -or $r.Task){throw "Natural request: $phrase -> $($r|ConvertTo-Json -Compress)"}
 }
 $r=Invoke-CoveMessageRequest 'mande mensagem para Ester no Discord: Oi, tudo bem?' -DryRun
 if($r.Body -cne 'Oi, tudo bem?' -or $r.Platform -cne 'Discord'){throw 'Exact content changed'}
 foreach($phrase in @('manda pro meu amigo Ester no Discord que oi!','diga para Ester no Discord que oi!','mande mensagem para Ester no Discord e fale oi!','manda "oi!" para Ester no Discord')){
  $r=Invoke-CoveMessageRequest $phrase -DryRun
  if($r.Action -ne 'send' -or $r.Recipient -cne 'Ester' -or $r.Platform -cne 'Discord' -or $r.Body -cne 'oi!'){throw "Spoken form fell through: $phrase -> $($r|ConvertTo-Json -Compress)"}
 }
 $r=Invoke-CoveMessageRequest 'manda um oi para Ester no Discord' -DryRun
 if($r.Body -cne 'oi' -or $r.Recipient -cne 'Ester' -or $r.Action -ne 'send'){throw 'Short greeting request'}
 $r=Invoke-CoveMessageRequest 'mande mensagem para Ester no Discord dizendo "Oi e fale com ela!"' -DryRun
 if($r.Body -cne 'Oi e fale com ela!'){throw 'Message body treated as another command'}
 $r=Invoke-CoveMessageRequest 'mande mensagem para Ester dizendo "gosta dela"' -DryRun
 if($r.Body -cne 'gosta dela' -or -not $r.AwaitReply){throw 'Quoted text changed or missing platform ignored'}
 foreach($phrase in @('nao mande mensagem para Ester no Discord falando oi','como enviar mensagem para Ester','o site disse mande mensagem para Ester')){if((Invoke-CoveMessageRequest $phrase -DryRun).Handled){throw 'Indirect message request accepted'}}
 $r=Invoke-CoveMessageRequest 'mande mensagem para Ester falando que gosta dela'
 if(-not $r.AwaitReply -or $r.NextDialog.Stage -ne 'platform' -or [CoveApp.Messaging]::Sends -or [CoveApp.DiscordCall]::Sends){throw 'Missing platform caused send'}
 $r=Invoke-CoveMessageRequest 'WhatsApp'
 if($r.Task.GetAwaiter().GetResult() -cne 'stub-whatsapp' -or [CoveApp.Messaging]::Recipient -cne 'Ester' -or [CoveApp.Messaging]::Body -cne 'Eu gosto de voce.'){throw 'Platform followup lost recipient/text'}
 $r=Invoke-CoveMessageRequest 'mande mensagem para Ester no Discord dizendo oi'
 if($r.Task.GetAwaiter().GetResult() -cne 'stub-discord' -or [CoveApp.DiscordCall]::Sends -ne 1){throw 'Discord routing'}
 if([CoveApp.DiscordCall]::DiagnosticFile -cne (Join-Path $PSScriptRoot 'cove-discord-diagnostico.log')){throw 'Message controller has no diagnostic destination'}
 foreach($phrase in @('agora diz pra ela que cheguei!','manda tambem que cheguei!','diga que cheguei!','Cove, agora pode dizer pra ela que cheguei!')){
  $follow=Invoke-CoveMessageRequest $phrase -DryRun
  if($follow.Recipient -cne 'Ester' -or $follow.Platform -cne 'Discord' -or $follow.Body -cne 'cheguei!' -or $follow.AwaitReply){throw "Lost conversation context: $phrase"}
 }
 $follow=Invoke-CoveMessageRequest 'manda a mesma mensagem para Ana' -DryRun
 if($follow.Recipient -cne 'Ana' -or $follow.Platform -cne 'Discord' -or $follow.Body -cne 'oi'){throw 'Same message followup'}
 $savedContext=$script:messageContext;$script:messageContext=$null
 $follow=Invoke-CoveMessageRequest 'diga pra ela que cheguei!' -DryRun
 if(-not $follow.AwaitReply -or $follow.Recipient -or $follow.Body -cne 'cheguei!'){throw 'No-context pronoun must not guess a recipient'}
 $script:messageContext=$savedContext
 $script:lastConversationalAnswer=[pscustomobject]@{Text='Fico feliz de conversar com voce!';Until=[datetime]::Now.AddMinutes(21)}
 $follow=Invoke-CoveMessageRequest 'mande essa resposta para Ana no Discord' -DryRun
 if($follow.Recipient -cne 'Ana' -or $follow.Platform -cne 'Discord' -or $follow.Body -cne 'Fico feliz de conversar com voce!'){throw 'Send this response lost composed text'}
 $script:lastConversationalAnswer=$null
 $r=Invoke-CoveMessageRequest 'mande mensagem para Ester no WhatsApp'
 if($r.NextDialog.Stage -ne 'body'){throw 'Missing body'}
 $r=Invoke-CoveMessageRequest 'cancela'
 if($r.Action -or $r.Task -or $script:messageDialog){throw 'Cancelled message remains active'}
 $web=Invoke-CoveMessageRequest 'mande mensagem para Ester no WhatsApp Web dizendo Ate logo!'
 if($web.Task.GetAwaiter().GetResult() -cne 'stub-web' -or [CoveApp.Messaging]::WebSends -ne 1 -or [CoveApp.Messaging]::Body -cne 'Ate logo!'){throw 'Web request did not select web controller'}
 'OK: natural messages, recipient/platform/body, literal quotes, one-question followup, cancellation, negative requests, no real sends.'
}finally{$script:discordCancel.Dispose()}
