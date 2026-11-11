$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveDiscord.ps1"
Add-Type -Path @("$PSScriptRoot\CoveComputer.cs","$PSScriptRoot\CoveDiscord.cs","$PSScriptRoot\CoveMessaging.cs") -ReferencedAssemblies UIAutomationClient,UIAutomationTypes,WindowsBase,System.Security
foreach($phrase in @('Cove liga para Joao no Discord','entre na call com Joao','inicie uma chamada com Joao no privado','chama Joao no privado','Cove faz uma ligacao para Joao','faca uma chamada de voz para Joao no Discord','chame Joao no discord','iniciar ligacao para Joao','faça uma ligação para Joao no Discord')){
 $r=Invoke-CoveDiscordRequest $phrase -DryRun
 if($r.Action -ne 'private' -or $r.Friend -cne 'Joao' -or $r.Task -or $r.AwaitReply){throw "Private destination: $phrase -> $($r|ConvertTo-Json -Compress)"}
}
foreach($server in @('CAPS','Outro servidor','Amigos 2026')){
 $r=Invoke-CoveDiscordRequest "entre no servidor $server e entra na call Geral" -DryRun
 if($r.Action -ne 'join' -or $r.Server -cne $server -or $r.Channel -cne 'Geral'){throw "Arbitrary guild: $server"}
}
foreach($phrase in @('nao ligue para Joao','como ligar para Joao','nao quero entrar na call com Joao')){if((Invoke-CoveDiscordRequest $phrase -DryRun).Handled){throw "Indirect request: $phrase"}}
$r=Invoke-CoveDiscordRequest 'iniciar chamada com alguem' -DryRun
if(-not $r.AwaitReply -or $r.NextDialog.Stage -ne 'friend'){throw 'Missing friend must be clarified'}
$r=Get-CoveDiscordRequest 'Joao' $r.NextDialog
if($r.Friend -cne 'Joao' -or $r.Action -ne 'private'){throw 'Friend follow-up'}
if(-not [CoveApp.DiscordCall]::IsPrivateResult('Joao','Joao user','Joao')){throw 'User rejected'}
foreach($metadata in @('Joao server','Joao user group','Joao servidor','Joao')){if([CoveApp.DiscordCall]::IsPrivateResult('Joao',$metadata,'Joao')){throw "Non-user result: $metadata"}}
if([CoveApp.DiscordCall]::IsPrivateResult('Joao2','user','Joao')){throw 'Wrong friend accepted'}
if([CoveApp.DiscordCall]::IsPrivateVoiceButton('Start Video Call')){throw 'Video accepted'}
if(-not [CoveApp.DiscordCall]::IsPrivateVoiceButton('Iniciar chamada de voz')){throw 'Voice rejected'}
'OK: arbitrary guilds, private requests and follow-up, negative requests, exact user identity, group/server rejection and voice-only buttons. No real call made.'
