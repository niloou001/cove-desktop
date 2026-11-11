$ErrorActionPreference='Stop'
Add-Type @'
using System.Threading;
using System.Threading.Tasks;
namespace CoveApp {
 public static class DiscordCall {
  public static string DiagnosticFile,Server,Channel;
  public static int MouseCalls,OtherCalls,PrivateCalls;
  public static Task<string> CallFriend(string friend,bool mouse,CancellationToken token){if(!mouse)throw new System.Exception("Mouse not selected");PrivateCalls++;Channel=friend;return Task.FromResult("private");}
  public static Task<string> JoinMouse(string url,string server,string channel,CancellationToken token){MouseCalls++;Server=server;Channel=channel;return Task.FromResult("mouse");}
  public static Task<string> Join(string url,string server,string channel,CancellationToken token){OtherCalls++;return Task.FromResult("other");}
 }
}
'@
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveDiscord.ps1"
$file=Join-Path $PSScriptRoot ('mouse-route-test-'+[guid]::NewGuid().ToString('N')+'.json')
$original=$script:coveDiscordLinksFile
$script:coveDiscordLinksFile=$file;$script:discordCancel=New-Object Threading.CancellationTokenSource
try{
 if((Get-CoveDiscordLinks).Method -cne 'mouse'){throw 'Mouse is not the default method'}
 Save-CoveDiscordLinks ([pscustomobject]@{Method='mouse';Channels=@()})
 $request=Invoke-CoveDiscordRequest 'Cove entre no servidor chamado CAPS e entra na call geral'
 if($request.Task.GetAwaiter().GetResult() -cne 'mouse' -or [CoveApp.DiscordCall]::MouseCalls -ne 1 -or [CoveApp.DiscordCall]::OtherCalls -ne 0){throw 'Request did not reach mouse controller'}
 if([CoveApp.DiscordCall]::Server -cne 'CAPS' -or [CoveApp.DiscordCall]::Channel -cne 'geral' -or $request.NeedsCallLink){throw 'Destination changed or link required'}
 Invoke-CoveDiscordRequest 'entre na call Geral no servidor CAPS' -DryRun|Out-Null
 if([CoveApp.DiscordCall]::MouseCalls -ne 1){throw 'Preview started mouse controller'}
 $private=Invoke-CoveDiscordRequest 'Cove liga para Joao no Discord'
 if($private.Task.GetAwaiter().GetResult() -cne 'private' -or [CoveApp.DiscordCall]::PrivateCalls -ne 1 -or [CoveApp.DiscordCall]::Channel -cne 'Joao'){throw 'Private action was not dispatched'}
 'OK: full CAPS/geral request selects mouse controller by default, without link, AI or old controller. External effects stubbed.'
}finally{$script:discordCancel.Dispose();$script:coveDiscordLinksFile=$original;if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
