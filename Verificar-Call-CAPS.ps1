$ErrorActionPreference='Stop'
. "$PSScriptRoot\CoveApps.ps1"
. "$PSScriptRoot\CoveDiscord.ps1"
foreach($phrase in @('entra na call geral no servidor CAPS no Discord','entre na call geral no servidor caps no dicord','Cove entra no servidor CAPS no Discord e na call geral','entra na call geral do servidor CAPS pelo Discord')){
 $r=Get-CoveDiscordRequest $phrase $null
 if($r.Action -ne 'join' -or $r.Server -ine 'CAPS' -or $r.Channel -ine 'geral' -or $r.AwaitReply){throw ($phrase+': '+($r|ConvertTo-Json -Compress))}
}
$first=Get-CoveDiscordRequest 'entra no servidor CAPS no Discord' $null
$next=Get-CoveDiscordRequest 'geral' $first.NextDialog
if($next.Action -ne 'join' -or $next.Server -ine 'CAPS' -or $next.Channel -ine 'geral'){throw 'Short follow-up lost destination'}
'OK: CAPS/geral, Discord suffix, speech spelling and short follow-up. No real connection.'